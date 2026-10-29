-- HU-COM-005 (-db), decision of 2026-10-28 (docs: PDR RN-CLI-001, data-dictionary consents, modeling-conventions
-- 360-368), never editing applied 006: the customer's acceptance of the terms is stored on customer itself,
-- NOT in customer_sensitive_data, which HU-COM-019 purges (the acceptance is evidence that must outlive the purge).
-- terms_accepted must be true: a lead who did not accept is not registered (RN-CLI-001). terms_accepted_at is the moment.
-- Declared debt, not built: no terms version, and no service_id on customer.
-- The table has no production data, but a customer may already exist on a developer's database. Such a row
-- was registered with the terms accepted at its creation, so it is backfilled true and now(); the defaults are
-- dropped right after so that every new row must state both, exactly as 008 and 009 did.
ALTER TABLE commercial_reservation.customer
    ADD COLUMN terms_accepted boolean CONSTRAINT chk_customer_terms_accepted_required NOT NULL DEFAULT true,
    ADD COLUMN terms_accepted_at timestamptz CONSTRAINT chk_customer_terms_accepted_at_required NOT NULL DEFAULT now(),
    ADD CONSTRAINT chk_customer_terms_accepted_true CHECK (terms_accepted = true);
ALTER TABLE commercial_reservation.customer
    ALTER COLUMN terms_accepted DROP DEFAULT,
    ALTER COLUMN terms_accepted_at DROP DEFAULT;
