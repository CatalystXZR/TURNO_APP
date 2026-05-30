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
-- Turno — Migration 18: Chile local ride times
-- =============================================================

-- Keep server-side validation in local Chile time.
create or replace function public.current_chile_time()
returns timestamp
language sql
stable
as $$
  select timezone('America/Santiago', now());
$$;

-- Drop trigger first (needed before alter type, and idempotent).
drop trigger if exists trg_validate_ride_departure on rides;

-- Convert published ride times to local wall-clock timestamps (idempotent).
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'rides'
      and column_name = 'departure_at'
      and data_type = 'timestamp with time zone'
  ) then
    alter table public.rides
      alter column departure_at type timestamp without time zone
      using departure_at at time zone 'UTC';
  end if;
end $$;

create or replace function public.trg_validate_ride_departure()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.departure_at <= public.current_chile_time() then
    raise exception 'ride_departed' using errcode = 'P0010';
  end if;

  return new;
end $$;

create trigger trg_validate_ride_departure
before insert or update of departure_at on rides
for each row execute function public.trg_validate_ride_departure();

-- Recreate ride lifecycle helpers using local timestamps.
create or replace function public.set_ride_completed_if_no_open_bookings(
  p_ride_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamp := public.current_chile_time();
begin
  update rides
  set status = 'completed'
  where id = p_ride_id
    and status = 'active'
    and (
      departure_at <= v_now
      or exists (
        select 1
        from bookings b2
        where b2.ride_id = p_ride_id
          and b2.status = 'completed'
      )
    )
    and not exists (
      select 1
      from bookings b
      where b.ride_id = p_ride_id
        and b.status = 'reserved'
    );
end $$;

create or replace function public.expire_past_active_rides()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_updated int;
  v_now timestamp := public.current_chile_time();
begin
  update rides r
  set status = 'completed'
  where r.status = 'active'
    and r.departure_at <= v_now
    and not exists (
      select 1
      from bookings b
      where b.ride_id = r.id
        and b.status = 'reserved'
    );

  get diagnostics v_updated = row_count;
  return v_updated;
end $$;

-- Recreate booking flow RPCs with local-time comparisons.
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

create or replace function public.driver_accept_booking(p_booking_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver uuid := auth.uid();
  v_owner uuid;
  v_ride_id uuid;
  v_status booking_status;
  v_dispatch booking_dispatch_status;
  v_departure timestamp;
  v_now timestamp := public.current_chile_time();
begin
  if v_driver is null then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  select r.driver_id, b.ride_id, b.status, b.dispatch_status, r.departure_at
    into v_owner, v_ride_id, v_status, v_dispatch, v_departure
  from bookings b
  join rides r on r.id = b.ride_id
  where b.id = p_booking_id
  for update of b;

  if not found then
    raise exception 'booking not found or already processed' using errcode = 'P0005';
  end if;

  if v_owner is distinct from v_driver then
    raise exception 'forbidden' using errcode = 'P0006';
  end if;

  if v_status <> 'reserved' then
    raise exception 'booking_not_active' using errcode = 'P0011';
  end if;

  if v_dispatch <> 'reserved' then
    raise exception 'invalid_dispatch_transition' using errcode = 'P0011';
  end if;

  if v_departure <= v_now then
    raise exception 'ride_departed' using errcode = 'P0010';
  end if;

  update bookings
  set dispatch_status = 'accepted',
      driver_accepted_at = coalesce(driver_accepted_at, now())
  where id = p_booking_id;
end $$;

create or replace function public.driver_cancel_ride(
  p_ride_id uuid,
  p_reason text default 'cancelled_by_driver'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver uuid := auth.uid();
  v_booking record;
  v_departure timestamp;
  v_now timestamp := public.current_chile_time();
begin
  if v_driver is null then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from rides where id = p_ride_id and driver_id = v_driver and status = 'active'
  ) then
    raise exception 'forbidden' using errcode = 'P0006';
  end if;

  update rides
  set status = 'cancelled',
      cancel_reason = coalesce(p_reason, 'cancelled_by_driver'),
      cancelled_at = now()
  where id = p_ride_id
  returning departure_at into v_departure;

  for v_booking in
    select id, passenger_id, amount_total
    from bookings
    where ride_id = p_ride_id and status = 'reserved'
    for update
  loop
    update wallets
    set balance_held = balance_held - v_booking.amount_total,
        balance_available = balance_available + v_booking.amount_total,
        updated_at = now()
    where user_id = v_booking.passenger_id;

    update bookings
    set status = 'cancelled'
    where id = v_booking.id;

    insert into transactions (user_id, booking_id, type, amount, metadata)
    values (
      v_booking.passenger_id,
      v_booking.id,
      'refund',
      v_booking.amount_total,
      jsonb_build_object('ride_id', p_ride_id, 'reason', 'driver_cancelled')
    );
  end loop;

  if v_now >= v_departure - interval '2 hours' then
    insert into strikes (driver_id, reason, source, expires_at)
    values (v_driver, 'driver_cancelled_ride', 'driver_cancel', now() + interval '2 months');
  end if;
end $$;

create or replace function public.cancel_booking(p_booking_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_passenger uuid := auth.uid();
  v_booking_passenger uuid;
  v_ride_id uuid;
  v_amount int;
  v_departure timestamp;
  v_dispatch booking_dispatch_status;
  v_now timestamp := public.current_chile_time();
begin
  if v_passenger is null then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  select b.passenger_id, b.ride_id, b.amount_total, r.departure_at, b.dispatch_status
    into v_booking_passenger, v_ride_id, v_amount, v_departure, v_dispatch
  from bookings b
  join rides r on r.id = b.ride_id
  where b.id = p_booking_id
    and b.status = 'reserved'
  for update of b;

  if not found then
    raise exception 'booking not found or already processed' using errcode = 'P0005';
  end if;

  if v_booking_passenger is distinct from v_passenger then
    raise exception 'forbidden' using errcode = 'P0006';
  end if;

  if v_dispatch in ('passenger_boarded', 'in_progress') then
    raise exception 'cannot_cancel_started_trip' using errcode = 'P0011';
  end if;

  if v_now > v_departure + interval '10 minutes' then
    raise exception 'cancel_window_expired' using errcode = 'P0013';
  end if;

  update wallets
  set balance_held = balance_held - v_amount,
      balance_available = balance_available + v_amount,
      updated_at = now()
  where user_id = v_passenger
    and balance_held >= v_amount;

  if not found then
    raise exception 'held_balance_mismatch' using errcode = 'P0012';
  end if;

  update rides
  set seats_available = least(seats_total, seats_available + 1)
  where id = v_ride_id
    and status = 'active';

  update bookings
  set status = 'cancelled',
      dispatch_status = 'cancelled',
      cancelled_at = now(),
      cancelled_by = v_passenger,
      cancel_reason = 'cancelled_by_passenger'
  where id = p_booking_id;

  insert into transactions (user_id, booking_id, type, amount, metadata)
  values (
    v_passenger,
    p_booking_id,
    'refund',
    v_amount,
    jsonb_build_object('ride_id', v_ride_id, 'reason', 'passenger_cancelled')
  );
end $$;

create or replace function public.passenger_report_no_show(
  p_booking_id uuid,
  p_notes text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_passenger uuid := auth.uid();
  v_driver uuid;
  v_ride_id uuid;
  v_amount int;
  v_departure timestamp;
  v_now timestamp := public.current_chile_time();
begin
  if v_passenger is null then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  select b.passenger_id, b.ride_id, b.amount_total, r.driver_id, r.departure_at
    into v_passenger, v_ride_id, v_amount, v_driver, v_departure
  from bookings b
  join rides r on r.id = b.ride_id
  where b.id = p_booking_id
    and b.status = 'reserved'
    and b.passenger_id = auth.uid()
  for update of b;

  if not found then
    raise exception 'booking not found or already processed' using errcode = 'P0005';
  end if;

  if v_now < v_departure + interval '10 minutes' then
    raise exception 'wait_time_not_elapsed' using errcode = 'P0008';
  end if;

  update wallets
  set balance_held = balance_held - v_amount,
      balance_available = balance_available + v_amount,
      updated_at = now()
  where user_id = v_passenger;

  update rides
  set seats_available = seats_available + 1
  where id = v_ride_id;

  update bookings
  set status = 'no_show',
      reported_no_show_at = now(),
      no_show_notes = p_notes
  where id = p_booking_id;

  insert into transactions (user_id, booking_id, type, amount, metadata)
  values (
    v_passenger,
    p_booking_id,
    'refund',
    v_amount,
    jsonb_build_object('ride_id', v_ride_id, 'reason', 'driver_no_show')
  );

  insert into strikes (driver_id, reason, booking_id, source, expires_at)
  values (v_driver, 'driver_no_show', p_booking_id, 'passenger_report', now() + interval '2 months');
end $$;
