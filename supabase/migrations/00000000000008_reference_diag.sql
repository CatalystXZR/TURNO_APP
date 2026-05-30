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
-- Turno MVP — Migration 08: Reference access diagnostics
--
-- Adds lightweight diagnostics to quickly verify that
-- universities/campuses are queryable from anon/authenticated clients.
-- This does not change business data or financial logic.
-- =============================================================

create or replace function public.reference_access_diag()
returns table (
  universities_count bigint,
  campuses_count bigint,
  current_uid uuid,
  jwt_role text
)
language sql
security definer
set search_path = public
as $$
  select
    (select count(*) from public.universities) as universities_count,
    (select count(*) from public.campuses) as campuses_count,
    auth.uid() as current_uid,
    coalesce(current_setting('request.jwt.claim.role', true), 'unknown') as jwt_role;
$$;

grant execute on function public.reference_access_diag() to anon, authenticated;
