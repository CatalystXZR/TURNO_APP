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
-- Turno MVP — Migration 09: Compliance, pricing and strikes
-- =============================================================

-- ----------
-- Reference data
-- ----------

insert into universities (id, code, name) values
  ('11111111-0000-0000-0000-000000000004', 'UCH',   'Universidad de Chile')
on conflict (id) do update
set code = excluded.code,
    name = excluded.name;

insert into universities (id, code, name) values
  ('11111111-0000-0000-0000-000000000005', 'UNAB',  'Universidad Andres Bello')
on conflict (id) do update
set code = excluded.code,
    name = excluded.name;

insert into universities (id, code, name) values
  ('11111111-0000-0000-0000-000000000006', 'UAI',   'Universidad Adolfo Ibañez')
on conflict (id) do update
set code = excluded.code,
    name = excluded.name;

insert into campuses (id, university_id, name, commune) values
  ('22222222-0006-0000-0000-000000000001', '11111111-0000-0000-0000-000000000004', 'Campus Beauchef', 'Santiago'),
  ('22222222-0006-0000-0000-000000000002', '11111111-0000-0000-0000-000000000004', 'Campus Juan Gomez Millas', 'Nunoa'),
  ('22222222-0006-0000-0000-000000000003', '11111111-0000-0000-0000-000000000004', 'Casa Central', 'Santiago')
on conflict (id) do nothing;

update campuses
set university_id = '11111111-0000-0000-0000-000000000006'
where id in (
  '22222222-0004-0000-0000-000000000001',
  '22222222-0004-0000-0000-000000000002',
  '22222222-0004-0000-0000-000000000003'
);

update campuses
set university_id = '11111111-0000-0000-0000-000000000005'
where id in (
  '22222222-0005-0000-0000-000000000001',
  '22222222-0005-0000-0000-000000000002',
  '22222222-0005-0000-0000-000000000003',
  '22222222-0005-0000-0000-000000000004'
);

-- ----------
-- Profile and compliance fields
-- ----------

alter table users_profile
  add column if not exists accepted_terms boolean not null default false,
  add column if not exists accepted_terms_at timestamptz,
  add column if not exists terms_version text,
  add column if not exists has_valid_license boolean not null default false,
  add column if not exists license_checked_at timestamptz,
  add column if not exists emergency_contact text,
  add column if not exists safety_notes text,
  add column if not exists profile_photo_url text,
  add column if not exists rating_avg numeric(3,2) not null default 5.00,
  add column if not exists rating_count int not null default 0,
  add column if not exists vehicle_suspended_until timestamptz;

alter table users_profile
  add column if not exists vehicle_model text,
  add column if not exists vehicle_plate text,
  add column if not exists vehicle_color text;

-- ----------
-- Ride metadata and pricing
-- ----------

alter table rides
  add column if not exists meeting_point text,
  add column if not exists is_radial boolean not null default false,
  add column if not exists platform_fee int not null default 0,
  add column if not exists driver_net_amount int not null default 0,
  add column if not exists cancel_reason text,
  add column if not exists cancelled_at timestamptz;

create or replace function public.enforce_ride_pricing()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_uni_code text;
  v_price int;
  v_fee int;
begin
  select code into v_uni_code
  from universities
  where id = new.university_id;

  if v_uni_code in ('PUC', 'UCH') then
    v_price := 2500;
    v_fee := round(v_price * case when coalesce(new.is_radial, false) then 0.1525 else 0.1425 end)::int;
  else
    v_price := 2000;
    v_fee := 0;
  end if;

  new.seat_price := v_price;
  new.platform_fee := v_fee;
  new.driver_net_amount := v_price - v_fee;
  return new;
end $$;

drop trigger if exists trg_enforce_ride_pricing on rides;
create trigger trg_enforce_ride_pricing
  before insert or update on rides
  for each row execute function public.enforce_ride_pricing();

