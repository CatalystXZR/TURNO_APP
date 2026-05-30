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
-- Turno MVP — Migration 02: RPC Functions
-- All functions run as SECURITY DEFINER so they bypass RLS
-- and operate atomically inside a transaction.
-- =============================================================

-- ── create_booking ───────────────────────────────────────────
-- Called by: BookingService.createBooking(rideId)
-- What it does (all-or-nothing):
--   1. Locks the ride row and validates availability.
--   2. Deducts seat_price from passenger's balance_available.
--   3. Adds seat_price to passenger's balance_held.
--   4. Decrements seats_available on the ride.
--   5. Inserts the booking row.
--   6. Inserts a 'booking_hold' transaction row.
--   Returns: the new booking UUID.

create or replace function public.create_booking(p_ride_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user       uuid := auth.uid();
  v_booking_id uuid;
  v_price      int;
  v_ride_status text;
begin
  -- Auth guard
  if v_user is null then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  -- Lock the ride row and read price / status
  select seat_price, status
    into v_price, v_ride_status
  from rides
  where id = p_ride_id
    and seats_available > 0
    and status = 'active'
  for update;

  if not found then
    raise exception 'ride unavailable' using errcode = 'P0002';
  end if;

  -- Check passenger does not already have an active booking on this ride
  if exists (
    select 1 from bookings
    where ride_id = p_ride_id
      and passenger_id = v_user
      and status = 'reserved'
  ) then
    raise exception 'already booked' using errcode = 'P0003';
  end if;

  -- Deduct from available, add to held — fails if balance insufficient
  update wallets
  set balance_available = balance_available - v_price,
      balance_held      = balance_held      + v_price,
      updated_at        = now()
  where user_id = v_user
    and balance_available >= v_price;

  if not found then
    raise exception 'insufficient balance' using errcode = 'P0004';
  end if;

  -- Decrement seat count
  update rides
  set seats_available = seats_available - 1
  where id = p_ride_id;

  -- Create booking
  insert into bookings (ride_id, passenger_id, amount_total)
  values (p_ride_id, v_user, v_price)
  returning id into v_booking_id;

  -- Ledger entry
  insert into transactions (user_id, booking_id, type, amount, metadata)
  values (
    v_user,
    v_booking_id,
    'booking_hold',
    -v_price,
    jsonb_build_object('ride_id', p_ride_id)
  );

  return v_booking_id;
end $$;

-- ── confirm_boarding ─────────────────────────────────────────
-- Called by: BookingService.confirmBoarding(bookingId)
-- Triggered by passenger pressing "ME SUBÍ AL AUTO".
-- What it does (all-or-nothing):
--   1. Verifies the calling user is the passenger on this booking.
--   2. Moves amount from passenger's balance_held to driver's balance_available.
--   3. Marks booking as 'completed'.
--   4. Inserts two ledger rows: one for passenger (release), one for driver (credit).

create or replace function public.confirm_boarding(p_booking_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_passenger  uuid;
  v_driver     uuid;
  v_amount     int;
begin
  -- Auth guard
  if auth.uid() is null then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  -- Lock booking + join ride to get driver
  select b.passenger_id, r.driver_id, b.amount_total
    into v_passenger, v_driver, v_amount
  from bookings b
  join rides r on r.id = b.ride_id
  where b.id = p_booking_id
    and b.status = 'reserved'
  for update of b;

  if not found then
    raise exception 'booking not found or already processed' using errcode = 'P0005';
  end if;

  -- Only the passenger may confirm their own boarding
  if auth.uid() is distinct from v_passenger then
    raise exception 'forbidden' using errcode = 'P0006';
  end if;

  -- Move funds: passenger held → driver available
  update wallets
  set balance_held = balance_held - v_amount,
      updated_at   = now()
  where user_id = v_passenger;

  update wallets
  set balance_available = balance_available + v_amount,
      updated_at        = now()
  where user_id = v_driver;

  -- Mark booking completed
  update bookings
  set status       = 'completed',
      confirmed_at = now()
  where id = p_booking_id;

  -- Ledger: passenger side (amount = 0, just marks the release event)
  insert into transactions (user_id, booking_id, type, amount, metadata)
  values (
    v_passenger,
    p_booking_id,
    'release_to_driver',
    0,
    jsonb_build_object('driver_id', v_driver)
  );

  -- Ledger: driver side (credit)
  insert into transactions (user_id, booking_id, type, amount, metadata)
  values (
    v_driver,
    p_booking_id,
    'release_to_driver',
    v_amount,
    jsonb_build_object('passenger_id', v_passenger)
  );
end $$;

-- ── cancel_booking ───────────────────────────────────────────
-- Optional MVP helper: passenger cancels before the ride.
-- Refunds balance_held back to balance_available.

create or replace function public.cancel_booking(p_booking_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_passenger uuid;
  v_ride_id   uuid;
  v_amount    int;
  v_departure timestamptz;
begin
  if auth.uid() is null then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  select b.passenger_id, b.ride_id, b.amount_total, r.departure_at
    into v_passenger, v_ride_id, v_amount, v_departure
  from bookings b
  join rides r on r.id = b.ride_id
  where b.id = p_booking_id
    and b.status = 'reserved'
  for update of b;

  if not found then
    raise exception 'booking not found or already processed' using errcode = 'P0005';
  end if;

  if auth.uid() is distinct from v_passenger then
    raise exception 'forbidden' using errcode = 'P0006';
  end if;

  -- Refund held amount back to available
  update wallets
  set balance_held      = balance_held      - v_amount,
      balance_available = balance_available + v_amount,
      updated_at        = now()
  where user_id = v_passenger;

  -- Restore seat
  update rides
  set seats_available = seats_available + 1
  where id = v_ride_id;

  -- Mark cancelled
  update bookings
  set status = 'cancelled'
  where id = p_booking_id;

  -- Ledger: refund
  insert into transactions (user_id, booking_id, type, amount, metadata)
  values (
    v_passenger,
    p_booking_id,
    'refund',
    v_amount,
    jsonb_build_object('ride_id', v_ride_id, 'reason', 'passenger_cancelled')
  );
end $$;

-- Grant execute rights to authenticated users
grant execute on function public.create_booking(uuid)  to authenticated;
grant execute on function public.confirm_boarding(uuid) to authenticated;
grant execute on function public.cancel_booking(uuid)  to authenticated;
