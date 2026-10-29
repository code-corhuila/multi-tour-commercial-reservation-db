-- HU-COM-005 (-db), defaults of 2026-10-28, never editing applied 009.
--  DP-D5-2: the companion document is kept plain and normalized (trim, upper case) as the dictionary
--           lists it, so RN-RES-005 works in the engine; the check refuses any other spelling.
--  DP-D5-1/5: birth_date_or_age is text holding the versioned envelope the application encrypts.
--  DP-D5-9: no contact column. The foreign key to the reservation waits for HU-COM-007 (plan D-08).
ALTER TABLE commercial_reservation.reservation_companion
    ADD COLUMN document_number text CONSTRAINT chk_reservation_companion_document_number_required NOT NULL,
    ADD COLUMN birth_date_or_age text CONSTRAINT chk_reservation_companion_birth_date_or_age_required NOT NULL,
    ADD CONSTRAINT chk_reservation_companion_document_number_normalized CHECK (
        document_number <> '' AND document_number = upper(btrim(document_number))),
    ADD CONSTRAINT uq_reservation_companion_reservation_document UNIQUE (reservation_id, document_number);
