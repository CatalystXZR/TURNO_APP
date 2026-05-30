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
-- Turno MVP — Migration 06: Public read access for reference tables
-- =============================================================
--
-- universities and campuses are reference/seed data that must be
-- readable by unauthenticated users (anon role) so that:
--   1. The registration screen can list universities before login.
--   2. The search screen can list campuses before login.
--
-- RLS is NOT enabled on these tables (they contain no sensitive data).
-- We simply grant SELECT to both the anon and authenticated roles.
--
-- Without this grant PostgREST blocks all queries from the anon role
-- even when RLS is disabled, which causes an empty dropdown on the
-- registration screen.
-- =============================================================

grant select on table universities to anon, authenticated;
grant select on table campuses     to anon, authenticated;