-- Compute baseline fee/net for existing rows
update rides
set platform_fee =
      case
        when universities.code in ('PUC', 'UCH')
          then round(rides.seat_price * 0.1425)::int
        else 0
      end,
    driver_net_amount =
      case
        when universities.code in ('PUC', 'UCH')
          then rides.seat_price - round(rides.seat_price * 0.1425)::int
        else rides.seat_price
      end
from universities
where universities.id = rides.university_id;

-- Ensure seat price by university rule for all active rows
update rides
set seat_price = case when universities.code in ('PUC', 'UCH') then 2500 else 2000 end,
    platform_fee = case when universities.code in ('PUC', 'UCH')
                      then round((case when universities.code in ('PUC', 'UCH') then 2500 else 2000 end) *
                           (case when rides.is_radial then 0.1525 else 0.1425 end))::int
                      else 0
                  end,
    driver_net_amount = (case when universities.code in ('PUC', 'UCH') then 2500 else 2000 end) -
                        (case when universities.code in ('PUC', 'UCH')
                           then round((case when universities.code in ('PUC', 'UCH') then 2500 else 2000 end) *
                                 (case when rides.is_radial then 0.1525 else 0.1425 end))::int
                           else 0
                         end)
from universities
where universities.id = rides.university_id;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'rides_seat_price_mvp_ck'
  ) then
    alter table rides
      add constraint rides_seat_price_mvp_ck
      check (seat_price in (2000, 2500));
  end if;
end $$;

-- ----------
-- Booking no-show reporting
-- ----------

alter table bookings
  add column if not exists reported_no_show_at timestamptz,
  add column if not exists no_show_notes text;

-- ----------
-- Strikes metadata
-- ----------

alter table strikes
  add column if not exists expires_at timestamptz,
  add column if not exists source text not null default 'system';

-- ----------
-- Trigger updates for new user defaults
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
    accepted_terms,
    accepted_terms_at,
    terms_version,
    has_valid_license
  )
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)),
    coalesce((new.raw_user_meta_data->>'accepted_terms')::boolean, false),
    case
      when coalesce((new.raw_user_meta_data->>'accepted_terms')::boolean, false)
      then now()
      else null
    end,
    new.raw_user_meta_data->>'terms_version',
    coalesce((new.raw_user_meta_data->>'has_valid_license')::boolean, false)
  )
  on conflict (id) do nothing;

  insert into public.wallets (user_id, balance_available, balance_held)
  values (new.id, 0, 0)
  on conflict (user_id) do nothing;

  return new;
end $$;

-- ----------
-- RPC updates
-- ----------

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
  if v_user is null then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

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

  if exists (
    select 1 from bookings
    where ride_id = p_ride_id
      and passenger_id = v_user
      and status = 'reserved'
  ) then
    raise exception 'already booked' using errcode = 'P0003';
  end if;

  update wallets
  set balance_available = balance_available - v_price,
      balance_held      = balance_held      + v_price,
      updated_at        = now()
  where user_id = v_user
    and balance_available >= v_price;

  if not found then
    raise exception 'insufficient balance' using errcode = 'P0004';
  end if;

  update rides
  set seats_available = seats_available - 1
  where id = p_ride_id;

  insert into bookings (ride_id, passenger_id, amount_total)
  values (p_ride_id, v_user, v_price)
  returning id into v_booking_id;

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
  v_fee        int;
  v_driver_net int;
