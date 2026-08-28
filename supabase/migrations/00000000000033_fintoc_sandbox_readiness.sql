/**
 *
 * Project: Turno
 *
 * Original Concept: Agustín Puelma, Cristobal Cordova, Carlos Ibarra
 *
 * Software Architecture & Code: Matías Toledo (catalystxzr)
 *
 * Description: Production-grade implementation for UDD carpooling system.
 *
 * Copyright (c) 2026. All rights reserved.
 *
 */

-- =============================================================
-- Turno — Migration 33: Fintoc sandbox readiness
-- =============================================================
-- Prepares the Fintoc integration for sandbox (test mode) end-to-end:
--   1) fintoc_payments.payment_intent_id — correlates payment_intent.*
--      webhook events back to their checkout session.
--   2) credit_wallet_topup v3 — supports the full lifecycle:
--        pending (created by create-topup-intent)
--          -> approved (webhook: pago exitoso)
--          -> failed / expired (webhook: pago fallido o sesion expirada)
--   3) update_fintoc_payment_status — marks failed/expired transitions.
--
-- Idempotency is preserved: crediting twice for the same
-- checkout_session_id is a no-op.
-- =============================================================

-- 1) Correlate payment_intent webhook events with their session
alter table fintoc_payments
  add column if not exists payment_intent_id text;

create index if not exists idx_fintoc_payments_payment_intent
  on fintoc_payments (payment_intent_id)
  where payment_intent_id is not null;

-- Lock down fintoc_payments: only service_role (edge functions) should
-- ever read or write this table. No client-side access.
alter table fintoc_payments enable row level security;

revoke all on table fintoc_payments from anon, authenticated;

-- 2) credit_wallet_topup v3 — pending -> approved transition
create or replace function public.credit_wallet_topup(
  p_user_id               uuid,
  p_amount                int,
  p_external_payment_id   text,
  p_amount_charged        int,
  p_fee_amount            int,
  p_provider              text default 'fintoc'
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

  -- Idempotency: already approved -> no-op
  if exists (
    select 1 from fintoc_payments
    where checkout_session_id = p_external_payment_id
      and status = 'approved'
  ) then
    return;
  end if;

  -- Record the payment as approved (upsert from pending/failed/expired)
  insert into fintoc_payments (
    checkout_session_id,
    user_id,
    amount,
    amount_requested,
    fee_amount,
    amount_charged,
    status,
    currency
  )
  values (
    p_external_payment_id,
    p_user_id,
    p_amount,
    p_amount,
    p_fee_amount,
    p_amount_charged,
    'approved',
    'CLP'
  )
  on conflict (checkout_session_id) do update
    set status          = 'approved',
        amount          = excluded.amount,
        amount_requested = excluded.amount_requested,
        fee_amount      = excluded.fee_amount,
        amount_charged  = excluded.amount_charged;

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
      'provider',            coalesce(nullif(trim(p_provider), ''), 'fintoc'),
      'amount_requested',    p_amount,
      'amount_charged',      p_amount_charged,
      'fee_amount',          p_fee_amount,
      'source',              'fintoc'
    )
  );
end $$;

revoke execute on function public.credit_wallet_topup(uuid, int, text, int, int, text) from public;
revoke execute on function public.credit_wallet_topup(uuid, int, text, int, int, text) from authenticated;
revoke execute on function public.credit_wallet_topup(uuid, int, text, int, int, text) from anon;

-- 3) update_fintoc_payment_status — failed/expired transitions (service role only)
create or replace function public.update_fintoc_payment_status(
  p_checkout_session_id text,
  p_status              text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_status not in ('pending', 'failed', 'expired', 'requires_action') then
    raise exception 'invalid target status' using errcode = 'P0009';
  end if;

  -- Never downgrade an approved payment
  update fintoc_payments
  set status = p_status
  where checkout_session_id = p_checkout_session_id
    and status <> 'approved';
end $$;

revoke execute on function public.update_fintoc_payment_status(text, text) from public;
revoke execute on function public.update_fintoc_payment_status(text, text) from authenticated;
revoke execute on function public.update_fintoc_payment_status(text, text) from anon;
