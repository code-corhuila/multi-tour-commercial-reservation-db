-- HU-COM-003 DP-03 (Fernanda, 2026-10-11): names and integer units from 06-data.
-- PROPUESTO (HU-COM-003): CHECK/NOT NULL names; labels follow data-dictionary.md.
-- Status catalogue, coverage, accumulation, caps, conditions and priority ties stay open.
-- Default writer privileges supply SELECT/INSERT/UPDATE, never DELETE (Anexo J).
CREATE TABLE commercial_reservation.discount_rule (
    discount_rule_id uuid NOT NULL,
    tenant_id uuid CONSTRAINT chk_discount_rule_tenant_required NOT NULL,
    name text NOT NULL,
    starts_on date CONSTRAINT chk_discount_rule_starts_on_required NOT NULL,
    ends_on date CONSTRAINT chk_discount_rule_ends_on_required NOT NULL,
    priority integer NOT NULL,
    calculation_base text NOT NULL,
    discount_type text NOT NULL,
    discount_percentage_bp integer,
    discount_amount_cents bigint,
    status text NOT NULL,
    CONSTRAINT pk_discount_rule PRIMARY KEY (discount_rule_id),
    CONSTRAINT chk_discount_rule_validity CHECK (starts_on <= ends_on),
    CONSTRAINT chk_discount_rule_priority CHECK (priority > 0),
    CONSTRAINT chk_discount_rule_calculation_base CHECK (
        calculation_base IN ('Valor original', 'Subtotal posterior al descuento anterior')),
    CONSTRAINT chk_discount_rule_type CHECK (discount_type IN ('Porcentual', 'Valor fijo')),
    CONSTRAINT chk_discount_rule_percentage CHECK (discount_percentage_bp BETWEEN 1 AND 10000),
    CONSTRAINT chk_discount_rule_amount CHECK (discount_amount_cents > 0),
    CONSTRAINT chk_discount_rule_value CHECK (
        (discount_type = 'Porcentual' AND discount_percentage_bp IS NOT NULL AND discount_amount_cents IS NULL)
        OR (discount_type = 'Valor fijo' AND discount_amount_cents IS NOT NULL AND discount_percentage_bp IS NULL))
);
