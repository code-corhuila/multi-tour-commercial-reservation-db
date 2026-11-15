-- HU-COM-010 (-db) docs issue #176, plan D-02 and D-03 (PROPOSED, debt DD-1): the review of a payment proof, as columns of the attempt of HU-COM-009 and not a
-- table of its own. decided_by, decided_at and decision_reason are the physical names of validatedOrRejectedBy, validatedOrRejectedAt and
-- validationOrRejectionReason (models.md, CONFIRMADO); the four amounts are PROPUESTO. treatment_amount_cents holds the value of a proof approved on a
-- cancelled reservation, which is neither applied nor excess. All nullable: the columns stay empty while the proof is IN_VALIDATION and always for cash.
-- Every constraint is keyed on the status values, so cash rows (no status) are left alone. A null inside a CHECK passes, so each rule is wrapped in
-- COALESCE(..., false): a missing amount is a refusal, not a pass. The reason is plain text with a non-blank check (DP-D10-5, OPEN).
ALTER TABLE commercial_reservation.payment_attempt
    ADD COLUMN decided_by uuid,
    ADD COLUMN decided_at timestamptz,
    ADD COLUMN decision_reason text,
    ADD COLUMN verified_amount_cents bigint,
    ADD COLUMN applied_amount_cents bigint,
    ADD COLUMN excess_amount_cents bigint,
    ADD COLUMN treatment_amount_cents bigint,
    ADD CONSTRAINT chk_payment_attempt_approved_complete CHECK (
        validation_status IS DISTINCT FROM 'APPROVED'
        OR COALESCE(
            verified_amount_cents > 0
            AND applied_amount_cents BETWEEN 0 AND verified_amount_cents
            AND excess_amount_cents >= 0
            AND treatment_amount_cents >= 0
            AND applied_amount_cents + excess_amount_cents + treatment_amount_cents = verified_amount_cents
            AND NOT (excess_amount_cents > 0 AND treatment_amount_cents > 0)
            AND decided_by IS NOT NULL
            AND decided_at IS NOT NULL, false)),
    ADD CONSTRAINT chk_payment_attempt_rejected_complete CHECK (
        validation_status IS DISTINCT FROM 'REJECTED'
        OR COALESCE(
            decided_by IS NOT NULL
            AND decided_at IS NOT NULL
            AND btrim(decision_reason) <> ''
            AND num_nonnulls(verified_amount_cents, applied_amount_cents, excess_amount_cents, treatment_amount_cents) = 0, false)),
    ADD CONSTRAINT chk_payment_attempt_undecided_empty CHECK (
        COALESCE(validation_status IN ('APPROVED', 'REJECTED'), false)
        OR num_nonnulls(decided_by, decided_at, decision_reason, verified_amount_cents, applied_amount_cents, excess_amount_cents, treatment_amount_cents) = 0),
    ADD CONSTRAINT chk_payment_attempt_difference_has_reason CHECK (
        validation_status IS DISTINCT FROM 'APPROVED'
        OR verified_amount_cents = received_amount_cents
        OR COALESCE(btrim(decision_reason) <> '', false));
