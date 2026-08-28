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
-- Turno — Migration 34: Campus reference corrections
-- =============================================================
-- Fixes campus names / communes and restores the correct
-- university_id for every campus. This also repairs the rows that
-- migration 09 reassigned to the wrong university.
--
-- All statements are idempotent (target rows by fixed UUID).

-- ----------
-- UDD
-- ----------

update campuses set university_id = '11111111-0000-0000-0000-000000000001', name = 'Rector Ernesto Silva Bafalluy', commune = 'Las Condes'
where id = '22222222-0001-0000-0000-000000000001';

update campuses set university_id = '11111111-0000-0000-0000-000000000001', name = 'Las Condes', commune = 'Las Condes'
where id = '22222222-0001-0000-0000-000000000002';

-- ----------
-- UANDES
-- ----------

update campuses set university_id = '11111111-0000-0000-0000-000000000002', name = 'Campus Universitario UANDES', commune = 'Las Condes'
where id = '22222222-0002-0000-0000-000000000001';

-- ----------
-- PUC
-- ----------

update campuses set university_id = '11111111-0000-0000-0000-000000000003', name = 'Casa Central', commune = 'Santiago'
where id = '22222222-0003-0000-0000-000000000001';

update campuses set university_id = '11111111-0000-0000-0000-000000000003', name = 'San Joaquín', commune = 'Macul'
where id = '22222222-0003-0000-0000-000000000002';

update campuses set university_id = '11111111-0000-0000-0000-000000000003', name = 'Oriente', commune = 'Providencia'
where id = '22222222-0003-0000-0000-000000000003';

update campuses set university_id = '11111111-0000-0000-0000-000000000003', name = 'Lo Contador', commune = 'Providencia'
where id = '22222222-0003-0000-0000-000000000004';

insert into campuses (id, university_id, name, commune) values
  ('22222222-0003-0000-0000-000000000005', '11111111-0000-0000-0000-000000000003', 'Villarrica', 'Villarrica')
on conflict (id) do nothing;

-- ----------
-- UCH
-- ----------

update campuses set university_id = '11111111-0000-0000-0000-000000000004', name = 'Andrés Bello', commune = 'Providencia'
where id = '22222222-0004-0000-0000-000000000001';

update campuses set university_id = '11111111-0000-0000-0000-000000000004', name = 'Beauchef', commune = 'Santiago'
where id = '22222222-0004-0000-0000-000000000002';

update campuses set university_id = '11111111-0000-0000-0000-000000000004', name = 'Juan Gómez Millas', commune = 'Ñuñoa'
where id = '22222222-0004-0000-0000-000000000003';

update campuses set university_id = '11111111-0000-0000-0000-000000000004', name = 'Norte', commune = 'Independencia'
where id = '22222222-0004-0000-0000-000000000004';

update campuses set university_id = '11111111-0000-0000-0000-000000000004', name = 'Sur', commune = 'La Pintana'
where id = '22222222-0004-0000-0000-000000000005';

insert into campuses (id, university_id, name, commune) values
  ('22222222-0004-0000-0000-000000000006', '11111111-0000-0000-0000-000000000004', 'Casa Central', 'Santiago')
on conflict (id) do nothing;

-- ----------
-- UAI
-- ----------

update campuses set university_id = '11111111-0000-0000-0000-000000000006', name = 'Peñalolén', commune = 'Peñalolén'
where id = '22222222-0005-0000-0000-000000000001';

update campuses set university_id = '11111111-0000-0000-0000-000000000006', name = 'Presidente Errázuriz', commune = 'Las Condes'
where id = '22222222-0005-0000-0000-000000000002';

-- ----------
-- UNAB
-- ----------

update campuses set university_id = '11111111-0000-0000-0000-000000000005', name = 'República', commune = 'Santiago'
where id = '22222222-0006-0000-0000-000000000001';

update campuses set university_id = '11111111-0000-0000-0000-000000000005', name = 'Casona de Las Condes', commune = 'Las Condes'
where id = '22222222-0006-0000-0000-000000000002';

update campuses set university_id = '11111111-0000-0000-0000-000000000005', name = 'Bellavista', commune = 'Providencia'
where id = '22222222-0006-0000-0000-000000000003';

update campuses set university_id = '11111111-0000-0000-0000-000000000005', name = 'Los Leones', commune = 'Providencia'
where id = '22222222-0006-0000-0000-000000000004';

update campuses set university_id = '11111111-0000-0000-0000-000000000005', name = 'Antonio Varas', commune = 'Providencia'
where id = '22222222-0006-0000-0000-000000000005';

update campuses set university_id = '11111111-0000-0000-0000-000000000005', name = 'Creativo', commune = 'Recoleta'
where id = '22222222-0006-0000-0000-000000000006';
