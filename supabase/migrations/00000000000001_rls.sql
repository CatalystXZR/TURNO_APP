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
-- Turno MVP — Migration 01: Row Level Security
-- =============================================================

-- Enable RLS on every sensitive table
alter table users_profile  enable row level security;
alter table wallets         enable row level security;
alter table rides           enable row level security;
alter table bookings        enable row level security;
alter table transactions    enable row level security;
alter table withdrawals     enable row level security;
alter table strikes         enable row level security;
alter table mp_payments     enable row level security;

-- Public tables — no RLS needed (read-only reference data)
-- universities and campuses are intentionally public.

-- ── users_profile ────────────────────────────────────────────
-- Users can read and write only their own row.
create policy "profile_self_rw" on users_profile
  for all
  using      (auth.uid() = id)
  with check (auth.uid() = id);

-- ── wallets ──────────────────────────────────────────────────
-- Users can only read their own wallet.
-- Writes happen exclusively via security-definer RPCs.
create policy "wallet_self_read" on wallets
  for select
  using (auth.uid() = user_id);

-- ── rides ────────────────────────────────────────────────────
-- Anyone logged-in can browse active rides.
create policy "rides_public_read" on rides
  for select
  using (true);

-- Only the driver can publish a ride for themselves.
create policy "rides_driver_insert" on rides
  for insert
  with check (auth.uid() = driver_id);

-- Only the driver can update/cancel their own ride.
create policy "rides_driver_update" on rides
  for update
  using (auth.uid() = driver_id);

-- ── bookings ─────────────────────────────────────────────────
-- Passengers see their own bookings.
-- Drivers see bookings on their rides.
create policy "bookings_self_read" on bookings
  for select
  using (
    auth.uid() = passenger_id
    or exists (
      select 1 from rides r
      where r.id = ride_id and r.driver_id = auth.uid()
    )
  );

-- Only the passenger inserts their own booking.
-- The actual atomic logic runs in the security-definer RPC.
create policy "bookings_passenger_insert" on bookings
  for insert
  with check (auth.uid() = passenger_id);

-- ── transactions ─────────────────────────────────────────────
-- Users can only read their own ledger rows.
-- All inserts happen via security-definer RPCs — no direct insert allowed.
create policy "tx_self_read" on transactions
  for select
  using (auth.uid() = user_id);

-- ── withdrawals ──────────────────────────────────────────────
-- Drivers can insert and read their own withdrawal requests.
create policy "withdrawals_driver_rw" on withdrawals
  for all
  using      (auth.uid() = driver_id)
  with check (auth.uid() = driver_id);

-- ── strikes ──────────────────────────────────────────────────
-- Drivers can only read their own strikes (issued by admin/system).
create policy "strikes_driver_read" on strikes
  for select
  using (auth.uid() = driver_id);

-- ── mp_payments ──────────────────────────────────────────────
-- Users can read their own payment records.
-- Inserts happen only from the webhook Edge Function (service_role key).
create policy "mp_payments_self_read" on mp_payments
  for select
  using (auth.uid() = user_id);
