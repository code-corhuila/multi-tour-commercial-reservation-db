-- HU-COM-017 (-db) plan D-03, AC-D17.6: a recorded credit and an application are facts, never edited. The default privileges of 001/002 gave the writer UPDATE on both
-- new tables; it is withdrawn here, after they exist. The application user inherits the writer. DELETE was never granted. Rollback grants UPDATE back.
REVOKE UPDATE ON commercial_reservation.credit_balance, commercial_reservation.credit_balance_application FROM commercial_reservation_writer;