begin
  if auth.uid() is null then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  select b.passenger_id,
         r.driver_id,
         b.amount_total,
         coalesce(r.platform_fee, 0),
         coalesce(r.driver_net_amount, b.amount_total)
    into v_passenger, v_driver, v_amount, v_fee, v_driver_net
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

  update wallets
  set balance_held = balance_held - v_amount,
      updated_at   = now()
  where user_id = v_passenger;

  update wallets
  set balance_available = balance_available + v_driver_net,
      updated_at        = now()
  where user_id = v_driver;

  update bookings
  set status       = 'completed',
      confirmed_at = now()
  where id = p_booking_id;

  insert into transactions (user_id, booking_id, type, amount, metadata)
  values (
    v_passenger,
    p_booking_id,
    'release_to_driver',
    0,
    jsonb_build_object(
      'driver_id', v_driver,
      'platform_fee', v_fee,
      'driver_net_amount', v_driver_net
    )
  );

  insert into transactions (user_id, booking_id, type, amount, metadata)
  values (
    v_driver,
    p_booking_id,
    'release_to_driver',
    v_driver_net,
    jsonb_build_object('passenger_id', v_passenger)
  );

  if v_fee > 0 then
    insert into transactions (user_id, booking_id, type, amount, metadata)
    values (
      v_driver,
      p_booking_id,
      'platform_fee',
      -v_fee,
      jsonb_build_object('reason', 'mvp_fee_split')
    );
  end if;
end $$;

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

  update wallets
  set balance_held      = balance_held      - v_amount,
      balance_available = balance_available + v_amount,
      updated_at        = now()
  where user_id = v_passenger;

  update rides
  set seats_available = seats_available + 1
  where id = v_ride_id;

  update bookings
  set status = 'cancelled'
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
  v_departure timestamptz;
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

  if now() >= v_departure - interval '2 hours' then
    insert into strikes (driver_id, reason, source, expires_at)
    values (v_driver, 'driver_cancelled_ride', 'driver_cancel', now() + interval '2 months');

    update users_profile
    set strikes_count = strikes_count + 1,
        suspended_until = case
          when strikes_count + 1 >= 2
            then greatest(coalesce(suspended_until, now()), now() + interval '2 months')
          else suspended_until
        end,
        vehicle_suspended_until = case
          when strikes_count + 1 >= 2
            then greatest(coalesce(vehicle_suspended_until, now()), now() + interval '2 months')
          else vehicle_suspended_until
        end
    where id = v_driver;
  end if;
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
  v_departure timestamptz;
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

  if now() < v_departure + interval '10 minutes' then
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

  update users_profile
  set strikes_count = strikes_count + 1,
      suspended_until = case
        when strikes_count + 1 >= 2
          then greatest(coalesce(suspended_until, now()), now() + interval '2 months')
        else suspended_until
      end,
      vehicle_suspended_until = case
        when strikes_count + 1 >= 2
          then greatest(coalesce(vehicle_suspended_until, now()), now() + interval '2 months')
        else vehicle_suspended_until
      end
  where id = v_driver;
end $$;

drop policy if exists "profile_driver_passenger_read" on users_profile;
create policy "profile_driver_passenger_read" on users_profile
  for select
  using (
    exists (
      select 1
      from bookings b
      join rides r on r.id = b.ride_id
      where b.passenger_id = users_profile.id
        and r.driver_id = auth.uid()
    )
  );

drop policy if exists "profile_active_driver_read" on users_profile;
create policy "profile_active_driver_read" on users_profile
  for select
  using (
    exists (
      select 1
      from rides r
      where r.driver_id = users_profile.id
        and r.status = 'active'
    )
  );

drop policy if exists "rides_driver_insert" on rides;
create policy "rides_driver_insert" on rides
  for insert
  with check (
    auth.uid() = driver_id
    and exists (
      select 1
      from users_profile up
      where up.id = auth.uid()
        and up.accepted_terms = true
        and up.has_valid_license = true
        and coalesce(up.suspended_until, now() - interval '1 second') <= now()
    )
  );

grant execute on function public.create_booking(uuid) to authenticated;
grant execute on function public.confirm_boarding(uuid) to authenticated;
grant execute on function public.cancel_booking(uuid) to authenticated;
grant execute on function public.driver_cancel_ride(uuid, text) to authenticated;
grant execute on function public.passenger_report_no_show(uuid, text) to authenticated;
