-- HU-COM-020 (-db) AC-20.5, AC-20.7 (PROPOSED default): a financial decision frozen by the inactivation of its tenant resumes with the time it had left. recognized_at is immutable (the guard of 006),
-- so the shifted due instant is kept here: the 24 hours end at resumed_due_at once it is set, and at recognized_at plus 24 hours otherwise. Nullable, no DEFAULT, never before the recognition.
ALTER TABLE commercial_reservation.financial_decision
    ADD COLUMN resumed_due_at timestamptz,
    ADD CONSTRAINT chk_financial_decision_resumed_due CHECK (resumed_due_at IS NULL OR resumed_due_at > recognized_at);
