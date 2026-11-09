-- HU-COM-018 (-db) plan D-04, AC-D18.11: the record of a rescheduling is a fact, never edited. The default privileges of 001/002 gave the writer UPDATE on the new table; it is withdrawn here,
-- after the table exists. The application user inherits the writer. DELETE was never granted. Rollback grants UPDATE back.
REVOKE UPDATE ON commercial_reservation.rescheduling_record FROM commercial_reservation_writer;
