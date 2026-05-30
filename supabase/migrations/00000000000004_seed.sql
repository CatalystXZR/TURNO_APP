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
-- Turno MVP — Migration 04: Seed Data
-- Universities and their campuses for the 6 target institutions.
-- Uses fixed UUIDs so re-running this migration is idempotent.
-- =============================================================

-- ── Universities ─────────────────────────────────────────────
insert into universities (id, code, name) values
  ('11111111-0000-0000-0000-000000000001', 'UDD',    'Universidad del Desarrollo'),
  ('11111111-0000-0000-0000-000000000002', 'UANDES', 'Universidad de los Andes'),
  ('11111111-0000-0000-0000-000000000003', 'PUC',    'Pontificia Universidad Catolica de Chile'),
  ('11111111-0000-0000-0000-000000000004', 'UCH',    'Universidad de Chile'),
  ('11111111-0000-0000-0000-000000000005', 'UNAB',   'Universidad Andres Bello'),
  ('11111111-0000-0000-0000-000000000006', 'UAI',    'Universidad Adolfo Ibanez')
on conflict (id) do nothing;

-- ── Campuses ─────────────────────────────────────────────────

-- UDD
insert into campuses (id, university_id, name, commune) values
  ('22222222-0001-0000-0000-000000000001', '11111111-0000-0000-0000-000000000001', 'Campus Rector Ernesto Silva Bafalluy', 'Santiago'),
  ('22222222-0001-0000-0000-000000000002', '11111111-0000-0000-0000-000000000001', 'Clinica Universidad del Desarrollo', 'Santiago')
on conflict (id) do nothing;

-- UANDES
insert into campuses (id, university_id, name, commune) values
  ('22222222-0002-0000-0000-000000000001', '11111111-0000-0000-0000-000000000002', 'Campus Universitario UANDES', 'Las Condes')
on conflict (id) do nothing;

-- PUC
insert into campuses (id, university_id, name, commune) values
  ('22222222-0003-0000-0000-000000000001', '11111111-0000-0000-0000-000000000003', 'Casa Central PUC',       'Santiago'),
  ('22222222-0003-0000-0000-000000000002', '11111111-0000-0000-0000-000000000003', 'Campus San Joaquin',    'San Joaquin'),
  ('22222222-0003-0000-0000-000000000003', '11111111-0000-0000-0000-000000000003', 'Campus Oriente',        'Macul'),
  ('22222222-0003-0000-0000-000000000004', '11111111-0000-0000-0000-000000000003', 'Campus Lo Contador',    'Providencia')
on conflict (id) do nothing;

-- UCH
insert into campuses (id, university_id, name, commune) values
  ('22222222-0004-0000-0000-000000000001', '11111111-0000-0000-0000-000000000004', 'Campus Andres Bello',          'Santiago'),
  ('22222222-0004-0000-0000-000000000002', '11111111-0000-0000-0000-000000000004', 'Campus Beauchef',              'Santiago'),
  ('22222222-0004-0000-0000-000000000003', '11111111-0000-0000-0000-000000000004', 'Campus Juan Gomez Millas',     'Nunoa'),
  ('22222222-0004-0000-0000-000000000004', '11111111-0000-0000-0000-000000000004', 'Campus Dra. Eloisa Diaz',      'Independencia'),
  ('22222222-0004-0000-0000-000000000005', '11111111-0000-0000-0000-000000000004', 'Campus Sur (Antumapu)',        'La Pintana')
on conflict (id) do nothing;

-- UAI
insert into campuses (id, university_id, name, commune) values
  ('22222222-0005-0000-0000-000000000001', '11111111-0000-0000-0000-000000000006', 'Campus Penalolen',           'Penalolen'),
  ('22222222-0005-0000-0000-000000000002', '11111111-0000-0000-0000-000000000006', 'Sede Presidente Errazuriz',  'Santiago')
on conflict (id) do nothing;

-- UNAB
insert into campuses (id, university_id, name, commune) values
  ('22222222-0006-0000-0000-000000000001', '11111111-0000-0000-0000-000000000005', 'Campus Republica',              'Santiago'),
  ('22222222-0006-0000-0000-000000000002', '11111111-0000-0000-0000-000000000005', 'Campus Casona de Las Condes',  'Las Condes'),
  ('22222222-0006-0000-0000-000000000003', '11111111-0000-0000-0000-000000000005', 'Campus Bellavista',             'Providencia'),
  ('22222222-0006-0000-0000-000000000004', '11111111-0000-0000-0000-000000000005', 'Campus Los Leones',             'Providencia'),
  ('22222222-0006-0000-0000-000000000005', '11111111-0000-0000-0000-000000000005', 'Campus Antonio Varas',          'Providencia'),
  ('22222222-0006-0000-0000-000000000006', '11111111-0000-0000-0000-000000000005', 'Campus Creativo',               'Santiago')
on conflict (id) do nothing;
