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
-- Turno — Migration 25: Simplify campuses, drop carrocería,
-- fix pricing (passenger pays 2190 = 2000+190), narrower overlap
-- =============================================================

-- ----------
-- 1) Drop and recreate driver_vehicle_required constraint WITHOUT vehicle_body_type
-- ----------

alter table users_profile drop constraint if exists users_profile_driver_vehicle_required_ck;

alter table users_profile
  add constraint users_profile_driver_vehicle_required_ck
  check (
    role_mode <> 'driver'
    or (
      has_valid_license = true
      and coalesce(trim(vehicle_brand), '') <> ''
      and coalesce(trim(vehicle_model), '') <> ''
      and coalesce(trim(vehicle_version), '') <> ''
      and vehicle_doors is not null
      and vehicle_doors between 2 and 6
      and coalesce(trim(vehicle_plate), '') <> ''
    )
  )
  not valid;

-- ----------
-- 2) Update handle_new_user() trigger — drop vehicle_body_type
-- ----------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.users_profile (
    id,
    full_name,
    role_mode,
    accepted_terms,
    accepted_terms_at,
    terms_version,
    has_valid_license,
    vehicle_brand,
    vehicle_model,
    vehicle_version,
    vehicle_doors,
    vehicle_plate
  )
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)),
    case
      when coalesce(new.raw_user_meta_data->>'role_mode', 'passenger') = 'driver'
      then 'driver'::role_mode
      else 'passenger'::role_mode
    end,
    coalesce((new.raw_user_meta_data->>'accepted_terms')::boolean, false),
    case
      when coalesce((new.raw_user_meta_data->>'accepted_terms')::boolean, false)
      then now()
      else null
    end,
    new.raw_user_meta_data->>'terms_version',
    coalesce((new.raw_user_meta_data->>'has_valid_license')::boolean, false),
    nullif(new.raw_user_meta_data->>'vehicle_brand', ''),
    nullif(new.raw_user_meta_data->>'vehicle_model', ''),
    nullif(new.raw_user_meta_data->>'vehicle_version', ''),
    nullif(new.raw_user_meta_data->>'vehicle_doors', '')::int,
    nullif(upper(replace(new.raw_user_meta_data->>'vehicle_plate', ' ', '')), '')
  )
  on conflict (id) do nothing;

  insert into public.wallets (user_id, balance_available, balance_held)
  values (new.id, 0, 0)
  on conflict (user_id) do nothing;

  return new;
end $$;

-- ----------
-- 3) Fix create_booking: deduct seat_price + platform_fee (2190) from passenger
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
  v_base_price int;
  v_total_charge int;
  v_driver uuid;
  v_departure timestamp;
  v_now timestamp := public.current_chile_time();
begin
  if v_user is null then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  select r.seat_price, r.platform_fee, r.driver_id, r.departure_at
    into v_base_price, v_total_charge, v_driver, v_departure
  from rides r
  where r.id = p_ride_id
    and r.seats_available > 0
    and r.status = 'active'
  for update;

  v_total_charge := v_base_price + v_total_charge; -- seat_price + platform_fee

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
  set balance_available = balance_available - v_total_charge,
      balance_held = balance_held + v_total_charge,
      updated_at = now()
  where user_id = v_user
    and balance_available >= v_total_charge;

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
    v_total_charge,
    'reserved',
    'reserved'
  )
  returning id into v_booking_id;

  insert into transactions (user_id, booking_id, type, amount, metadata)
  values (
    v_user,
    v_booking_id,
    'booking_hold',
    -v_total_charge,
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
    jsonb_build_object('amount_total', v_total_charge)
  );

  return v_booking_id;
end $$;

-- ----------
-- 4) Narrow overlap window from ±2 hours to ±10 minutes (literal overlap)
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
    and r.departure_at >= p_new_departure_at - interval '10 minutes'
    and r.departure_at <= p_new_departure_at + interval '10 minutes'
    and r.id != p_new_ride_id;

  return v_overlap = 0;
end $$;

-- ----------
-- 5) Add UCH university if missing (uses the UUID from Flutter constants)
-- ----------

insert into universities (id, code, name)
values ('11111111-0000-0000-0000-000000000004', 'UCH', 'Universidad de Chile')
on conflict (id) do nothing;

-- ----------
-- 6) Grants
-- ----------

grant execute on function public.check_no_overlapping_booking(uuid, timestamp, uuid) to authenticated;
