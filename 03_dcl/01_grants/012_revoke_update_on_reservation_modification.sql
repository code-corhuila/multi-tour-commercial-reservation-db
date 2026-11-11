-- HU-COM-012 (-db) plan D-06, AC-D12.5: a stored change is never edited. The default privileges of 001/002 gave the writer UPDATE on it; it is withdrawn here,
-- after the table exists. The application user inherits the writer, so it loses it too. DELETE was never granted. Rollback grants it back.
REVOKE UPDATE ON commercial_reservation.reservation_modification FROM commercial_reservation_writer;
