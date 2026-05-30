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

-- Migration 07: Enable RLS on reference tables and add public-read policies.
-- The GRANT SELECT in migration 06 is necessary but not sufficient when the
-- Supabase Dashboard has RLS enabled on a table.  These policies make the
-- tables readable by everyone (anon + authenticated) regardless of Dashboard
-- state, and are safe because universities / campuses contain no sensitive data.

-- universities
ALTER TABLE universities ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "universities_public_read" ON universities;
CREATE POLICY "universities_public_read"
  ON universities
  FOR SELECT
  USING (true);

-- campuses
ALTER TABLE campuses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "campuses_public_read" ON campuses;
CREATE POLICY "campuses_public_read"
  ON campuses
  FOR SELECT
  USING (true);
