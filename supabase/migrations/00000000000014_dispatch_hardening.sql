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
-- Turno — Migration 14: Dispatch hardening + anti-bypass controls
-- =============================================================

-- ----------
-- 1) Security hardening on direct table writes
-- ----------

drop policy if exists "bookings_passenger_insert" on bookings;
drop policy if exists "rides_driver_update" on rides;

-- ----------
-- 2) Booking dispatch lifecycle schema
-- ----------

do $$ begin
  create type booking_dispatch_status as enum (
    'reserved',
    'accepted',
    'driver_arriving',
    'driver_arrived',
    'passenger_boarded',
    'in_progress',
    'completed',
    'cancelled',
    'no_show'
  );
exception when duplicate_object then null; end $$;

alter table bookings
  add column if not exists dispatch_status booking_dispatch_status not null default 'reserved',
  add column if not exists driver_accepted_at timestamptz,
  add column if not exists driver_arriving_at timestamptz,
  add column if not exists driver_arrived_at timestamptz,
  add column if not exists passenger_boarded_at timestamptz,
  add column if not exists trip_started_at timestamptz,
  add column if not exists trip_completed_at timestamptz,
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancelled_by uuid references users_profile(id),
  add column if not exists cancel_reason text;

update bookings
set dispatch_status = case status
    when 'completed' then 'completed'::booking_dispatch_status
    when 'cancelled' then 'cancelled'::booking_dispatch_status
    when 'no_show' then 'no_show'::booking_dispatch_status
    else 'reserved'::booking_dispatch_status
  end;

do $$
begin
  if exists (
    select 1
    from pg_constraint
    where conname = 'idx_bookings_unique_active_passenger_ride'
      and conrelid = 'public.bookings'::regclass
  ) then
    alter table bookings drop constraint idx_bookings_unique_active_passenger_ride;
  end if;

  if exists (
    select 1
    from pg_constraint
    where conname = 'bookings_ride_id_passenger_id_key'
      and conrelid = 'public.bookings'::regclass
  ) then
    alter table bookings drop constraint bookings_ride_id_passenger_id_key;
  end if;
end $$;

create unique index if not exists idx_bookings_unique_active_passenger_ride
  on bookings (ride_id, passenger_id)
  where status = 'reserved';

create index if not exists idx_bookings_dispatch_status
  on bookings (dispatch_status, created_at desc);

create index if not exists idx_bookings_active_by_ride_dispatch
  on bookings (ride_id, dispatch_status)
  where status = 'reserved';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'rides_seats_capacity_ck'
  ) then
    alter table rides
      add constraint rides_seats_capacity_ck
      check (seats_available <= seats_total);
  end if;
end $$;

-- ----------
-- 3) Dispatch event audit log
-- ----------

create table if not exists booking_events (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references bookings(id) on delete cascade,
  ride_id uuid not null references rides(id) on delete cascade,
  actor_user_id uuid references users_profile(id),
  actor_role text not null,
  from_status booking_dispatch_status,
  to_status booking_dispatch_status not null,
  event_type text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_booking_events_booking_created
  on booking_events (booking_id, created_at desc);

create index if not exists idx_booking_events_ride_created
  on booking_events (ride_id, created_at desc);

alter table booking_events enable row level security;

drop policy if exists "booking_events_participant_read" on booking_events;
create policy "booking_events_participant_read" on booking_events
  for select
  using (
    auth.uid() = actor_user_id
    or exists (
      select 1
      from bookings b
      where b.id = booking_id
        and b.passenger_id = auth.uid()
    )
    or exists (
      select 1
      from rides r
      where r.id = ride_id
        and r.driver_id = auth.uid()
    )
  );

-- ----------
-- 4) Helpers
-- ----------

