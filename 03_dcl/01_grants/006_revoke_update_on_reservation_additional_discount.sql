-- HU-COM-004 (-db) docs issue #171, AC-D4.9, plan D-07 (PROPOSED, immutable by decision 2026-10-28): a stored additional
-- discount is never edited. The default privileges of 001/002 gave the writer UPDATE on it; it is withdrawn here, after the
-- table exists. The application user inherits the writer, so it loses it too. DELETE was never granted. Rollback grants it back.
REVOKE UPDATE ON commercial_reservation.reservation_additional_discount FROM commercial_reservation_writer;
