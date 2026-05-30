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
-- Turno — Migration 17: strikes reconciliation + guardrails
-- =============================================================

-- 1) Rebuild counters from active strikes only (expires_at >= now())
with active_strikes as (
  select
    driver_id,
    count(*)::int as cnt,
    max(expires_at) as max_expiry
  from strikes
  where expires_at >= now()
  group by driver_id
)
update users_profile up
set strikes_count = coalesce(a.cnt, 0),
    suspended_until = case
      when coalesce(a.cnt, 0) >= 2 then a.max_expiry
      else null
    end,
    vehicle_suspended_until = case
      when coalesce(a.cnt, 0) >= 2 then a.max_expiry
      else null
    end
from (
  select
    up2.id,
    a.cnt,
    a.max_expiry
  from users_profile up2
  left join active_strikes a on a.driver_id = up2.id
) a
where up.id = a.id;

-- 2) Helper to keep strike counters coherent at any time
create or replace function public.refresh_user_strike_state(
  p_driver_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cnt int;
  v_max_expiry timestamptz;
begin
  select
    count(*)::int,
    max(expires_at)
  into v_cnt, v_max_expiry
  from strikes
  where driver_id = p_driver_id
    and expires_at >= now();

  update users_profile
  set strikes_count = greatest(coalesce(v_cnt, 0), 0),
      suspended_until = case
        when coalesce(v_cnt, 0) >= 2 then v_max_expiry
        else null
      end,
      vehicle_suspended_until = case
        when coalesce(v_cnt, 0) >= 2 then v_max_expiry
        else null
      end
  where id = p_driver_id
    and exists (
      select 1
      from users_profile up
      where up.id = p_driver_id
        and (up.vehicle_brand is not null
             or up.vehicle_model is not null
             or up.vehicle_version is not null
             or up.vehicle_plate is not null)
    );

  if not found then
    update users_profile
    set strikes_count = greatest(coalesce(v_cnt, 0), 0),
        suspended_until = case
          when coalesce(v_cnt, 0) >= 2 then v_max_expiry
          else null
        end
    where id = p_driver_id;
  end if;
end $$;

-- 3) Ensure any new strike always recalculates profile state
drop trigger if exists trg_refresh_user_strike_state on strikes;
drop function if exists public.trg_refresh_user_strike_state();

create or replace function public.trg_refresh_user_strike_state()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.refresh_user_strike_state(
    case
      when tg_op = 'DELETE' then old.driver_id
      else new.driver_id
    end
  );
  return null;
end $$;

create trigger trg_refresh_user_strike_state
after insert or update or delete on strikes
for each row execute function public.trg_refresh_user_strike_state();

-- 4) Harden display semantics in API layer (optional read helper)
create or replace function public.get_profile_current_state(
  p_user_id uuid
)
returns setof users_profile
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.refresh_user_strike_state(p_user_id);

  return query
  select *
  from users_profile
  where id = p_user_id;
end $$;

create or replace function public.is_driver_banned_now(
  p_driver_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_banned boolean;
begin
  perform public.refresh_user_strike_state(p_driver_id);

  select coalesce(suspended_until, now() - interval '1 second') > now()
  into v_banned
  from users_profile
  where id = p_driver_id;

  return coalesce(v_banned, false);
end $$;

grant execute on function public.get_profile_current_state(uuid) to authenticated;
grant execute on function public.get_profile_current_state(uuid) to anon;
grant execute on function public.is_driver_banned_now(uuid) to authenticated;
grant execute on function public.is_driver_banned_now(uuid) to anon;

drop policy if exists "rides_driver_insert" on rides;
create policy "rides_driver_insert" on rides
  for insert
  with check (
    auth.uid() = driver_id
    and departure_at > timezone('America/Santiago', now())
    and exists (
      select 1
      from users_profile up
      where up.id = auth.uid()
        and up.accepted_terms = true
        and up.has_valid_license = true
        and not public.is_driver_banned_now(auth.uid())
    )
  );