create or replace function public.log_booking_event(
  p_booking_id uuid,
  p_ride_id uuid,
  p_actor_user_id uuid,
  p_actor_role text,
  p_from_status booking_dispatch_status,
  p_to_status booking_dispatch_status,
  p_event_type text,
  p_metadata jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into booking_events (
    booking_id,
    ride_id,
    actor_user_id,
    actor_role,
    from_status,
    to_status,
    event_type,
    metadata
  )
  values (
    p_booking_id,
    p_ride_id,
    p_actor_user_id,
    coalesce(nullif(trim(p_actor_role), ''), 'system'),
    p_from_status,
    p_to_status,
    coalesce(nullif(trim(p_event_type), ''), 'unknown'),
    coalesce(p_metadata, '{}'::jsonb)
  );
end $$;

create or replace function public.set_ride_completed_if_no_open_bookings(
  p_ride_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update rides
  set status = 'completed'
  where id = p_ride_id
    and status = 'active'
    and (
      departure_at <= now()
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
begin
  update rides r
  set status = 'completed'
  where r.status = 'active'
    and r.departure_at <= now()
    and not exists (
      select 1
      from bookings b
      where b.ride_id = r.id
        and b.status = 'reserved'
    );

  get diagnostics v_updated = row_count;
  return v_updated;
end $$;

grant execute on function public.expire_past_active_rides() to authenticated;

-- ----------
-- 4.1) One-time financial correction for historical double fee discount
-- ----------

with fix_rows as (
  select
    pf.user_id,
    pf.booking_id,
    abs(pf.amount)::int as fee_to_restore
  from transactions pf
  where pf.type = 'platform_fee'
    and pf.amount < 0
    and coalesce(pf.metadata->>'reason', '') = 'mvp_fee_split'
    and exists (
      select 1
      from transactions rel
      where rel.user_id = pf.user_id
        and rel.booking_id = pf.booking_id
        and rel.type = 'release_to_driver'
    )
    and not exists (
      select 1
      from transactions fx
      where fx.user_id = pf.user_id
        and fx.booking_id = pf.booking_id
        and fx.type = 'refund'
        and coalesce(fx.metadata->>'reason', '') = 'platform_fee_double_discount_fix'
    )
),
wallet_fix as (
  select user_id, sum(fee_to_restore)::int as total_restore
  from fix_rows
  group by user_id
),
apply_wallet_fix as (
  update wallets w
  set balance_available = w.balance_available + wf.total_restore,
      updated_at = now()
  from wallet_fix wf
  where w.user_id = wf.user_id
  returning w.user_id
)
insert into transactions (user_id, booking_id, type, amount, metadata)
select
  fr.user_id,
  fr.booking_id,
  'refund',
  fr.fee_to_restore,
  jsonb_build_object(
    'reason', 'platform_fee_double_discount_fix',
    'source', 'migration_14_dispatch_hardening'
  )
from fix_rows fr;

-- ----------
-- 5) RPC updates with strict dispatch transitions
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
  v_departure timestamptz;
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

  if v_departure <= now() then
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
  v_departure timestamptz;
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

  if v_departure <= now() then
    raise exception 'ride_departed' using errcode = 'P0010';
  end if;

  update bookings
  set dispatch_status = 'accepted',
      driver_accepted_at = coalesce(driver_accepted_at, now())
  where id = p_booking_id;

  perform public.log_booking_event(
    p_booking_id,
    v_ride_id,
    v_driver,
    'driver',
    v_dispatch,
    'accepted'::booking_dispatch_status,
    'driver_accepted_booking'
  );
end $$;

create or replace function public.driver_mark_arriving(p_booking_id uuid)
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
begin
  if v_driver is null then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  select r.driver_id, b.ride_id, b.status, b.dispatch_status
    into v_owner, v_ride_id, v_status, v_dispatch
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

  if v_dispatch <> 'accepted' then
    raise exception 'invalid_dispatch_transition' using errcode = 'P0011';
  end if;

  update bookings
  set dispatch_status = 'driver_arriving',
      driver_arriving_at = coalesce(driver_arriving_at, now())
  where id = p_booking_id;

  perform public.log_booking_event(
    p_booking_id,
    v_ride_id,
    v_driver,
    'driver',
    v_dispatch,
    'driver_arriving'::booking_dispatch_status,
    'driver_marked_arriving'
  );
end $$;

create or replace function public.driver_mark_arrived(p_booking_id uuid)
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
begin
  if v_driver is null then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  select r.driver_id, b.ride_id, b.status, b.dispatch_status
    into v_owner, v_ride_id, v_status, v_dispatch
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

  if v_dispatch not in ('accepted', 'driver_arriving') then
    raise exception 'invalid_dispatch_transition' using errcode = 'P0011';
  end if;

  update bookings
  set dispatch_status = 'driver_arrived',
      driver_arrived_at = coalesce(driver_arrived_at, now())
  where id = p_booking_id;

  perform public.log_booking_event(
    p_booking_id,
    v_ride_id,
    v_driver,
    'driver',
    v_dispatch,
    'driver_arrived'::booking_dispatch_status,
    'driver_marked_arrived'
  );
end $$;

create or replace function public.confirm_boarding(p_booking_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_passenger uuid := auth.uid();
  v_booking_passenger uuid;
  v_ride_id uuid;
  v_status booking_status;
  v_dispatch booking_dispatch_status;
begin
  if v_passenger is null then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  select b.passenger_id, b.ride_id, b.status, b.dispatch_status
    into v_booking_passenger, v_ride_id, v_status, v_dispatch
  from bookings b
  where b.id = p_booking_id
  for update of b;

  if not found then
    raise exception 'booking not found or already processed' using errcode = 'P0005';
  end if;

  if v_booking_passenger is distinct from v_passenger then
    raise exception 'forbidden' using errcode = 'P0006';
  end if;

  if v_status <> 'reserved' then
    raise exception 'booking_not_active' using errcode = 'P0011';
  end if;

  if v_dispatch not in ('accepted', 'driver_arriving', 'driver_arrived') then
    raise exception 'invalid_dispatch_transition' using errcode = 'P0011';
  end if;

  update bookings
  set dispatch_status = 'passenger_boarded',
      passenger_boarded_at = coalesce(passenger_boarded_at, now())
  where id = p_booking_id;

  perform public.log_booking_event(
    p_booking_id,
    v_ride_id,
    v_passenger,
    'passenger',
    v_dispatch,
    'passenger_boarded'::booking_dispatch_status,
    'passenger_confirmed_boarding'
  );
end $$;

create or replace function public.driver_start_trip(p_booking_id uuid)
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
begin
  if v_driver is null then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  select r.driver_id, b.ride_id, b.status, b.dispatch_status
    into v_owner, v_ride_id, v_status, v_dispatch
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

  if v_dispatch <> 'passenger_boarded' then
    raise exception 'passenger_not_boarded' using errcode = 'P0011';
  end if;

  update bookings
  set dispatch_status = 'in_progress',
      trip_started_at = coalesce(trip_started_at, now())
  where id = p_booking_id;

  perform public.log_booking_event(
    p_booking_id,
    v_ride_id,
    v_driver,
    'driver',
    v_dispatch,
    'in_progress'::booking_dispatch_status,
    'driver_started_trip'
  );
end $$;

create or replace function public.driver_complete_trip(p_booking_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver uuid := auth.uid();
  v_owner uuid;
  v_ride_id uuid;
  v_passenger uuid;
  v_status booking_status;
  v_dispatch booking_dispatch_status;
  v_amount int;
  v_fee int;
  v_driver_net int;
begin
  if v_driver is null then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  select r.driver_id,
         b.ride_id,
         b.passenger_id,
         b.status,
         b.dispatch_status,
         b.amount_total,
         greatest(coalesce(r.driver_net_amount, b.amount_total), 0),
         greatest(b.amount_total - greatest(coalesce(r.driver_net_amount, b.amount_total), 0), 0)
    into v_owner,
         v_ride_id,
         v_passenger,
         v_status,
         v_dispatch,
         v_amount,
         v_driver_net,
         v_fee
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

  if v_dispatch not in ('in_progress', 'passenger_boarded') then
    raise exception 'invalid_dispatch_transition' using errcode = 'P0011';
  end if;

  update wallets
  set balance_held = balance_held - v_amount,
      updated_at = now()
  where user_id = v_passenger
    and balance_held >= v_amount;

  if not found then
    raise exception 'held_balance_mismatch' using errcode = 'P0012';
  end if;

  update wallets
  set balance_available = balance_available + v_driver_net,
      updated_at = now()
  where user_id = v_driver;

  if not found then
    raise exception 'wallet not found for user %', v_driver using errcode = 'P0007';
  end if;

  update bookings
  set status = 'completed',
      dispatch_status = 'completed',
      confirmed_at = coalesce(confirmed_at, now()),
      trip_started_at = coalesce(trip_started_at, now()),
      trip_completed_at = now()
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
      'driver_net_amount', v_driver_net,
      'settled_at', now()
    )
  );

  insert into transactions (user_id, booking_id, type, amount, metadata)
  values (
    v_driver,
    p_booking_id,
    'release_to_driver',
    v_driver_net,
    jsonb_build_object(
      'passenger_id', v_passenger,
      'platform_fee', v_fee,
      'gross_amount', v_amount
    )
  );

  perform public.log_booking_event(
    p_booking_id,
    v_ride_id,
    v_driver,
    'driver',
    v_dispatch,
    'completed'::booking_dispatch_status,
    'driver_completed_trip',
    jsonb_build_object(
      'gross_amount', v_amount,
      'driver_net_amount', v_driver_net,
      'platform_fee', v_fee
    )
  );

  perform public.set_ride_completed_if_no_open_bookings(v_ride_id);
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
  v_departure timestamptz;
  v_dispatch booking_dispatch_status;
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

  if now() > v_departure + interval '10 minutes' then
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

  perform public.log_booking_event(
    p_booking_id,
    v_ride_id,
    v_passenger,
    'passenger',
    v_dispatch,
    'cancelled'::booking_dispatch_status,
    'passenger_cancelled_booking'
  );

  perform public.set_ride_completed_if_no_open_bookings(v_ride_id);
end $$;

create or replace function public.driver_reject_booking(
  p_booking_id uuid,
  p_reason text default 'rejected_by_driver'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver uuid := auth.uid();
  v_owner uuid;
  v_passenger uuid;
  v_ride_id uuid;
  v_amount int;
  v_dispatch booking_dispatch_status;
begin
  if v_driver is null then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  select r.driver_id, b.passenger_id, b.ride_id, b.amount_total, b.dispatch_status
    into v_owner, v_passenger, v_ride_id, v_amount, v_dispatch
  from bookings b
  join rides r on r.id = b.ride_id
  where b.id = p_booking_id
    and b.status = 'reserved'
  for update of b;

  if not found then
    raise exception 'booking not found or already processed' using errcode = 'P0005';
  end if;

  if v_owner is distinct from v_driver then
    raise exception 'forbidden' using errcode = 'P0006';
  end if;

  if v_dispatch not in ('reserved', 'accepted') then
    raise exception 'invalid_dispatch_transition' using errcode = 'P0011';
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
      cancelled_by = v_driver,
      cancel_reason = coalesce(nullif(trim(p_reason), ''), 'rejected_by_driver')
  where id = p_booking_id;

  insert into transactions (user_id, booking_id, type, amount, metadata)
  values (
    v_passenger,
    p_booking_id,
    'refund',
    v_amount,
    jsonb_build_object(
      'ride_id', v_ride_id,
      'reason', 'driver_rejected_booking',
      'driver_reason', coalesce(nullif(trim(p_reason), ''), 'rejected_by_driver')
    )
  );

  perform public.log_booking_event(
    p_booking_id,
    v_ride_id,
    v_driver,
    'driver',
    v_dispatch,
    'cancelled'::booking_dispatch_status,
    'driver_rejected_booking',
    jsonb_build_object('reason', coalesce(nullif(trim(p_reason), ''), 'rejected_by_driver'))
  );

  perform public.set_ride_completed_if_no_open_bookings(v_ride_id);
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
      cancel_reason = coalesce(nullif(trim(p_reason), ''), 'cancelled_by_driver'),
      cancelled_at = now(),
      seats_available = seats_total
  where id = p_ride_id
  returning departure_at into v_departure;

  for v_booking in
    select id, passenger_id, amount_total, dispatch_status
    from bookings
    where ride_id = p_ride_id
      and status = 'reserved'
    for update
  loop
    update wallets
    set balance_held = balance_held - v_booking.amount_total,
        balance_available = balance_available + v_booking.amount_total,
        updated_at = now()
    where user_id = v_booking.passenger_id
      and balance_held >= v_booking.amount_total;

    if not found then
      raise exception 'held_balance_mismatch' using errcode = 'P0012';
    end if;

    update bookings
    set status = 'cancelled',
        dispatch_status = 'cancelled',
        cancelled_at = now(),
        cancelled_by = v_driver,
        cancel_reason = coalesce(nullif(trim(p_reason), ''), 'cancelled_by_driver')
    where id = v_booking.id;

    insert into transactions (user_id, booking_id, type, amount, metadata)
    values (
      v_booking.passenger_id,
      v_booking.id,
      'refund',
      v_booking.amount_total,
      jsonb_build_object('ride_id', p_ride_id, 'reason', 'driver_cancelled')
    );

    perform public.log_booking_event(
      v_booking.id,
      p_ride_id,
      v_driver,
      'driver',
      v_booking.dispatch_status,
      'cancelled'::booking_dispatch_status,
      'driver_cancelled_ride',
      jsonb_build_object('reason', coalesce(nullif(trim(p_reason), ''), 'cancelled_by_driver'))
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
  v_dispatch booking_dispatch_status;
begin
  if v_passenger is null then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  select b.passenger_id,
         b.ride_id,
         b.amount_total,
         b.dispatch_status,
         r.driver_id,
         r.departure_at
    into v_passenger,
         v_ride_id,
         v_amount,
         v_dispatch,
         v_driver,
         v_departure
  from bookings b
  join rides r on r.id = b.ride_id
  where b.id = p_booking_id
    and b.status = 'reserved'
    and b.passenger_id = auth.uid()
  for update of b;

  if not found then
    raise exception 'booking not found or already processed' using errcode = 'P0005';
  end if;

  if v_dispatch not in ('accepted', 'driver_arriving', 'driver_arrived') then
    raise exception 'invalid_dispatch_transition' using errcode = 'P0011';
  end if;

  if now() < v_departure + interval '10 minutes' then
    raise exception 'wait_time_not_elapsed' using errcode = 'P0008';
  end if;

  if now() > v_departure + interval '12 hours' then
    raise exception 'report_window_expired' using errcode = 'P0013';
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
  set status = 'no_show',
      dispatch_status = 'no_show',
      reported_no_show_at = now(),
      no_show_notes = p_notes,
      cancelled_at = now(),
      cancelled_by = v_passenger,
      cancel_reason = 'driver_no_show'
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

  perform public.log_booking_event(
    p_booking_id,
    v_ride_id,
    v_passenger,
    'passenger',
    v_dispatch,
    'no_show'::booking_dispatch_status,
    'passenger_reported_no_show',
    jsonb_build_object('notes', coalesce(p_notes, ''))
  );

  perform public.set_ride_completed_if_no_open_bookings(v_ride_id);
end $$;

-- ----------
-- 6) Grants for authenticated app role
-- ----------

grant execute on function public.create_booking(uuid) to authenticated;
grant execute on function public.confirm_boarding(uuid) to authenticated;
grant execute on function public.cancel_booking(uuid) to authenticated;
grant execute on function public.driver_cancel_ride(uuid, text) to authenticated;
grant execute on function public.passenger_report_no_show(uuid, text) to authenticated;
grant execute on function public.driver_accept_booking(uuid) to authenticated;
grant execute on function public.driver_mark_arriving(uuid) to authenticated;
grant execute on function public.driver_mark_arrived(uuid) to authenticated;
grant execute on function public.driver_start_trip(uuid) to authenticated;
grant execute on function public.driver_complete_trip(uuid) to authenticated;
grant execute on function public.driver_reject_booking(uuid, text) to authenticated;
