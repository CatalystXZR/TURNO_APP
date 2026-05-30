-- =============================================================
-- Turno — Migration 27: Fintoc payments (replace Mercado Pago)
-- =============================================================

-- 1) New table: fintoc_payments (idempotency + audit for Fintoc)
create table if not exists fintoc_payments (
  checkout_session_id text primary key,
  user_id            uuid not null references users_profile(id),
  amount             int  not null,
  amount_requested   int,
  fee_amount         int  not null default 0,
  amount_charged     int,
  status             text not null default 'pending',
  currency           text not null default 'CLP',
  created_at         timestamptz not null default now(),

  constraint fintoc_payments_amount_positive_ck
    check (amount > 0),
  constraint fintoc_payments_amount_requested_positive_ck
    check (coalesce(amount_requested, amount) > 0),
  constraint fintoc_payments_amount_charged_positive_ck
    check (coalesce(amount_charged, amount) > 0)
);

create index if not exists idx_fintoc_payments_user_created
  on fintoc_payments (user_id, created_at desc);

-- 2) Updated credit_wallet_topup (full signature) — uses fintoc_payments
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

  -- Idempotency: skip if already processed
  if exists (
    select 1 from fintoc_payments
    where checkout_session_id = p_external_payment_id
  ) then
    return;
  end if;

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

-- 3) Backward-compat overload (3 params) — also updated for fintoc_payments
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
    'fintoc_legacy'
  );
end $$;

revoke execute on function public.credit_wallet_topup(uuid, int, text) from public;
revoke execute on function public.credit_wallet_topup(uuid, int, text) from authenticated;
revoke execute on function public.credit_wallet_topup(uuid, int, text) from anon;

-- 4) Update delete_user_account to clean fintoc_payments + mp_payments
create or replace function public.delete_user_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'Sesion requerida' using errcode = 'P0001';
  end if;

  delete from bookings where passenger_id = v_user;
  delete from rides where driver_id = v_user;
  delete from transactions where user_id = v_user;
  delete from withdrawals where driver_id = v_user;
  delete from fintoc_payments where user_id = v_user;
  delete from mp_payments where user_id = v_user;
  delete from strikes where driver_id = v_user;
  delete from wallets where user_id = v_user;
  delete from users_profile where id = v_user;
  delete from auth.users where id = v_user;
end $$;

grant execute on function public.delete_user_account() to authenticated;
