-- =============================================================
-- Turno — Migration 29: Adversarial Audit Fixes
-- =============================================================
--
-- Fixes applied:
--   A) Anti-griefing cooldown on passenger cancellations (V1)
--      Prevents seat-hostage attacks: book → cancel → rebook loop.
--   B) complete_ride_manual hardening (V2)
--      Guards against driver fraud by requiring minimum dispatch state.
--   C) delete_user_account fix (V4b)
--      Transactions immutability rules blocked account deletion.
--
-- Security audit by: Principal QA Architect adversarial review.
-- =============================================================

begin;

-- =============================================================
-- A) ANTI-GRIEFING: Cooldown columns on users_profile
-- =============================================================

alter table users_profile
  add column if not exists last_cancelled_at timestamptz,
  add column if not exists last_cancelled_ride_id uuid;

-- =============================================================
-- A.1) Update cancel_booking to record cooldown data
--      (Passenger-side cancellation only)
-- =============================================================

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

  -- Anti-griefing: record cancellation on user profile for cooldown
  update users_profile
  set last_cancelled_at = now(),
      last_cancelled_ride_id = v_ride_id
  where id = v_passenger;

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

-- =============================================================
-- A.2) Update create_booking to enforce cooldown
--      Blocks re-booking on same ride within 15 min of cancel.
-- =============================================================

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

  -- Anti-griefing: enforce 15-minute cooldown after cancelling on same ride
  if exists (
    select 1
    from users_profile up
    where up.id = v_user
      and up.last_cancelled_ride_id = p_ride_id
      and up.last_cancelled_at is not null
      and up.last_cancelled_at > now() - interval '15 minutes'
  ) then
    raise exception 'cancellation_cooldown' using errcode = 'P0018';
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

-- =============================================================
-- B) COMPLETE_RIDE_MANUAL HARDENING
--    Guard: only complete bookings that the driver has at least
--    accepted. Also require the ride departure time has passed.
-- =============================================================

create or replace function public.complete_ride_manual(p_ride_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_ride record;
  v_booking record;
  v_passenger uuid;
  v_amount int;
  v_fee int;
  v_driver_net int;
begin
  if v_user is null then
    raise exception 'Sesion requerida' using errcode = 'P0001';
  end if;

  select * into v_ride from rides where id = p_ride_id and driver_id = v_user;
  if not found then
    raise exception 'Ride no encontrado o no eres el conductor' using errcode = 'P0002';
  end if;

  if v_ride.status <> 'active' then
    raise exception 'El ride no esta activo' using errcode = 'P0005';
  end if;

  -- HARDENING: Only allow completion after the ride departure time has passed.
  -- This prevents a driver from immediately completing a freshly-published ride
  -- without ever attempting the trip.
  if v_ride.departure_at > public.current_chile_time() then
    raise exception 'El ride aun no ha partido' using errcode = 'P0010';
  end if;

  for v_booking in
    select b.id, b.passenger_id, b.amount_total, b.dispatch_status,
           greatest(coalesce(v_ride.driver_net_amount, b.amount_total), 0) as driver_net,
           greatest(b.amount_total - greatest(coalesce(v_ride.driver_net_amount, b.amount_total), 0), 0) as fee
    from bookings b
    where b.ride_id = p_ride_id
      and b.status = 'reserved'
      -- HARDENING: Only complete bookings the driver has at least accepted.
      -- Prevents fraud: driver cannot force-complete bookings they never
      -- acknowledged (e.g., freshly reserved, never accepted).
      and b.dispatch_status in (
        'accepted',
        'driver_arriving',
        'driver_arrived',
        'passenger_boarded',
        'in_progress'
      )
    for update of b
  loop
    v_passenger := v_booking.passenger_id;
    v_amount := v_booking.amount_total;
    v_driver_net := v_booking.driver_net;
    v_fee := v_booking.fee;

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
    where user_id = v_user;

    update bookings
    set status = 'completed',
        dispatch_status = 'completed',
        confirmed_at = coalesce(confirmed_at, now()),
        trip_started_at = coalesce(trip_started_at, now()),
        trip_completed_at = now()
    where id = v_booking.id;

    insert into transactions (user_id, booking_id, type, amount, metadata)
    values (
      v_passenger,
      v_booking.id,
      'release_to_driver',
      0,
      jsonb_build_object(
        'driver_id', v_user,
        'platform_fee', v_fee,
        'driver_net_amount', v_driver_net,
        'settled_at', now()
      )
    );

    insert into transactions (user_id, booking_id, type, amount, metadata)
    values (
      v_user,
      v_booking.id,
      'release_to_driver',
      v_driver_net,
      jsonb_build_object(
        'passenger_id', v_passenger,
        'platform_fee', v_fee,
        'gross_amount', v_amount
      )
    );

    perform public.log_booking_event(
      v_booking.id,
      p_ride_id,
      v_user,
      'driver',
      v_booking.dispatch_status,
      'completed'::booking_dispatch_status,
      'driver_completed_ride_manual',
      jsonb_build_object(
        'gross_amount', v_amount,
        'driver_net_amount', v_driver_net,
        'platform_fee', v_fee
      )
    );
  end loop;

  perform public.set_ride_completed_if_no_open_bookings(p_ride_id);
end $$;

-- =============================================================
-- C) DELETE_USER_ACCOUNT FIX
--    The transactions table has immutability rules
--    (transactions_no_delete / transactions_no_update) that
--    silently block DELETEs, causing FK violations when
--    users_profile is deleted. This fix temporarily drops the
--    rules during account deletion and recreates them after.
-- =============================================================

