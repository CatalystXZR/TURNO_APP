-- =============================================================
-- Turno — Migration 31: UGC Reporting & Blocking System
-- =============================================================
--
-- Purpose: Apple App Store Guideline 1.2 compliance.
-- Adds user reporting and blocking for a platform with user-
-- generated content (reviews, profiles, inter-user messaging).
--
-- Tables:
--   user_reports  — Reports of abusive/inappropriate users
--   user_blocks   — Blocks between users (prevents interaction)
--
-- RPCs:
--   report_user           — Submit a user report
--   block_user            — Block a user
--   unblock_user          — Unblock a user
--   is_user_blocked       — Check if a user is blocked
--   get_blocked_user_ids  — Get list of blocked user IDs
--
-- Also updates delete_user_account to accept p_reason parameter.
-- =============================================================

begin;

-- =============================================================
-- A) USER REPORTS TABLE
-- =============================================================

create table if not exists user_reports (
    id uuid primary key default gen_random_uuid(),
    reporter_id uuid not null references auth.users(id) on delete cascade,
    reported_user_id uuid not null references auth.users(id) on delete cascade,
    reason_category text not null,
        -- 'harassment', 'fake_profile', 'dangerous_driving',
        -- 'passenger_misconduct', 'no_show', 'other'
    details text,
    booking_id uuid references bookings(id) on delete set null,
    created_at timestamptz not null default now(),
    resolved_at timestamptz,
    resolution_notes text
);

comment on table user_reports is 'User-generated reports of abusive or inappropriate behavior (Apple Guideline 1.2 compliance).';
comment on column user_reports.reason_category is 'Category: harassment, fake_profile, dangerous_driving, passenger_misconduct, no_show, other';
comment on column user_reports.booking_id is 'Optional link to a booking associated with the report.';

-- Index for efficient lookups by reporter and reported user
create index if not exists idx_user_reports_reporter on user_reports(reporter_id);
create index if not exists idx_user_reports_reported on user_reports(reported_user_id);

-- =============================================================
-- B) USER BLOCKS TABLE
-- =============================================================

create table if not exists user_blocks (
    id uuid primary key default gen_random_uuid(),
    blocker_id uuid not null references auth.users(id) on delete cascade,
    blocked_user_id uuid not null references auth.users(id) on delete cascade,
    created_at timestamptz not null default now(),
    unique(blocker_id, blocked_user_id)
);

comment on table user_blocks is 'User-to-user block records. Blocked users cannot interact with the blocker.';

create index if not exists idx_user_blocks_blocker on user_blocks(blocker_id);
create index if not exists idx_user_blocks_blocked on user_blocks(blocked_user_id);

-- =============================================================
-- C) RLS POLICIES
-- =============================================================

alter table user_reports enable row level security;
alter table user_blocks enable row level security;

-- user_reports: reporters can see their own reports
create policy "Reporters can view their own reports"
    on user_reports for select
    using (reporter_id = auth.uid());

-- user_reports: any authenticated user can create a report
create policy "Authenticated users can create reports"
    on user_reports for insert
    with check (reporter_id = auth.uid());

-- user_blocks: users can see their own blocks
create policy "Users can view their own blocks"
    on user_blocks for select
    using (blocker_id = auth.uid());

-- user_blocks: users can create their own blocks
create policy "Users can create their own blocks"
    on user_blocks for insert
    with check (blocker_id = auth.uid());

-- user_blocks: users can delete their own blocks
create policy "Users can delete their own blocks"
    on user_blocks for delete
    using (blocker_id = auth.uid());

-- =============================================================
-- D) RPC: report_user
--    Submits a report against another user.
-- =============================================================

