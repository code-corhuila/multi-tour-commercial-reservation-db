GRANT USAGE ON SCHEMA commercial_reservation TO commercial_reservation_reader;

-- Both forms are needed. DDL runs before DCL, so on a rebuild the tables already exist when this runs
-- and only ALL TABLES reaches them; on an environment already migrated, a table created later is
-- reached only by the default privileges. Either one alone leaves a gap.
GRANT SELECT ON ALL TABLES IN SCHEMA commercial_reservation TO commercial_reservation_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA commercial_reservation GRANT SELECT ON TABLES TO commercial_reservation_reader;
