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
-- Turno MVP — Migration 10: Profile photos storage bucket
-- =============================================================

insert into storage.buckets (id, name, public)
values ('profile-photos', 'profile-photos', true)
on conflict (id) do update
set public = true;

drop policy if exists "profile_photos_public_read" on storage.objects;
create policy "profile_photos_public_read"
on storage.objects for select
using (bucket_id = 'profile-photos');

drop policy if exists "profile_photos_auth_insert" on storage.objects;
create policy "profile_photos_auth_insert"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'profile-photos'
  and split_part(name, '/', 1) = auth.uid()::text
);

drop policy if exists "profile_photos_auth_update" on storage.objects;
create policy "profile_photos_auth_update"
on storage.objects for update
to authenticated
using (
  bucket_id = 'profile-photos'
  and split_part(name, '/', 1) = auth.uid()::text
)
with check (
  bucket_id = 'profile-photos'
  and split_part(name, '/', 1) = auth.uid()::text
);

drop policy if exists "profile_photos_auth_delete" on storage.objects;
create policy "profile_photos_auth_delete"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'profile-photos'
  and split_part(name, '/', 1) = auth.uid()::text
);
