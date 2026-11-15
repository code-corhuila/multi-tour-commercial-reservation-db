-- HU-COM-007 (-db) plan D-06 (PROPOSED, debt DD-3, closes G-CTX but the accumulation policy): the commercial context fixed at creation.
-- One line for EVERY general rule in force when the reservation was created, applied or not, so a zero amount is kept (RN-RES-003).
-- The name, the type and the value of the rule are copies: a renamed, edited or inactivated rule never rewrites the sale.
-- The codes are those of discount_rule after 04_alter/009 and of the -api enum DiscountBase, so nothing is mapped. The accumulation policy
-- has no column (ND-06, open). No UPDATE for the writer: 03_dcl/01_grants/008. Nothing has a DEFAULT; DELETE is never granted.
CREATE TABLE commercial_reservation.reservation_fixed_discount (
    reservation_fixed_discount_id uuid NOT NULL,
    tenant_id uuid CONSTRAINT chk_reservation_fixed_discount_tenant_required NOT NULL,
    reservation_id uuid CONSTRAINT chk_reservation_fixed_discount_reservation_required NOT NULL,
    line_order integer CONSTRAINT chk_reservation_fixed_discount_order_required NOT NULL,
    discount_rule_id uuid CONSTRAINT chk_reservation_fixed_discount_rule_required NOT NULL,
    rule_name text CONSTRAINT chk_reservation_fixed_discount_name_required NOT NULL,
    discount_type text CONSTRAINT chk_reservation_fixed_discount_type_required NOT NULL,
    discount_percentage_bp integer,
    discount_amount_cents bigint,
    calculation_base text CONSTRAINT chk_reservation_fixed_discount_base_kind_required NOT NULL,
    base_cents bigint CONSTRAINT chk_reservation_fixed_discount_base_required NOT NULL,
    amount_cents bigint CONSTRAINT chk_reservation_fixed_discount_amount_required NOT NULL,
    subtotal_cents bigint CONSTRAINT chk_reservation_fixed_discount_subtotal_required NOT NULL,
    cap_cents bigint,
    CONSTRAINT pk_reservation_fixed_discount PRIMARY KEY (reservation_fixed_discount_id),
    CONSTRAINT fk_reservation_fixed_discount_reservation FOREIGN KEY (reservation_id)
        REFERENCES commercial_reservation.reservation (reservation_id) ON DELETE RESTRICT,
    CONSTRAINT fk_reservation_fixed_discount_rule FOREIGN KEY (discount_rule_id)
        REFERENCES commercial_reservation.discount_rule (discount_rule_id) ON DELETE RESTRICT,
    CONSTRAINT uq_reservation_fixed_discount_reservation_order UNIQUE (reservation_id, line_order),
    CONSTRAINT chk_reservation_fixed_discount_order CHECK (line_order >= 1),
    CONSTRAINT chk_reservation_fixed_discount_name CHECK (btrim(rule_name) <> ''),
    CONSTRAINT chk_reservation_fixed_discount_type CHECK (discount_type IN ('PERCENTAGE', 'FIXED_AMOUNT')),
    CONSTRAINT chk_reservation_fixed_discount_percentage CHECK (discount_percentage_bp BETWEEN 1 AND 10000),
    CONSTRAINT chk_reservation_fixed_discount_value CHECK (
        (discount_type = 'PERCENTAGE' AND discount_percentage_bp IS NOT NULL AND discount_amount_cents IS NULL)
        OR (discount_type = 'FIXED_AMOUNT' AND discount_amount_cents IS NOT NULL AND discount_percentage_bp IS NULL)),
    CONSTRAINT chk_reservation_fixed_discount_fixed_amount CHECK (discount_amount_cents > 0),
    CONSTRAINT chk_reservation_fixed_discount_base_kind CHECK (calculation_base IN ('ORIGINAL_VALUE', 'PREVIOUS_SUBTOTAL')),
    CONSTRAINT chk_reservation_fixed_discount_base CHECK (base_cents >= 0),
    CONSTRAINT chk_reservation_fixed_discount_amount CHECK (amount_cents >= 0),
    CONSTRAINT chk_reservation_fixed_discount_subtotal CHECK (subtotal_cents >= 0),
    CONSTRAINT chk_reservation_fixed_discount_cap CHECK (cap_cents > 0)
);
