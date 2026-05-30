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
-- Turno — Migration 20: Auto-expire stale bookings + timezone safety
-- =============================================================

-- 1) Auto-close bookings where passenger never boarded after departure + 15 min
create or replace function public.expire_stale_bookings()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamp := public.current_chile_time();
  v_expired_bookings int;
begin
  update bookings
  set status = 'no_show',
      dispatch_status = 'no_show',
      reported_no_show_at = now(),
      cancelled_at = now(),
      cancel_reason = 'passenger_no_board auto-expired'
  where status = 'reserved'
    and dispatch_status in ('reserved', 'accepted', 'driver_arriving', 'driver_arrived', 'passenger_boarded')
    and exists (
      select 1 from rides r
      where r.id = bookings.ride_id
        and r.departure_at + interval '15 minutes' <= v_now
    )
    and not exists (
      select 1 from bookings b2
      where b2.ride_id = bookings.ride_id
        and b2.id = bookings.id
        and b2.dispatch_status in ('in_progress', 'completed')
    )
  returning id into v_expired_bookings;

  get diagnostics v_expired_bookings = row_count;
  return coalesce(v_expired_bookings, 0);
end $$;

-- 2) Release held funds for expired bookings
create or replace function public.expire_stale_bookings_and_release()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int := 0;
  v_booking record;
  v_passenger uuid;
  v_amount int;
  v_ride_id uuid;
begin
  for v_booking in
    select id, passenger_id, amount_total, ride_id
    from bookings
    where status = 'reserved'
      and dispatch_status in ('reserved', 'accepted', 'driver_arriving', 'driver_arrived')
      and exists (
        select 1 from rides r
        where r.id = bookings.ride_id
          and r.departure_at + interval '15 minutes' <= public.current_chile_time()
      )
    for update of bookings
  loop
    v_passenger := v_booking.passenger_id;
    v_amount := v_booking.amount_total;
    v_ride_id := v_booking.ride_id;

    update bookings
    set status = 'no_show',
        dispatch_status = 'no_show',
        reported_no_show_at = now(),
        cancelled_at = now(),
        cancel_reason = 'passenger_no_board_auto_expired'
    where id = v_booking.id;

    update wallets
    set balance_held = balance_held - v_amount,
        balance_available = balance_available + v_amount,
        updated_at = now()
    where user_id = v_passenger
      and balance_held >= v_amount;

    update rides
    set seats_available = least(seats_total, seats_available + 1)
    where id = v_ride_id
      and status = 'active';

    insert into transactions (user_id, booking_id, type, amount, metadata)
    values (
      v_passenger,
      v_booking.id,
      'refund',
      v_amount,
      jsonb_build_object('ride_id', v_ride_id, 'reason', 'auto_expired_no_show')
    );

    v_count := v_count + 1;
  end loop;

  return v_count;
end $$;

-- 3) Grant execution to authenticated
grant execute on function public.expire_stale_bookings() to authenticated;
grant execute on function public.expire_stale_bookings_and_release() to authenticated;
grant execute on function public.expire_stale_bookings_and_release() to postgres;

-- 4) Helper: get current timezone offset for display validation
create or replace function public.get_chile_timezone_offset()
returns text
language sql
stable
as $$
  select extract(timezone from now())::text;
$$;

-- 5) Scheduled function (runs via pg_cron if available and permitted)
do $$
begin
  if exists (
    select 1 from pg_extension where extname = 'pg_cron'
  ) then
    delete from cron.job where jobname = 'expire_stale_bookings';
    insert into cron.job (schedule, command, jobname)
    values (
      '*/5 * * * *',
      'select public.expire_stale_bookings_and_release();',
      'expire_stale_bookings'
    );
  end if;
exception when others then
  -- pg_cron not available or insufficient permissions; cron job skipped
  null;
end $$;