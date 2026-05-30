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
-- Turno MVP — Migration 00: Schema
-- Extensions, enums, tables, foreign keys, indexes
-- =============================================================

-- ── Extensions ───────────────────────────────────────────────
create extension if not exists "pgcrypto";

-- ── Enums ────────────────────────────────────────────────────
do $$ begin
  create type role_mode      as enum ('passenger','driver');
exception when duplicate_object then null; end $$;

do $$ begin
  create type ride_direction as enum ('to_campus','from_campus');
exception when duplicate_object then null; end $$;

do $$ begin
  create type booking_status as enum ('reserved','cancelled','completed','no_show');
exception when duplicate_object then null; end $$;

do $$ begin
  create type tx_type as enum (
    'topup','booking_hold','release_to_driver','platform_fee',
    'refund','withdrawal_request','withdrawal_paid','penalty'
  );
exception when duplicate_object then null; end $$;

-- ── Universities ─────────────────────────────────────────────
create table if not exists universities (
  id   uuid primary key default gen_random_uuid(),
  code text unique not null,   -- UDD, UANDES, PUC, UAI, UNAB
  name text        not null
);

-- ── Campuses ─────────────────────────────────────────────────
create table if not exists campuses (
  id            uuid primary key default gen_random_uuid(),
  university_id uuid not null references universities(id) on delete cascade,
  name          text not null,
  commune       text not null
);

-- ── Users profile (extends auth.users 1-to-1) ────────────────
create table if not exists users_profile (
  id                  uuid primary key references auth.users(id) on delete cascade,
  full_name           text,
  university_id       uuid references universities(id),
  campus_id           uuid references campuses(id),
  role_mode           role_mode not null default 'passenger',
  is_driver_verified  boolean   not null default false,
  strikes_count       int       not null default 0,
  suspended_until     timestamptz,
  created_at          timestamptz not null default now()
);

-- ── Wallets ──────────────────────────────────────────────────
create table if not exists wallets (
  user_id           uuid primary key references users_profile(id) on delete cascade,
  balance_available int  not null default 0 check (balance_available >= 0),
  balance_held      int  not null default 0 check (balance_held >= 0),
  updated_at        timestamptz not null default now()
);

-- ── Rides ────────────────────────────────────────────────────
create table if not exists rides (
  id              uuid         primary key default gen_random_uuid(),
  driver_id       uuid         not null references users_profile(id),
  university_id   uuid         not null references universities(id),
  campus_id       uuid         not null references campuses(id),
  origin_commune  text         not null
                    check (origin_commune in (
                      'Chicureo','Lo Barnechea','Providencia',
                      'Vitacura','La Reina','Buin'
                    )),
  direction       ride_direction not null,
  departure_at    timestamptz  not null,
  seat_price      int          not null default 2000 check (seat_price > 0),
  seats_total     int          not null check (seats_total > 0),
  seats_available int          not null check (seats_available >= 0),
  status          text         not null default 'active'
                    check (status in ('active','cancelled','completed')),
  created_at      timestamptz  not null default now()
);

-- ── Bookings ─────────────────────────────────────────────────
create table if not exists bookings (
  id           uuid           primary key default gen_random_uuid(),
  ride_id      uuid           not null references rides(id) on delete cascade,
  passenger_id uuid           not null references users_profile(id),
  amount_total int            not null default 2000,
  status       booking_status not null default 'reserved',
  confirmed_at timestamptz,
  created_at   timestamptz    not null default now(),
  unique (ride_id, passenger_id)
);

-- ── Transactions (immutable ledger — insert only) ────────────
create table if not exists transactions (
  id         uuid     primary key default gen_random_uuid(),
  user_id    uuid     not null references users_profile(id),
  booking_id uuid     references bookings(id),
  type       tx_type  not null,
  amount     int      not null,   -- positive = credit, negative = debit
  metadata   jsonb    not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- Prevent updates/deletes on the ledger
create or replace rule transactions_no_update as
  on update to transactions do instead nothing;

create or replace rule transactions_no_delete as
  on delete to transactions do instead nothing;

-- ── Withdrawals ──────────────────────────────────────────────
create table if not exists withdrawals (
  id           uuid primary key default gen_random_uuid(),
  driver_id    uuid not null references users_profile(id),
  amount       int  not null check (amount >= 20000),
  status       text not null default 'requested'
                 check (status in ('requested','processing','paid','rejected')),
  requested_at timestamptz not null default now(),
  processed_at timestamptz
);

-- ── Strikes ──────────────────────────────────────────────────
create table if not exists strikes (
  id         uuid primary key default gen_random_uuid(),
  driver_id  uuid not null references users_profile(id),
  reason     text not null,
  booking_id uuid references bookings(id),
  created_at timestamptz not null default now()
);

-- ── MP topup idempotency ──────────────────────────────────────
-- Stores external Mercado Pago payment IDs to prevent double-crediting.
create table if not exists mp_payments (
  external_payment_id text    primary key,
  user_id             uuid    not null references users_profile(id),
  amount              int     not null,
  status              text    not null default 'approved',
  created_at          timestamptz not null default now()
);

-- ── Indexes ──────────────────────────────────────────────────
create index if not exists idx_rides_search
  on rides (departure_at, campus_id, direction, status);

create index if not exists idx_rides_driver
  on rides (driver_id, created_at desc);

create index if not exists idx_bookings_passenger
  on bookings (passenger_id, created_at desc);

create index if not exists idx_bookings_ride
  on bookings (ride_id, status);

create index if not exists idx_transactions_user
  on transactions (user_id, created_at desc);

create index if not exists idx_withdrawals_driver
  on withdrawals (driver_id, requested_at desc);
