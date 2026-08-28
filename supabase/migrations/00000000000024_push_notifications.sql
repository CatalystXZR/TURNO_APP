-- Migration 24: Push notification infrastructure (APNs)
--
-- Dependencies: pg_net extension must be enabled via Supabase Dashboard
--   Dashboard > Database > Extensions > pg_net (schema: extensions)
-- If pg_net is not available, the trigger degrades gracefully.

-- 1. Device tokens table for APNs push notifications
create table if not exists device_tokens (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references users_profile(id) on delete cascade,
  platform    text not null check (platform in ('ios', 'android')),
  token       text not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique(user_id, token)
);

create index if not exists idx_device_tokens_user_id on device_tokens(user_id);

-- 2. Enable pg_net for outbound HTTP calls (if available)
do $$
begin
  create extension if not exists pg_net with schema extensions;
exception when others then
  raise notice 'pg_net extension not available — push notifications disabled';
end;
$$;

-- 3. Push notification dispatch function
-- Called from booking_event triggers to deliver APNs via the Edge Function.
create or replace function push_notify_dispatch_change(
  p_booking_id uuid,
  p_new_status text
)
returns void
language plpgsql
security definer
set search_path = public
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
      v_edge_url := 'https://zawaevytpkvejhekyokw.supabase.co/functions/v1/send-push-notification';

      perform net.http_post(
        url := v_edge_url,
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'X-Internal-Secret', 'turnoapp-internal-push-call-v1'
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

-- 4. Trigger: call push_notify_dispatch_change after each booking_event insert
create or replace function trg_booking_event_push()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  begin
    perform push_notify_dispatch_change(new.booking_id, new.to_status::text);
  exception when others then
    raise warning 'trg_booking_event_push: push notification failed for booking_event % — %', new.id, sqlerrm;
  end;
  return new;
end;
$$;

drop trigger if exists booking_event_push_trigger on booking_events;
create trigger booking_event_push_trigger
  after insert on booking_events
  for each row
  execute function trg_booking_event_push();
