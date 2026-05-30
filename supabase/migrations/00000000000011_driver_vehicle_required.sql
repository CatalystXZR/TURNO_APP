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
-- Turno MVP — Migration 11: Driver vehicle registration data
-- =============================================================

alter table users_profile
  add column if not exists vehicle_brand text,
  add column if not exists vehicle_version text,
  add column if not exists vehicle_doors int,
  add column if not exists vehicle_body_type text;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'users_profile_vehicle_doors_ck'
  ) then
    alter table users_profile
      add constraint users_profile_vehicle_doors_ck
      check (vehicle_doors is null or vehicle_doors between 2 and 6);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'users_profile_driver_vehicle_required_ck'
  ) then
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
          and coalesce(trim(vehicle_body_type), '') <> ''
          and coalesce(trim(vehicle_plate), '') <> ''
        )
      )
      not valid;
  end if;
end $$;

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
    vehicle_body_type,
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
    nullif(new.raw_user_meta_data->>'vehicle_body_type', ''),
    nullif(upper(replace(new.raw_user_meta_data->>'vehicle_plate', ' ', '')), '')
  )
  on conflict (id) do nothing;

  insert into public.wallets (user_id, balance_available, balance_held)
  values (new.id, 0, 0)
  on conflict (user_id) do nothing;

  return new;
end $$;
