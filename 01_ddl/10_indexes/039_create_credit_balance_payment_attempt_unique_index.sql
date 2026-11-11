-- HU-COM-017 (-db) plan D-02, AC-D17.4 (AC4 of the story): one credit per validated payment attempt, so the excess of a payment is never recorded twice.
-- Partial on the attempt column. The table is new and empty: no CONCURRENTLY.
CREATE UNIQUE INDEX uq_credit_balance_payment_attempt ON commercial_reservation.credit_balance (source_payment_attempt_id)
    WHERE source_payment_attempt_id IS NOT NULL;
