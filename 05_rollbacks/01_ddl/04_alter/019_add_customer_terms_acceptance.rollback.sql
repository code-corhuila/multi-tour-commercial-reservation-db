ALTER TABLE commercial_reservation.customer
    DROP CONSTRAINT chk_customer_terms_accepted_true,
    DROP COLUMN terms_accepted_at,
    DROP COLUMN terms_accepted;
