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
-- Turno — Migration 16: Public reviews + favorites
-- =============================================================

-- ----------
-- 1) Tables
-- ----------

create table if not exists booking_reviews (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references bookings(id) on delete cascade,
  ride_id uuid not null references rides(id) on delete cascade,
  reviewer_id uuid not null references users_profile(id) on delete cascade,
  reviewee_id uuid not null references users_profile(id) on delete cascade,
  reviewer_role role_mode not null,
  reviewee_role role_mode not null,
  stars int not null check (stars between 1 and 5),
  comment text,
  is_public boolean not null default true,
  created_at timestamptz not null default now(),
  constraint booking_reviews_one_per_reviewer unique (booking_id, reviewer_id),
  constraint booking_reviews_not_self check (reviewer_id <> reviewee_id),
  constraint booking_reviews_comment_len_ck
    check (comment is null or char_length(comment) <= 500)
);

create index if not exists idx_booking_reviews_reviewee_created
  on booking_reviews (reviewee_id, created_at desc);

create index if not exists idx_booking_reviews_reviewer_created
  on booking_reviews (reviewer_id, created_at desc);

create index if not exists idx_booking_reviews_booking
  on booking_reviews (booking_id);

create table if not exists user_favorites (
  user_id uuid not null references users_profile(id) on delete cascade,
  favorite_user_id uuid not null references users_profile(id) on delete cascade,
  source text not null default 'manual',
  created_at timestamptz not null default now(),
  primary key (user_id, favorite_user_id),
  constraint user_favorites_not_self check (user_id <> favorite_user_id)
);

create index if not exists idx_user_favorites_user_created
  on user_favorites (user_id, created_at desc);

create index if not exists idx_user_favorites_target_created
  on user_favorites (favorite_user_id, created_at desc);

-- ----------
-- 2) RLS
-- ----------

alter table booking_reviews enable row level security;
alter table user_favorites enable row level security;

drop policy if exists "booking_reviews_public_read" on booking_reviews;
create policy "booking_reviews_public_read" on booking_reviews
  for select
  using (
    is_public = true
    or auth.uid() = reviewer_id
    or auth.uid() = reviewee_id
  );

drop policy if exists "user_favorites_owner_read" on user_favorites;
create policy "user_favorites_owner_read" on user_favorites
  for select
  using (auth.uid() = user_id);

drop policy if exists "user_favorites_owner_insert" on user_favorites;
create policy "user_favorites_owner_insert" on user_favorites
  for insert
  with check (auth.uid() = user_id);

drop policy if exists "user_favorites_owner_delete" on user_favorites;
create policy "user_favorites_owner_delete" on user_favorites
  for delete
  using (auth.uid() = user_id);

-- ----------
-- 3) Rating recompute helper
-- ----------

create or replace function public.recompute_user_rating(
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_avg numeric(3,2);
  v_count int;
begin
  select
    coalesce(round(avg(stars)::numeric, 2), 5.00)::numeric(3,2),
    count(*)::int
  into v_avg, v_count
  from booking_reviews
  where reviewee_id = p_user_id;

  update users_profile
  set rating_avg = coalesce(v_avg, 5.00)::numeric(3,2),
      rating_count = coalesce(v_count, 0)
  where id = p_user_id;
end $$;

-- ----------
-- 4) Public review submit RPC
-- ----------

create or replace function public.submit_booking_review(
  p_booking_id uuid,
  p_stars int,
  p_comment text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_passenger uuid;
  v_driver uuid;
  v_ride_id uuid;
  v_status booking_status;
  v_dispatch booking_dispatch_status;
  v_trip_completed_at timestamptz;
  v_confirmed_at timestamptz;
  v_completed_at timestamptz;
  v_reviewer_role role_mode;
  v_reviewee_role role_mode;
  v_reviewee_id uuid;
  v_comment text;
  v_review_id uuid;
begin
  if v_user is null then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  if p_stars < 1 or p_stars > 5 then
    raise exception 'invalid_review_stars' using errcode = 'P0014';
  end if;

  select
    b.passenger_id,
    r.driver_id,
    b.ride_id,
    b.status,
    b.dispatch_status,
    b.trip_completed_at,
    b.confirmed_at
  into
    v_passenger,
    v_driver,
    v_ride_id,
    v_status,
    v_dispatch,
    v_trip_completed_at,
    v_confirmed_at
  from bookings b
  join rides r on r.id = b.ride_id
  where b.id = p_booking_id
  for update of b;

  if not found then
    raise exception 'booking not found or already processed' using errcode = 'P0005';
  end if;

  if v_status <> 'completed' or v_dispatch <> 'completed' then
    raise exception 'review_only_completed_trip' using errcode = 'P0014';
  end if;

  if v_user = v_passenger then
    v_reviewer_role := 'passenger'::role_mode;
    v_reviewee_role := 'driver'::role_mode;
    v_reviewee_id := v_driver;
  elsif v_user = v_driver then
    v_reviewer_role := 'driver'::role_mode;
    v_reviewee_role := 'passenger'::role_mode;
    v_reviewee_id := v_passenger;
  else
    raise exception 'forbidden' using errcode = 'P0006';
  end if;

  if v_reviewee_id is null or v_reviewee_id = v_user then
    raise exception 'invalid_review_target' using errcode = 'P0014';
  end if;

  v_completed_at := coalesce(v_trip_completed_at, v_confirmed_at, now());

  if now() > v_completed_at + interval '30 days' then
    raise exception 'review_window_expired' using errcode = 'P0014';
  end if;

  v_comment := nullif(trim(coalesce(p_comment, '')), '');

  begin
    insert into booking_reviews (
      booking_id,
      ride_id,
      reviewer_id,
      reviewee_id,
      reviewer_role,
      reviewee_role,
      stars,
      comment,
      is_public
    )
    values (
      p_booking_id,
      v_ride_id,
      v_user,
      v_reviewee_id,
      v_reviewer_role,
      v_reviewee_role,
      p_stars,
      v_comment,
      true
    )
    returning id into v_review_id;
  exception
    when unique_violation then
      raise exception 'review_already_submitted' using errcode = 'P0014';
  end;

  perform public.recompute_user_rating(v_reviewee_id);

  perform public.log_booking_event(
    p_booking_id,
    v_ride_id,
    v_user,
    v_reviewer_role::text,
    'completed'::booking_dispatch_status,
    'completed'::booking_dispatch_status,
    'review_submitted',
    jsonb_build_object(
      'review_id', v_review_id,
      'reviewee_id', v_reviewee_id,
      'stars', p_stars,
      'is_public', true
    )
  );

  return v_review_id;
end $$;

-- ----------
-- 5) Favorites RPCs
-- ----------

