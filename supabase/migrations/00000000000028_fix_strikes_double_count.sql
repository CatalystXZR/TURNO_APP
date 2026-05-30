-- =============================================================
-- Turno — Migration 28: Fix strike double-counting + auto-expire
-- =============================================================
--
-- Bugs fixed:
--   A) driver_cancel_ride and passenger_report_no_show did a manual
--      UPDATE users_profile AFTER the trigger already recalculated,
--      causing double-counting (strikes_count inflated by +1).
--   B) No periodic job recalculated strike state when strikes naturally
--      expired (expires_at passed). Users appeared suspended forever.
--
-- Solution:
--   1) Remove manual UPDATE from both functions — rely solely on
--      trg_refresh_user_strike_state trigger.
--   2) Add a pg_cron job that recalcs all strike states every hour.

begin;

-- =============================================================
-- 1) driver_cancel_ride: keep everything except the manual UPDATE
-- =============================================================
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
      cancel_reason = coalesce(nullif(trim(p_reason), ''), 'cancelled_by_driver'),
      cancelled_at = now(),
      seats_available = seats_total
  where id = p_ride_id
  returning departure_at into v_departure;

  for v_booking in
    select id, passenger_id, amount_total, dispatch_status
    from bookings
    where ride_id = p_ride_id and status = 'reserved'
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

  -- Strike insertion: the AFTER INSERT trigger trg_refresh_user_strike_state
  -- will recalculate strikes_count, suspended_until and vehicle_suspended_until
  -- correctly. No manual UPDATE needed.
  if v_now >= v_departure - interval '2 hours' then
    insert into strikes (driver_id, reason, source, expires_at)
    values (v_driver, 'driver_cancelled_ride', 'driver_cancel', now() + interval '2 months');
  end if;
end $$;

-- =============================================================
-- 2) passenger_report_no_show: keep everything except manual UPDATE
-- =============================================================
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
  v_dispatch booking_dispatch_status;
  v_now timestamp := public.current_chile_time();
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

  if v_now < v_departure + interval '10 minutes' then
    raise exception 'wait_time_not_elapsed' using errcode = 'P0008';
  end if;

  if v_now > v_departure + interval '12 hours' then
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

  -- Strike insertion: the AFTER INSERT trigger trg_refresh_user_strike_state
  -- will recalculate strikes_count, suspended_until and vehicle_suspended_until
  -- correctly. No manual UPDATE needed.
  insert into strikes (driver_id, reason, booking_id, source, expires_at)
  values (v_driver, 'driver_no_show', p_booking_id, 'passenger_report', now() + interval '2 months');

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

-- =============================================================
-- 3) Refresh strike state for ALL users with strikes
--    (handles natural expiration of strikes_count/suspension)
-- =============================================================
create or replace function public.refresh_all_strike_states()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int := 0;
  r record;
begin
  for r in select distinct driver_id from strikes loop
    perform public.refresh_user_strike_state(r.driver_id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;

-- =============================================================
-- 4) pg_cron job: recalculate all strike states every hour
--    (same safe pattern as migration 20)
-- =============================================================
do $$
begin
  if exists (
    select 1 from pg_extension where extname = 'pg_cron'
  ) then
    delete from cron.job where jobname = 'refresh_strike_states';
    insert into cron.job (schedule, command, jobname)
    values (
      '0 * * * *',
      'select public.refresh_all_strike_states();',
      'refresh_strike_states'
    );
  end if;
exception when others then
  null;
end $$;

commit;
