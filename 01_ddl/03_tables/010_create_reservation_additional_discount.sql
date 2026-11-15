-- HU-COM-004 T-02, plan D-02 and D-03 (PROPUESTO): the additional discount of one reservation.
-- Its own table (DP-04-6 proposed); the reason is kept as text (DP-04-2 option A, as the portal port).
-- No cap column (DP-04-1 open), no foreign key (the reservations table of HU-COM-007 does not exist:
-- the composite (tenant_id, reservation_id) key is a later changeset, G-A) and no event (DP-04-5).
-- applied_by is plain data: users belong to identity-audit (ADR-005 E7).
-- Default writer privileges give SELECT/INSERT/UPDATE, never DELETE (D-08); the UPDATE revoke waits for DP-04-4.
CREATE TABLE commercial_reservation.reservation_additional_discount (
    additional_discount_id uuid NOT NULL,
    tenant_id uuid CONSTRAINT chk_reservation_additional_discount_tenant_required NOT NULL,
    reservation_id uuid CONSTRAINT chk_reservation_additional_discount_reservation_required NOT NULL,
    discount_percentage_bp integer NOT NULL,
    reason text CONSTRAINT chk_reservation_additional_discount_reason_required NOT NULL,
    applied_by uuid CONSTRAINT chk_reservation_additional_discount_author_required NOT NULL,
    applied_at timestamptz CONSTRAINT chk_reservation_additional_discount_moment_required NOT NULL,
    previous_value_cents bigint NOT NULL,
    amount_cents bigint NOT NULL,
    CONSTRAINT pk_reservation_additional_discount PRIMARY KEY (additional_discount_id),
    CONSTRAINT uq_reservation_additional_discount_reservation UNIQUE (reservation_id),
    CONSTRAINT chk_reservation_additional_discount_percentage CHECK (discount_percentage_bp BETWEEN 1 AND 10000),
    CONSTRAINT chk_reservation_additional_discount_amount CHECK (amount_cents > 0),
    CONSTRAINT chk_reservation_additional_discount_previous_value CHECK (previous_value_cents > 0),
    CONSTRAINT chk_reservation_additional_discount_amount_within_previous CHECK (amount_cents <= previous_value_cents),
    CONSTRAINT chk_reservation_additional_discount_reason_not_blank CHECK (btrim(reason) <> '')
);
