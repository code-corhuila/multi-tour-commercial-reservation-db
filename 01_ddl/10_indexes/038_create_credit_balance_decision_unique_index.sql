-- HU-COM-017 (-db) plan D-02, AC-D17.4 (RN-RES-006C, DP-D17-2): one credit per decision. Partial, so the credits born from an attempt (null decision) do not collide.
-- The table is new and empty: no CONCURRENTLY. The api reads the refusal as already recorded.
CREATE UNIQUE INDEX uq_credit_balance_decision ON commercial_reservation.credit_balance (source_financial_decision_id)
    WHERE source_financial_decision_id IS NOT NULL;