create or replace function public.report_user(
    p_reported_user_id uuid,
    p_reason_category text,
    p_details text default null,
    p_booking_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_reporter uuid := auth.uid();
    v_report_id uuid;
    v_valid_categories text[] := array[
        'harassment',
        'fake_profile',
        'dangerous_driving',
        'passenger_misconduct',
        'no_show',
        'other'
    ];
begin
    if v_reporter is null then
        raise exception 'Sesion requerida' using errcode = 'P0001';
    end if;

    if p_reported_user_id = v_reporter then
        raise exception 'No puedes reportarte a ti mismo' using errcode = 'P0006';
    end if;

    if not (p_reason_category = any(v_valid_categories)) then
        raise exception 'Categoria de reporte invalida. Valores permitidos: harassment, fake_profile, dangerous_driving, passenger_misconduct, no_show, other'
            using errcode = 'P0006';
    end if;

    insert into user_reports (
        reporter_id,
        reported_user_id,
        reason_category,
        details,
        booking_id
    )
    values (
        v_reporter,
        p_reported_user_id,
        p_reason_category,
        p_details,
        p_booking_id
    )
    returning id into v_report_id;

    return v_report_id;
end $$;

-- =============================================================
-- E) RPC: block_user
--    Blocks a user. Blocked users cannot:
--      - Book rides published by the blocker
--      - See the blocker's profile details
--      - Be booked by the blocker (for passenger blocks)
-- =============================================================

create or replace function public.block_user(p_blocked_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_blocker uuid := auth.uid();
begin
    if v_blocker is null then
        raise exception 'Sesion requerida' using errcode = 'P0001';
    end if;

    if p_blocked_user_id = v_blocker then
        raise exception 'No puedes bloquearte a ti mismo' using errcode = 'P0006';
    end if;

    insert into user_blocks (blocker_id, blocked_user_id)
    values (v_blocker, p_blocked_user_id)
    on conflict (blocker_id, blocked_user_id) do nothing;
end $$;

-- =============================================================
-- F) RPC: unblock_user
-- =============================================================

create or replace function public.unblock_user(p_blocked_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_blocker uuid := auth.uid();
begin
    if v_blocker is null then
        raise exception 'Sesion requerida' using errcode = 'P0001';
    end if;

    delete from user_blocks
    where blocker_id = v_blocker
      and blocked_user_id = p_blocked_user_id;
end $$;

-- =============================================================
-- G) RPC: is_user_blocked
--    Returns true if the target user is blocked by the caller
--    OR if the caller is blocked by the target.
-- =============================================================

create or replace function public.is_user_blocked(p_target_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
    v_user uuid := auth.uid();
begin
    if v_user is null then
        return false;
    end if;

    return exists (
        select 1 from user_blocks
        where (blocker_id = v_user and blocked_user_id = p_target_user_id)
           or (blocker_id = p_target_user_id and blocked_user_id = v_user)
    );
end $$;

-- =============================================================
-- H) RPC: get_blocked_user_ids
--    Returns list of user IDs blocked by the caller.
-- =============================================================

create or replace function public.get_blocked_user_ids()
returns table (blocked_user_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
    v_user uuid := auth.uid();
begin
    if v_user is null then
        return;
    end if;

    return query
        select ub.blocked_user_id
        from user_blocks ub
        where ub.blocker_id = v_user;
end $$;

-- =============================================================
-- I) UPDATE create_booking: Reject if blocked
--    Prevents a blocked user from booking rides published
--    by the blocker.
-- =============================================================

