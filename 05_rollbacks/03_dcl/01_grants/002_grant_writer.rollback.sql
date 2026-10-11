-- See 001: nothing may be left held by the role, or dropping it fails.
ALTER DEFAULT PRIVILEGES IN SCHEMA commercial_reservation REVOKE SELECT, INSERT, UPDATE ON TABLES FROM commercial_reservation_writer;
REVOKE SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA commercial_reservation FROM commercial_reservation_writer;
REVOKE USAGE ON SCHEMA commercial_reservation FROM commercial_reservation_writer;
