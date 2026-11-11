-- HU-COM-017 (-db) plan D-05, AC-D17.9 (G-B of HU-COM-016): the decision of kind CREDIT_BALANCE_REFUND_REQUEST already carries credit_balance_id, with no key until the
-- credit table existed. The key is added now and restricts. No earlier story could insert a request row, so every existing value of the column is null.
ALTER TABLE commercial_reservation.financial_decision
    ADD CONSTRAINT fk_financial_decision_credit_balance FOREIGN KEY (credit_balance_id)
        REFERENCES commercial_reservation.credit_balance (credit_balance_id) ON DELETE RESTRICT;
