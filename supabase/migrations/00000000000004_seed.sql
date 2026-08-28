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
  ('22222222-0001-0000-0000-000000000001', '11111111-0000-0000-0000-000000000001', 'Rector Ernesto Silva Bafalluy', 'Las Condes'),
  ('22222222-0001-0000-0000-000000000002', '11111111-0000-0000-0000-000000000001', 'Las Condes',                  'Las Condes')
on conflict (id) do nothing;

-- UANDES
insert into campuses (id, university_id, name, commune) values
  ('22222222-0002-0000-0000-000000000001', '11111111-0000-0000-0000-000000000002', 'Campus Universitario UANDES', 'Las Condes')
on conflict (id) do nothing;

-- PUC
insert into campuses (id, university_id, name, commune) values
  ('22222222-0003-0000-0000-000000000001', '11111111-0000-0000-0000-000000000003', 'Casa Central',    'Santiago'),
  ('22222222-0003-0000-0000-000000000002', '11111111-0000-0000-0000-000000000003', 'San Joaquín',     'Macul'),
  ('22222222-0003-0000-0000-000000000003', '11111111-0000-0000-0000-000000000003', 'Oriente',         'Providencia'),
  ('22222222-0003-0000-0000-000000000004', '11111111-0000-0000-0000-000000000003', 'Lo Contador',     'Providencia'),
  ('22222222-0003-0000-0000-000000000005', '11111111-0000-0000-0000-000000000003', 'Villarrica',      'Villarrica')
on conflict (id) do nothing;

-- UCH
insert into campuses (id, university_id, name, commune) values
  ('22222222-0004-0000-0000-000000000001', '11111111-0000-0000-0000-000000000004', 'Andrés Bello',        'Providencia'),
  ('22222222-0004-0000-0000-000000000002', '11111111-0000-0000-0000-000000000004', 'Beauchef',            'Santiago'),
  ('22222222-0004-0000-0000-000000000003', '11111111-0000-0000-0000-000000000004', 'Juan Gómez Millas',   'Ñuñoa'),
  ('22222222-0004-0000-0000-000000000004', '11111111-0000-0000-0000-000000000004', 'Norte',               'Independencia'),
  ('22222222-0004-0000-0000-000000000005', '11111111-0000-0000-0000-000000000004', 'Sur',                 'La Pintana'),
  ('22222222-0004-0000-0000-000000000006', '11111111-0000-0000-0000-000000000004', 'Casa Central',        'Santiago')
on conflict (id) do nothing;

-- UAI
insert into campuses (id, university_id, name, commune) values
  ('22222222-0005-0000-0000-000000000001', '11111111-0000-0000-0000-000000000006', 'Peñalolén',           'Peñalolén'),
  ('22222222-0005-0000-0000-000000000002', '11111111-0000-0000-0000-000000000006', 'Presidente Errázuriz', 'Las Condes')
on conflict (id) do nothing;

-- UNAB
insert into campuses (id, university_id, name, commune) values
  ('22222222-0006-0000-0000-000000000001', '11111111-0000-0000-0000-000000000005', 'República',             'Santiago'),
  ('22222222-0006-0000-0000-000000000002', '11111111-0000-0000-0000-000000000005', 'Casona de Las Condes',  'Las Condes'),
  ('22222222-0006-0000-0000-000000000003', '11111111-0000-0000-0000-000000000005', 'Bellavista',            'Providencia'),
  ('22222222-0006-0000-0000-000000000004', '11111111-0000-0000-0000-000000000005', 'Los Leones',            'Providencia'),
  ('22222222-0006-0000-0000-000000000005', '11111111-0000-0000-0000-000000000005', 'Antonio Varas',         'Providencia'),
  ('22222222-0006-0000-0000-000000000006', '11111111-0000-0000-0000-000000000005', 'Creativo',              'Recoleta')
on conflict (id) do nothing;
