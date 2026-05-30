-- =============================================================
-- Turno — Migration 30: Security Hardening
-- =============================================================
--
-- Changes:
--   A) Revoke system-level RPCs from authenticated role.
--      expire_stale_bookings, expire_stale_bookings_and_release,
--      and expire_past_active_rides should only execute via
--      pg_cron (postgres) or service_role, never by end-users.
--      Any authenticated user calling these could disrupt active
--      trips during edge-case time windows.
--
--   B) Update push notification trigger to use a configurable
--      secret parameter instead of hardcoded string.
--      The edge function send-push-notification now REQUIRES
--      INTERNAL_PUSH_SECRET to be set (no fallback). The DB
--      trigger will read it from a custom GUC parameter set
--      at the database level.
--
-- Security audit by: Staff Flutter Architect & Red Teamer.
-- =============================================================

begin;

-- =============================================================
-- A) Revoke system RPC grants from authenticated
-- =============================================================

revoke execute on function public.expire_stale_bookings() from authenticated;
revoke execute on function public.expire_stale_bookings_and_release() from authenticated;
revoke execute on function public.expire_past_active_rides() from authenticated;

-- Ensure postgres role still has access (for pg_cron)
grant execute on function public.expire_stale_bookings() to postgres;
grant execute on function public.expire_stale_bookings_and_release() to postgres;
grant execute on function public.expire_past_active_rides() to postgres;

-- =============================================================
-- B) Push notification secret via custom GUC parameter
--    This replaces the hardcoded secret in the trigger body.
--    Set this per-environment:
--      ALTER DATABASE postgres SET app.internal_push_secret = 'your_secret';
--    Or via Supabase Dashboard > Database > Settings.
-- =============================================================

-- Register the custom parameter so it can be used in current_setting()
do $$
begin
  -- Only register if not already present (idempotent across re-runs)
  perform set_config('app.internal_push_secret', '', false);
exception when others then
  null;
end $$;

-- =============================================================
-- B.1) Update push_notify_dispatch_change to read secret from GUC
--      Fallback provided for environments where GUC is unset.
-- =============================================================

create or replace function public.push_notify_dispatch_change(
  p_booking_id uuid,
  p_new_status text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_passenger_id   uuid;
  v_driver_id      uuid;
  v_passenger_name text;
  v_driver_name    text;
  v_notify_user_id uuid;
  v_title          text;
  v_body           text;
  v_edge_url       text;
  v_push_secret    text;
begin
  select
    b.passenger_id,
    r.driver_id,
    up.full_name,
    ud.full_name
  into
    v_passenger_id,
    v_driver_id,
    v_passenger_name,
    v_driver_name
  from bookings b
  join rides r on r.id = b.ride_id
  join users_profile up on up.id = b.passenger_id
  join users_profile ud on ud.id = r.driver_id
  where b.id = p_booking_id;

  if not found then
    return;
  end if;

  if p_new_status = 'accepted' then
    v_notify_user_id := v_passenger_id;
    v_title := 'Te han confirmado el Ride!';
    v_body := v_driver_name || ' ha aceptado tu reserva.';
  elsif p_new_status = 'driver_arriving' then
    v_notify_user_id := v_passenger_id;
    v_title := 'El rider va en camino!';
    v_body := v_driver_name || ' va en camino al punto de encuentro.';
  elsif p_new_status = 'driver_arrived' then
    v_notify_user_id := v_passenger_id;
    v_title := 'El rider ha llegado!';
    v_body := v_driver_name || ' ya se encuentra en el punto de encuentro.';
  elsif p_new_status = 'passenger_boarded' then
    v_notify_user_id := v_driver_id;
    v_title := 'Pasajero a bordo';
    v_body := v_passenger_name || ' ha confirmado abordaje. Ya puedes iniciar el viaje.';
  elsif p_new_status = 'in_progress' then
    v_notify_user_id := v_passenger_id;
    v_title := 'Viaje en curso';
    v_body := 'Tu viaje con ' || v_driver_name || ' ha comenzado.';
  elsif p_new_status = 'completed' then
    v_notify_user_id := v_passenger_id;
    v_title := 'Viaje finalizado';
    v_body := 'Tu viaje ha finalizado. Puedes dejar una reseña a ' || v_driver_name || '.';
  end if;

  if v_notify_user_id is not null then
    begin
      -- Read push secret from database-level GUC parameter.
      -- Set via: ALTER DATABASE postgres SET app.internal_push_secret = '...';
      -- Falls back to empty string if not configured (edge function will reject).
      v_push_secret := coalesce(
        nullif(current_setting('app.internal_push_secret', true), ''),
        ''
      );

      v_edge_url := 'https://zawaevytpkvejhekyokw.supabase.co/functions/v1/send-push-notification';

      perform net.http_post(
        url := v_edge_url,
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'X-Internal-Secret', v_push_secret
        ),
        body := jsonb_build_object(
          'user_id', v_notify_user_id,
          'title', v_title,
          'body', v_body,
          'booking_id', p_booking_id
        )
      );
    exception when others then
      raise warning 'push_notify_dispatch_change: edge function call failed for booking % — %', p_booking_id, sqlerrm;
    end;
  end if;
end;
$$;

commit;
