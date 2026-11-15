-- HU-COM-011 (-db) plan D-02, DP-D11-1 (PROPOSED default): a follow-up is a fact appended after a contact with the customer, never edited or deleted.
-- The note is required and non-blank (portal AC-PP.7); the dictionary conditional customerResponse is not stored. No DEFAULT: the service states every value.
-- The key to the reservation restricts. UPDATE is withdrawn in 03_dcl/01_grants/010; DELETE was never granted.
CREATE TABLE commercial_reservation.payment_followup (
    payment_followup_id uuid NOT NULL,
    tenant_id uuid CONSTRAINT chk_payment_followup_tenant_required NOT NULL,
    reservation_id uuid CONSTRAINT chk_payment_followup_reservation_required NOT NULL,
    contacted_by uuid CONSTRAINT chk_payment_followup_contacted_by_required NOT NULL,
    contacted_at timestamptz CONSTRAINT chk_payment_followup_contacted_at_required NOT NULL,
    note text CONSTRAINT chk_payment_followup_note_required NOT NULL,
    CONSTRAINT pk_payment_followup PRIMARY KEY (payment_followup_id),
    CONSTRAINT fk_payment_followup_reservation FOREIGN KEY (reservation_id)
        REFERENCES commercial_reservation.reservation (reservation_id) ON DELETE RESTRICT,
    CONSTRAINT chk_payment_followup_note CHECK (btrim(note) <> '')
);
