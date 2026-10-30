-- HU-COM-007 (-db) plan D-06, AC-D7.8 (PROPOSED): what was fixed at creation stays fixed. The default privileges of 001/002 gave the
-- writer UPDATE on the new table; it is withdrawn here, after the table exists (the precedent is 006 for the additional discount).
-- The application user inherits the writer, so it loses it too. INSERT and SELECT stay; DELETE was never granted. Rollback grants it back.
REVOKE UPDATE ON commercial_reservation.reservation_fixed_discount FROM commercial_reservation_writer;
