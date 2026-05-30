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
-- Turno MVP — Migration 05: Webhook RPC
-- credit_wallet_topup — called exclusively by the Mercado Pago
-- webhook Edge Function using the service_role key.
-- Atomically: records the payment, credits the wallet, writes ledger.
-- Idempotent: safe to retry if webhook fires twice.
-- =============================================================

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
  -- Idempotency guard: do nothing if payment already recorded
  if exists (
    select 1 from mp_payments
    where external_payment_id = p_external_payment_id
  ) then
    return;
  end if;

  -- Record the payment (idempotency key)
  insert into mp_payments (external_payment_id, user_id, amount, status)
  values (p_external_payment_id, p_user_id, p_amount, 'approved');

  -- Credit the wallet
  update wallets
  set balance_available = balance_available + p_amount,
      updated_at        = now()
  where user_id = p_user_id;

  if not found then
    raise exception 'wallet not found for user %', p_user_id
      using errcode = 'P0007';
  end if;

  -- Ledger entry
  insert into transactions (user_id, type, amount, metadata)
  values (
    p_user_id,
    'topup',
    p_amount,
    jsonb_build_object(
      'external_payment_id', p_external_payment_id,
      'source',              'mercadopago'
    )
  );
end $$;

-- Only service_role should call this (webhook uses service_role key)
-- Do NOT grant to authenticated or anon
revoke execute on function public.credit_wallet_topup(uuid, int, text) from public;
revoke execute on function public.credit_wallet_topup(uuid, int, text) from authenticated;
revoke execute on function public.credit_wallet_topup(uuid, int, text) from anon;
-- service_role bypasses RLS/grants, so no explicit grant needed
