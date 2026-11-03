-- HU-COM-011 (-db) plan D-02, AC-D11.3 (AC5 of the story): a stored follow-up is never edited. The default privileges of 001/002 gave the writer UPDATE on it;
-- it is withdrawn here, after the table exists. The application user inherits the writer, so it loses it too. DELETE was never granted. Rollback grants it back.
REVOKE UPDATE ON commercial_reservation.payment_followup FROM commercial_reservation_writer;