create or replace function public.create_booking(p_ride_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_booking_id uuid;
  v_base_price int;
  v_total_charge int;
  v_driver uuid;
  v_departure timestamp;
  v_now timestamp := public.current_chile_time();
begin
  if v_user is null then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  select r.seat_price, r.platform_fee, r.driver_id, r.departure_at
    into v_base_price, v_total_charge, v_driver, v_departure
  from rides r
  where r.id = p_ride_id
    and r.seats_available > 0
    and r.status = 'active'
  for update;

  v_total_charge := v_base_price + v_total_charge;

  if not found then
    raise exception 'ride unavailable' using errcode = 'P0002';
  end if;

  if v_driver = v_user then
    raise exception 'cannot_book_own_ride' using errcode = 'P0011';
  end if;

  -- Block check: prevent bookings between blocked users
  if exists (
    select 1 from user_blocks
    where (blocker_id = v_user and blocked_user_id = v_driver)
       or (blocker_id = v_driver and blocked_user_id = v_user)
  ) then
    raise exception 'user_blocked' using errcode = 'P0019';
  end if;

  if v_departure <= v_now then
    raise exception 'ride_departed' using errcode = 'P0010';
  end if;

  if exists (
    select 1
    from bookings
    where ride_id = p_ride_id
      and passenger_id = v_user
      and status = 'reserved'
  ) then
    raise exception 'already booked' using errcode = 'P0003';
  end if;

  if not public.check_no_overlapping_booking(v_user, v_departure, p_ride_id) then
    raise exception 'overlapping_booking' using errcode = 'P0016';
  end if;

  -- Anti-griefing: enforce 15-minute cooldown after cancelling on same ride
  if exists (
    select 1
    from users_profile up
    where up.id = v_user
      and up.last_cancelled_ride_id = p_ride_id
      and up.last_cancelled_at is not null
      and up.last_cancelled_at > now() - interval '15 minutes'
  ) then
    raise exception 'cancellation_cooldown' using errcode = 'P0018';
  end if;

  update wallets
  set balance_available = balance_available - v_total_charge,
      balance_held = balance_held + v_total_charge,
      updated_at = now()
  where user_id = v_user
    and balance_available >= v_total_charge;

  if not found then
    raise exception 'insufficient balance' using errcode = 'P0004';
  end if;

  update rides
  set seats_available = seats_available - 1
  where id = p_ride_id
    and seats_available > 0;

  if not found then
    raise exception 'ride unavailable' using errcode = 'P0002';
  end if;

  insert into bookings (
    ride_id,
    passenger_id,
    amount_total,
    status,
    dispatch_status
  )
  values (
    p_ride_id,
    v_user,
    v_total_charge,
    'reserved',
    'reserved'
  )
  returning id into v_booking_id;

  insert into transactions (user_id, booking_id, type, amount, metadata)
  values (
    v_user,
    v_booking_id,
    'booking_hold',
    -v_total_charge,
    jsonb_build_object('ride_id', p_ride_id)
  );

  perform public.log_booking_event(
    v_booking_id,
    p_ride_id,
    v_user,
    'passenger',
    'reserved'::booking_dispatch_status,
    'reserved'::booking_dispatch_status,
    'booking_created',
    jsonb_build_object('amount_total', v_total_charge)
  );

  return v_booking_id;
end $$;

-- =============================================================
-- J) UPDATE delete_user_account: Accept p_reason
--    Also clean up user_reports and user_blocks for the deleted user.
-- =============================================================

create or replace function public.delete_user_account(
    p_user_id uuid default null,
    p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid;
begin
  if p_user_id is not null then
    v_user := p_user_id;
  else
    v_user := auth.uid();
  end if;

  if v_user is null then
    raise exception 'Sesion requerida' using errcode = 'P0001';
  end if;

  -- Temporarily drop ledger immutability rules so we can clean up
  drop rule if exists transactions_no_delete on transactions;
  drop rule if exists transactions_no_update on transactions;

  delete from transactions
  where user_id = v_user
     or booking_id in (
       select id from bookings where passenger_id = v_user
     )
     or booking_id in (
       select b.id
       from bookings b
       join rides r on r.id = b.ride_id
       where r.driver_id = v_user
     );

  create or replace rule transactions_no_delete as
    on delete to transactions do instead nothing;

  create or replace rule transactions_no_update as
    on update to transactions do instead nothing;

  -- Clean up user reports made by or against this user
  delete from user_reports where reporter_id = v_user or reported_user_id = v_user;

  -- Clean up user blocks made by or against this user
  delete from user_blocks where blocker_id = v_user or blocked_user_id = v_user;

  delete from bookings where passenger_id = v_user;
  delete from rides where driver_id = v_user;

  delete from withdrawals where driver_id = v_user;
  delete from fintoc_payments where user_id = v_user;
  delete from mp_payments where user_id = v_user;
  delete from strikes where driver_id = v_user;

  delete from wallets where user_id = v_user;
  delete from users_profile where id = v_user;
  delete from auth.users where id = v_user;
end $$;

-- =============================================================
-- K) Grants
-- =============================================================

grant execute on function public.report_user(uuid, text, text, uuid) to authenticated;
grant execute on function public.block_user(uuid) to authenticated;
grant execute on function public.unblock_user(uuid) to authenticated;
grant execute on function public.is_user_blocked(uuid) to authenticated;
grant execute on function public.get_blocked_user_ids() to authenticated;
grant execute on function public.create_booking(uuid) to authenticated;
grant execute on function public.delete_user_account(uuid, text) to authenticated;
grant execute on function public.delete_user_account(uuid, text) to service_role;

commit;
