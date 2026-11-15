-- HU-COM-009 (-db) plan D-10, AC-D9.5 (PROPOSED): the proof may show a bank account or a name, so it is downloaded only through the API (ADR-005 E6).
-- The default privileges gave the reader SELECT and the writer UPDATE on the new table; both are withdrawn after it exists (precedent: 005 and 006).
-- The writer keeps SELECT and INSERT; a proof is never modified; DELETE was never granted. The application user inherits the writer.
REVOKE SELECT ON commercial_reservation.payment_proof_file FROM commercial_reservation_reader;
REVOKE UPDATE ON commercial_reservation.payment_proof_file FROM commercial_reservation_writer;
