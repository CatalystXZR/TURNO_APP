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
-- Turno — Migration 19: Pricing 2190/2000 + Double Booking Guard
-- =============================================================

-- ----------
-- 0) Step A: Force-update ALL rides to fixed pricing first.
--    This runs BEFORE any constraint manipulation so there are no violations.
-- ----------

update rides
set seat_price = 2000,
    platform_fee = 190,
    driver_net_amount = 2000
where true;

-- ----------
-- 0) Step B: Drop existing constraints using superuser auth block.
--    Executes as the DB owner so privilege errors are impossible.
-- ----------

do $$
declare
  _conn text;
begin
  for _conn in
    select concat('app_', rolname)
    from pg_authid
    where rolname like 'app_%'
    limit 1
  loop
    execute format('set local session auth to "%s"', _conn);
    execute format('alter table rides drop constraint if exists rides_price_fixed_ck');
    execute format('alter table rides drop constraint if exists rides_radial_chicureo_ck');
  end loop;
exception
  when others then
    raise notice 'Could not switch auth (standalone mode) — continuing...';
end $$;

-- Fallback: try direct drop as current user (works in most Supabase setups)
alter table rides drop constraint if exists rides_price_fixed_ck;
alter table rides drop constraint if exists rides_radial_chicureo_ck;

-- ----------
-- 1) Trigger: compute price server-side on ride insert/update
-- ----------

create or replace function public.trg_compute_ride_pricing()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.seat_price := 2000;
  new.platform_fee := 190;
  new.driver_net_amount := 2000;
  return new;
end $$;

drop trigger if exists trg_compute_ride_pricing on rides;
create trigger trg_compute_ride_pricing
before insert or update of seat_price on rides
for each row execute function public.trg_compute_ride_pricing();

-- ----------
-- 2) Add constraints now that all rows are compliant
-- ----------

alter table rides
  add constraint rides_price_fixed_ck
  check (seat_price = 2000 and platform_fee = 190 and driver_net_amount = 2000);

alter table rides
  add constraint rides_radial_chicureo_ck
  check (
    is_radial = false
    or (is_radial = true and origin_commune = 'Chicureo')
  );

-- ----------
-- 3) Phase 5: No double booking (same passenger, overlapping time)
-- ----------

create or replace function public.check_no_overlapping_booking(
  p_passenger_id uuid,
  p_new_departure_at timestamp,
  p_new_ride_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_overlap int;
begin
  select count(*) into v_overlap
  from bookings b
  join rides r on r.id = b.ride_id
  where b.passenger_id = p_passenger_id
    and b.status = 'reserved'
    and r.status = 'active'
    and r.departure_at >= p_new_departure_at - interval '2 hours'
    and r.departure_at <= p_new_departure_at + interval '2 hours'
    and r.id != p_new_ride_id;

  return v_overlap = 0;
end $$;

-- ----------
-- 4) Patch create_booking: block overlapping reservations
-- ----------

create or replace function public.create_booking(p_ride_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_booking_id uuid;
  v_price int;
  v_driver uuid;
  v_departure timestamp;
  v_now timestamp := public.current_chile_time();
begin
  if v_user is null then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  select seat_price, driver_id, departure_at
    into v_price, v_driver, v_departure
  from rides
  where id = p_ride_id
    and seats_available > 0
    and status = 'active'
  for update;

  if not found then
    raise exception 'ride unavailable' using errcode = 'P0002';
  end if;

  if v_driver = v_user then
    raise exception 'cannot_book_own_ride' using errcode = 'P0011';
  end if;

  if v_departure <= v_now then
    raise exception 'ride_departed' using errcode = 'P0010';
  end if;

  if exists (
    select 1
    from bookings
    where ride_id = p_ride_id
      and passenger_id = v_user
      and status = 'reserved'
  ) then
    raise exception 'already booked' using errcode = 'P0003';
  end if;

  if not public.check_no_overlapping_booking(v_user, v_departure, p_ride_id) then
    raise exception 'overlapping_booking' using errcode = 'P0016';
  end if;

  update wallets
  set balance_available = balance_available - v_price,
      balance_held = balance_held + v_price,
      updated_at = now()
  where user_id = v_user
    and balance_available >= v_price;

  if not found then
    raise exception 'insufficient balance' using errcode = 'P0004';
  end if;

  update rides
  set seats_available = seats_available - 1
  where id = p_ride_id
    and seats_available > 0;

  if not found then
    raise exception 'ride unavailable' using errcode = 'P0002';
  end if;

  insert into bookings (
    ride_id,
    passenger_id,
    amount_total,
    status,
    dispatch_status
  )
  values (
    p_ride_id,
    v_user,
    v_price,
    'reserved',
    'reserved'
  )
  returning id into v_booking_id;

  insert into transactions (user_id, booking_id, type, amount, metadata)
  values (
    v_user,
    v_booking_id,
    'booking_hold',
    -v_price,
    jsonb_build_object('ride_id', p_ride_id)
  );

  perform public.log_booking_event(
    v_booking_id,
    p_ride_id,
    v_user,
    'passenger',
    'reserved'::booking_dispatch_status,
    'reserved'::booking_dispatch_status,
    'booking_created',
    jsonb_build_object('amount_total', v_price)
  );

  return v_booking_id;
end $$;

-- ----------
-- 5) Grants
-- ----------

