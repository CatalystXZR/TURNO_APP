/**
 *
 * Project: Turno
 *
 * Original Concept: Agustín Puelma, Cristobal Cordova, Carlos Ibarra
 *
 * Software Architecture & Code: Matías Toledo (catalystxzr)
 *
 * Description: Production-grade implementation for UDD carpooling system.
 *
 * Copyright (c) 2026. All rights reserved.
 *
 */

-- =============================================================
-- Turno MVP — Migration 03: Auth Trigger
-- Automatically creates users_profile + wallets rows whenever
-- a new user signs up via Supabase Auth.
-- This removes the manual upsert calls from register_screen.dart
-- (though those calls are safe to keep as idempotent fallbacks).
-- =============================================================

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Create profile row
  insert into public.users_profile (id, full_name)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data->>'full_name',
      split_part(new.email, '@', 1)   -- fallback: username part of email
    )
  )
  on conflict (id) do nothing;   -- safe if register_screen.dart already inserted

  -- Create wallet row
  insert into public.wallets (user_id, balance_available, balance_held)
  values (new.id, 0, 0)
  on conflict (user_id) do nothing;

  return new;
end $$;

-- Drop the trigger first (idempotent re-runs)
drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();
