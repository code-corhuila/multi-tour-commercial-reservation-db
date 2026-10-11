-- Reverses 001_create_schema_commercial_reservation.sql. It does not use CASCADE on purpose:
-- by the time it runs, the rollbacks of every later changeset have already removed their objects.
DROP SCHEMA commercial_reservation;
