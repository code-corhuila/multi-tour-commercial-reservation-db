ALTER TABLE commercial_reservation.financial_decision
    DROP CONSTRAINT chk_financial_decision_resumed_due,
    DROP COLUMN resumed_due_at;
