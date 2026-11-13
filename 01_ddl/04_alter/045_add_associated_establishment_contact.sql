-- HU-COM-002 (-db) spec 2026-11-12 (PROPOSED, AC-D2.11): the contact of an association, three optional columns. They are nullable on purpose: the rows that existed before have none and RN-07 forbids deleting
-- them, so "one of email or phone" is the service's rule, not the engine's. The engine only bounds the length and refuses an empty text (the service sends null for a field that was not typed).
ALTER TABLE commercial_reservation.associated_establishment
    ADD COLUMN contact_email text,
    ADD COLUMN contact_phone text,
    ADD COLUMN contact_address text,
    ADD CONSTRAINT chk_associated_establishment_contact_email_length CHECK (char_length(btrim(contact_email)) BETWEEN 1 AND 254 AND char_length(contact_email) <= 254),
    ADD CONSTRAINT chk_associated_establishment_contact_phone_length CHECK (char_length(btrim(contact_phone)) BETWEEN 1 AND 30 AND char_length(contact_phone) <= 30),
    ADD CONSTRAINT chk_associated_establishment_contact_address_length CHECK (char_length(btrim(contact_address)) BETWEEN 1 AND 255 AND char_length(contact_address) <= 255);
