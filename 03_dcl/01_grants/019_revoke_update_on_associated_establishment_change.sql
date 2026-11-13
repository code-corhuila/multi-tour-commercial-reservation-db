-- HU-COM-002 (-db) spec 2026-11-12 (AC-D2.14): the change log is a trace, never edited. The default privileges of 001/002 gave the writer UPDATE on the new table; it is withdrawn here, after the table exists.
-- The application user inherits the writer. DELETE was never granted. Rollback grants UPDATE back.
REVOKE UPDATE ON commercial_reservation.associated_establishment_change FROM commercial_reservation_writer;
