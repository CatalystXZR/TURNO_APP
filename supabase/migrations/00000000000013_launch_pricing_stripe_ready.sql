/**
 *
 * Project: Turno
 *
 * Original Concept: Agustin Puelma, Cristobal Cordova, Carlos Ibarra
 *
 * Software Architecture & Code: Matias Toledo (catalystxzr)
 *
 * Description: Production-grade implementation for UDD carpooling system.
 *
 * Copyright (c) 2026. All rights reserved.
 *
 */

-- =============================================================
-- Turno Launch — Migration 13: fixed fee pricing + Stripe-ready topups
-- =============================================================

-- ----------
-- 1) Fixed platform fee for all rides
-- ----------

create or replace function public.enforce_ride_pricing()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_uni_code text;
  v_price int;
  v_fee int := 190;
begin
  select code into v_uni_code
  from universities
  where id = new.university_id;

  if v_uni_code in ('PUC', 'UCH') then
    v_price := 2500;
  else
    v_price := 2000;
  end if;

  new.seat_price := v_price;
  new.platform_fee := v_fee;
  new.driver_net_amount := greatest(v_price - v_fee, 0);
  return new;
end $$;

-- Recompute historical rows using fixed fee
update rides
set seat_price = case
      when universities.code in ('PUC', 'UCH') then 2500
      else 2000
    end,
    platform_fee = 190,
    driver_net_amount = case
      when universities.code in ('PUC', 'UCH') then 2500 - 190
      else 2000 - 190
    end
from universities
where universities.id = rides.university_id;

-- ----------
-- 2) Topup ledger extended for fee-aware and provider-aware flows
-- ----------

alter table mp_payments
  add column if not exists amount_requested int,
  add column if not exists fee_amount int not null default 0,
  add column if not exists amount_charged int,
  add column if not exists provider text not null default 'mercadopago',
  add column if not exists currency text not null default 'CLP';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'mp_payments_amount_requested_positive_ck'
  ) then
    alter table mp_payments
      add constraint mp_payments_amount_requested_positive_ck
      check (coalesce(amount_requested, amount) > 0);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'mp_payments_amount_charged_positive_ck'
  ) then
    alter table mp_payments
      add constraint mp_payments_amount_charged_positive_ck
      check (coalesce(amount_charged, amount) > 0);
  end if;
end $$;

update mp_payments
set amount_requested = coalesce(amount_requested, amount),
    amount_charged = coalesce(amount_charged, amount),
    fee_amount = coalesce(fee_amount, 0),
    provider = coalesce(provider, 'mercadopago'),
    currency = coalesce(currency, 'CLP')
where amount_requested is null
   or amount_charged is null
   or provider is null
   or currency is null;

create index if not exists idx_mp_payments_provider_created
  on mp_payments (provider, created_at desc);

-- ----------
-- 3) RPC for net-credit topup flows (supports Stripe and MP)
-- ----------

create or replace function public.credit_wallet_topup(
  p_user_id             uuid,
  p_amount              int,
  p_external_payment_id text,
  p_amount_charged      int,
  p_fee_amount          int,
  p_provider            text default 'mercadopago'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_amount <= 0 then
    raise exception 'invalid credited amount' using errcode = 'P0009';
  end if;

  if p_amount_charged <= 0 then
    raise exception 'invalid charged amount' using errcode = 'P0009';
  end if;

  if p_fee_amount < 0 then
    raise exception 'invalid fee amount' using errcode = 'P0009';
  end if;

  if p_amount + p_fee_amount <> p_amount_charged then
    raise exception 'charged amount mismatch' using errcode = 'P0009';
  end if;

  if exists (
    select 1 from mp_payments
    where external_payment_id = p_external_payment_id
  ) then
    return;
  end if;

  insert into mp_payments (
    external_payment_id,
    user_id,
    amount,
    amount_requested,
    fee_amount,
    amount_charged,
    provider,
    currency,
    status
  )
  values (
    p_external_payment_id,
    p_user_id,
    p_amount,
    p_amount,
    p_fee_amount,
    p_amount_charged,
    coalesce(nullif(trim(p_provider), ''), 'unknown'),
    'CLP',
    'approved'
  );

  update wallets
  set balance_available = balance_available + p_amount,
      updated_at        = now()
  where user_id = p_user_id;

  if not found then
    raise exception 'wallet not found for user %', p_user_id
      using errcode = 'P0007';
  end if;

  insert into transactions (user_id, type, amount, metadata)
  values (
    p_user_id,
    'topup',
    p_amount,
    jsonb_build_object(
      'external_payment_id', p_external_payment_id,
      'provider',            coalesce(nullif(trim(p_provider), ''), 'unknown'),
      'amount_requested',    p_amount,
      'amount_charged',      p_amount_charged,
      'fee_amount',          p_fee_amount,
      'source',              'payment_provider'
    )
  );
end $$;

revoke execute on function public.credit_wallet_topup(uuid, int, text, int, int, text) from public;
revoke execute on function public.credit_wallet_topup(uuid, int, text, int, int, text) from authenticated;
revoke execute on function public.credit_wallet_topup(uuid, int, text, int, int, text) from anon;

-- Keep old signature for backward compatibility (routes to new fixed-fee shape)
create or replace function public.credit_wallet_topup(
  p_user_id             uuid,
  p_amount              int,
  p_external_payment_id text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.credit_wallet_topup(
    p_user_id,
    p_amount,
    p_external_payment_id,
    p_amount,
    0,
    'mercadopago'
  );
end $$;

revoke execute on function public.credit_wallet_topup(uuid, int, text) from public;
revoke execute on function public.credit_wallet_topup(uuid, int, text) from authenticated;
revoke execute on function public.credit_wallet_topup(uuid, int, text) from anon;