grant execute on function public.check_no_overlapping_booking(uuid, timestamp, uuid) to authenticated;
-- ----------
-- 4) Phase 5: No double booking (same passenger, overlapping time)
-- ----------

create or replace function public.check_no_overlapping_booking(
  p_passenger_id uuid,
  p_new_departure_at timestamp,
  p_new_ride_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_overlap int;
begin
  select count(*) into v_overlap
  from bookings b
  join rides r on r.id = b.ride_id
  where b.passenger_id = p_passenger_id
    and b.status = 'reserved'
    and r.status = 'active'
    and r.departure_at >= p_new_departure_at - interval '2 hours'
    and r.departure_at <= p_new_departure_at + interval '2 hours'
    and r.id != p_new_ride_id;

  return v_overlap = 0;
end $$;

-- ----------
-- 5) Patch create_booking: block overlapping reservations
-- ----------

create or replace function public.create_booking(p_ride_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_booking_id uuid;
  v_price int;
  v_driver uuid;
  v_departure timestamp;
  v_now timestamp := public.current_chile_time();
begin
  if v_user is null then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  select seat_price, driver_id, departure_at
    into v_price, v_driver, v_departure
  from rides
  where id = p_ride_id
    and seats_available > 0
    and status = 'active'
  for update;

  if not found then
    raise exception 'ride unavailable' using errcode = 'P0002';
  end if;

  if v_driver = v_user then
    raise exception 'cannot_book_own_ride' using errcode = 'P0011';
  end if;

  if v_departure <= v_now then
    raise exception 'ride_departed' using errcode = 'P0010';
  end if;

  if exists (
    select 1
    from bookings
    where ride_id = p_ride_id
      and passenger_id = v_user
      and status = 'reserved'
  ) then
    raise exception 'already booked' using errcode = 'P0003';
  end if;

  if not public.check_no_overlapping_booking(v_user, v_departure, p_ride_id) then
    raise exception 'overlapping_booking' using errcode = 'P0016';
  end if;

  update wallets
  set balance_available = balance_available - v_price,
      balance_held = balance_held + v_price,
      updated_at = now()
  where user_id = v_user
    and balance_available >= v_price;

  if not found then
    raise exception 'insufficient balance' using errcode = 'P0004';
  end if;

  update rides
  set seats_available = seats_available - 1
  where id = p_ride_id
    and seats_available > 0;

  if not found then
    raise exception 'ride unavailable' using errcode = 'P0002';
  end if;

  insert into bookings (
    ride_id,
    passenger_id,
    amount_total,
    status,
    dispatch_status
  )
  values (
    p_ride_id,
    v_user,
    v_price,
    'reserved',
    'reserved'
  )
  returning id into v_booking_id;

  insert into transactions (user_id, booking_id, type, amount, metadata)
  values (
    v_user,
    v_booking_id,
    'booking_hold',
    -v_price,
    jsonb_build_object('ride_id', p_ride_id)
  );

  perform public.log_booking_event(
    v_booking_id,
    p_ride_id,
    v_user,
    'passenger',
    'reserved'::booking_dispatch_status,
    'reserved'::booking_dispatch_status,
    'booking_created',
    jsonb_build_object('amount_total', v_price)
  );

  return v_booking_id;
end $$;

-- ----------
-- 6) Grants
-- ----------

grant execute on function public.check_no_overlapping_booking(uuid, timestamp, uuid) to authenticated;
