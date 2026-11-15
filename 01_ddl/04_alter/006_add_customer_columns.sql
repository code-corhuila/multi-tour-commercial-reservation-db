-- HU-COM-005 (-db), defaults of 2026-10-28, never editing applied 008. The tables are new and empty,
-- so the NOT NULL columns need no backfill.
--  DP-D5-1: document_number and birth_date_or_age are text holding a versioned envelope the application
--           encrypts before saving; contact_info is jsonb with the same envelope. No key in the database.
--  DP-D5-5: one column carries a birth date or an age.
--  DP-D5-6: status has no CHECK and no catalogue; the application writes the placeholder ACTIVE.
--  DP-D5-4: account_id is nullable and has no foreign key (cross-domain, Annex J.3.4).
-- Not built because their decision is open: e-mail and keyed hashes (DP-D5-2, 3), terms and consents
-- (DP-D5-7, DP-D5-10), retention date (DP-D5-10).
ALTER TABLE commercial_reservation.customer
    ADD COLUMN document_number text CONSTRAINT chk_customer_document_number_required NOT NULL,
    ADD COLUMN birth_date_or_age text CONSTRAINT chk_customer_birth_date_or_age_required NOT NULL,
    ADD COLUMN contact_info jsonb CONSTRAINT chk_customer_contact_info_required NOT NULL,
    ADD COLUMN status text CONSTRAINT chk_customer_status_required NOT NULL,
    ADD COLUMN account_id uuid;