create or replace function public.delete_user_account(p_user_id uuid default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid;
begin
  -- If called with explicit user_id (from edge function via service_role),
  -- use that. Otherwise derive from auth.uid() (direct client call).
  if p_user_id is not null then
    v_user := p_user_id;
  else
    v_user := auth.uid();
  end if;

  if v_user is null then
    raise exception 'Sesion requerida' using errcode = 'P0001';
  end if;

  -- Temporarily drop ledger immutability rules so we can clean up
  drop rule if exists transactions_no_delete on transactions;
  drop rule if exists transactions_no_update on transactions;

  -- Delete ALL transactions related to this user:
  --   a) Transactions owned by this user
  --   b) Transactions referencing bookings where this user was passenger
  --      (partner transactions, e.g. driver's release_to_driver row)
  --   c) Transactions referencing bookings on rides this user drove
  delete from transactions
  where user_id = v_user
     or booking_id in (
       select id from bookings where passenger_id = v_user
     )
     or booking_id in (
       select b.id
       from bookings b
       join rides r on r.id = b.ride_id
       where r.driver_id = v_user
     );

  -- Restore immutability rules immediately
  create or replace rule transactions_no_delete as
    on delete to transactions do instead nothing;

  create or replace rule transactions_no_update as
    on update to transactions do instead nothing;

  -- Delete bookings where this user is the passenger
  -- (cascades to booking_events and booking_reviews via FK)
  delete from bookings where passenger_id = v_user;

  -- Delete rides driven by this user
  -- (cascades to bookings, booking_events, booking_reviews via FK)
  delete from rides where driver_id = v_user;

  -- Clean up remaining child tables
  delete from withdrawals where driver_id = v_user;
  delete from fintoc_payments where user_id = v_user;
  delete from mp_payments where user_id = v_user;
  delete from strikes where driver_id = v_user;

  -- Delete profile and auth user (cascades to wallets, device_tokens,
  -- user_favorites, booking_reviews via FK ON DELETE CASCADE)
  delete from wallets where user_id = v_user;
  delete from users_profile where id = v_user;
  delete from auth.users where id = v_user;
end $$;

-- =============================================================
-- D) Grants
-- =============================================================

grant execute on function public.create_booking(uuid) to authenticated;
grant execute on function public.cancel_booking(uuid) to authenticated;
grant execute on function public.complete_ride_manual(uuid) to authenticated;
grant execute on function public.delete_user_account(uuid) to authenticated;
grant execute on function public.delete_user_account(uuid) to service_role;

commit;
