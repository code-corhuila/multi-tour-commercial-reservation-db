-- HU-COM-019 (-db) plan D-03, AC-D19.5: a deletion record is a fact, never edited. The default privileges of 001/002 gave the writer UPDATE on the new table; it is withdrawn here, after the
-- table exists. DELETE was never granted. Rollback grants UPDATE back.
REVOKE UPDATE ON commercial_reservation.sensitive_data_deletion FROM commercial_reservation_writer;
