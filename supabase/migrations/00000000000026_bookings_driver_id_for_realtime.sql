-- =============================================================
-- Turno — Migration 26: bookings.driver_id for efficient realtime
-- =============================================================

alter table bookings
  add column if not exists driver_id uuid references users_profile(id);

update bookings b
set driver_id = r.driver_id
from rides r
where r.id = b.ride_id
  and b.driver_id is null;

create or replace function set_booking_driver_id()
returns trigger
language plpgsql
as $$
begin
  if new.driver_id is null then
    select r.driver_id into new.driver_id
    from rides r
    where r.id = new.ride_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_bookings_set_driver_id on bookings;

create trigger trg_bookings_set_driver_id
before insert or update of ride_id, driver_id on bookings
for each row
execute function set_booking_driver_id();

create index if not exists idx_bookings_driver
  on bookings (driver_id, created_at desc);
