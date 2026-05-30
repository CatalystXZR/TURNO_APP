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
-- Turno — Migration 15: Wallet reconciliation ledger adjustment
-- =============================================================
-- Goal:
-- - Keep wallet balances as source of truth.
-- - Bring transaction-ledger expected balances in sync with wallet totals.
-- - Do not mutate historical wallet balances in this migration.

-- If held balances are inconsistent, stop and handle manually (high risk).
do $$
declare
  v_held_mismatches int;
begin
  select count(*)::int
    into v_held_mismatches
  from public.wallet_reconciliation_diag(null)
  where held_delta <> 0;

  if v_held_mismatches > 0 then
    raise exception 'held balance mismatches detected (% users). Resolve manually before migration 15', v_held_mismatches
      using errcode = 'P0020';
  end if;
end $$;

with deltas as (
  select
    d.user_id,
    d.available_delta
  from public.wallet_reconciliation_diag(null) d
  where d.available_delta <> 0
),
to_adjust as (
  select
    user_id,
    available_delta,
    case
      when available_delta > 0 then 'refund'::tx_type
      else 'penalty'::tx_type
    end as tx_kind
  from deltas
),
ins as (
  insert into public.transactions (user_id, type, amount, metadata)
  select
    a.user_id,
    a.tx_kind,
    a.available_delta,
    jsonb_build_object(
      'reason', 'wallet_available_reconciliation_migration_15',
      'source', 'migration_15_wallet_reconciliation_adjustment',
      'available_delta', a.available_delta
    )
  from to_adjust a
  returning 1
)
select count(*) from ins;
