-- Revoked in the opposite order, so the role can be dropped afterwards: a role that still holds a
-- privilege cannot be dropped.
ALTER DEFAULT PRIVILEGES IN SCHEMA commercial_reservation REVOKE SELECT ON TABLES FROM commercial_reservation_reader;
REVOKE SELECT ON ALL TABLES IN SCHEMA commercial_reservation FROM commercial_reservation_reader;
REVOKE USAGE ON SCHEMA commercial_reservation FROM commercial_reservation_reader;