create or replace function public.toggle_favorite_user(
  p_target_user_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  if p_target_user_id is null then
    raise exception 'invalid_favorite_target' using errcode = 'P0014';
  end if;

  if p_target_user_id = v_user then
    raise exception 'favorite_self_forbidden' using errcode = 'P0014';
  end if;

  if not exists (select 1 from users_profile where id = p_target_user_id) then
    raise exception 'favorite_target_not_found' using errcode = 'P0005';
  end if;

  if exists (
    select 1
    from user_favorites
    where user_id = v_user
      and favorite_user_id = p_target_user_id
  ) then
    delete from user_favorites
    where user_id = v_user
      and favorite_user_id = p_target_user_id;
    return false;
  end if;

  insert into user_favorites (user_id, favorite_user_id)
  values (v_user, p_target_user_id);
  return true;
end $$;

create or replace function public.list_my_favorites(
  p_role_filter text default null,
  p_limit int default 100
)
returns table (
  favorite_user_id uuid,
  full_name text,
  role_mode role_mode,
  rating_avg numeric(3,2),
  rating_count int,
  profile_photo_url text,
  vehicle_model text,
  vehicle_plate text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_filter text := nullif(lower(trim(coalesce(p_role_filter, ''))), '');
begin
  if v_user is null then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  if v_filter is not null and v_filter not in ('driver', 'passenger') then
    raise exception 'invalid_role_filter' using errcode = 'P0014';
  end if;

  return query
  select
    uf.favorite_user_id,
    up.full_name,
    up.role_mode,
    up.rating_avg,
    up.rating_count,
    up.profile_photo_url,
    up.vehicle_model,
    up.vehicle_plate,
    uf.created_at
  from user_favorites uf
  join users_profile up on up.id = uf.favorite_user_id
  where uf.user_id = v_user
    and (v_filter is null or up.role_mode::text = v_filter)
  order by uf.created_at desc
  limit greatest(least(coalesce(p_limit, 100), 200), 1);
end $$;

-- ----------
-- 6) Public references RPC
-- ----------

create or replace function public.get_public_user_reviews(
  p_user_id uuid,
  p_limit int default 5
)
returns table (
  id uuid,
  booking_id uuid,
  ride_id uuid,
  stars int,
  comment text,
  created_at timestamptz,
  reviewer_id uuid,
  reviewer_role role_mode,
  reviewer_name text,
  reviewer_photo_url text,
  reviewer_rating_avg numeric(3,2),
  reviewer_rating_count int
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select
    br.id,
    br.booking_id,
    br.ride_id,
    br.stars,
    br.comment,
    br.created_at,
    br.reviewer_id,
    br.reviewer_role,
    up.full_name,
    up.profile_photo_url,
    up.rating_avg,
    up.rating_count
  from booking_reviews br
  join users_profile up on up.id = br.reviewer_id
  where br.reviewee_id = p_user_id
    and br.is_public = true
  order by br.created_at desc
  limit greatest(least(coalesce(p_limit, 5), 20), 1);
end $$;

-- ----------
-- 7) Grants
-- ----------

revoke execute on function public.recompute_user_rating(uuid) from public;
revoke execute on function public.recompute_user_rating(uuid) from authenticated;
revoke execute on function public.recompute_user_rating(uuid) from anon;

revoke execute on function public.submit_booking_review(uuid, int, text) from public;
revoke execute on function public.submit_booking_review(uuid, int, text) from authenticated;
revoke execute on function public.submit_booking_review(uuid, int, text) from anon;

revoke execute on function public.toggle_favorite_user(uuid) from public;
revoke execute on function public.toggle_favorite_user(uuid) from authenticated;
revoke execute on function public.toggle_favorite_user(uuid) from anon;

revoke execute on function public.list_my_favorites(text, int) from public;
revoke execute on function public.list_my_favorites(text, int) from authenticated;
revoke execute on function public.list_my_favorites(text, int) from anon;

revoke execute on function public.get_public_user_reviews(uuid, int) from public;
revoke execute on function public.get_public_user_reviews(uuid, int) from authenticated;
revoke execute on function public.get_public_user_reviews(uuid, int) from anon;

grant execute on function public.submit_booking_review(uuid, int, text) to authenticated;
grant execute on function public.toggle_favorite_user(uuid) to authenticated;
grant execute on function public.list_my_favorites(text, int) to authenticated;
grant execute on function public.get_public_user_reviews(uuid, int) to authenticated;
grant execute on function public.get_public_user_reviews(uuid, int) to anon;
