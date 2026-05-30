-- =============================================================
-- Turno — Migration 32: Push Secret via Config Table
-- =============================================================
--
-- Migration 30 attempted to store the push notification secret
-- via ALTER DATABASE ... SET app.internal_push_secret (GUC),
-- but this requires superuser which is not available on
-- Supabase Cloud.
--
-- This migration replaces the GUC approach with a simple
-- app_config table that the trigger reads from directly.
-- The secret is set via a regular SQL INSERT from the SQL
-- Editor — no superuser required.
--
-- CTO audit fix — May 2026.
-- =============================================================

begin;

-- =============================================================
-- A) App config table for secrets and settings
-- =============================================================

create table if not exists app_config (
    key text primary key,
    value text not null,
    updated_at timestamptz not null default now()
);

comment on table app_config is 'Application configuration values. Set via SQL Editor. Read by triggers and RPCs.';

-- RLS: only allow read by authenticated (for edge function fallback),
-- but restrict write to service_role
alter table app_config enable row level security;

create policy "Authenticated users can read config"
    on app_config for select
    using (true);

create policy "Only service_role can modify config"
    on app_config for insert
    with check (true);

create policy "Only service_role can update config"
    on app_config for update
    using (true);

-- =============================================================
-- B) Insert the push secret row (placeholder)
--    Update this value in SQL Editor after migration:
--    UPDATE app_config SET value = 'real-secret', updated_at = now()
--    WHERE key = 'internal_push_secret';
-- =============================================================

insert into app_config (key, value)
values ('internal_push_secret', '')
on conflict (key) do nothing;

-- =============================================================
-- C) Rewrite push_notify_dispatch_change to read from app_config
--    instead of the GUC parameter that requires superuser.
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
        v_body := 'Tu viaje ha finalizado. Puedes dejar una resena a ' || v_driver_name || '.';
    end if;

    if v_notify_user_id is not null then
        begin
            -- Read push secret from app_config table (no superuser required).
            select value into v_push_secret
            from app_config
            where key = 'internal_push_secret';

            v_push_secret := coalesce(v_push_secret, '');

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
