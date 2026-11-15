-- HU-COM-003 (-db) closing decisions of 2026-10-28 (PROPOSED): the api and the OpenAPI contract speak
-- codes and require audit moments, and discount_rule still held the Spanish words and no moments.
-- Never editing applied 007. The table holds no production data; rows that exist are converted anyway.
-- (a) calculation_base: 'Valor original' -> ORIGINAL_VALUE, 'Subtotal posterior al descuento anterior' -> PREVIOUS_SUBTOTAL.
-- (b) discount_type: 'Porcentual' -> PERCENTAGE, 'Valor fijo' -> FIXED_AMOUNT. The column stays because 06-data names it;
--     the api derives it from which value is set, and chk_discount_rule_value keeps "exactly one value" coherent with it.
-- (c) created_at and updated_at, timestamptz NOT NULL, no DEFAULT like catalog_service: the service states the moment.
--     The temporary default only fills rows that already exist and is dropped right after, as in 008.
ALTER TABLE commercial_reservation.discount_rule
    DROP CONSTRAINT chk_discount_rule_value,
    DROP CONSTRAINT chk_discount_rule_type,
    DROP CONSTRAINT chk_discount_rule_calculation_base;
UPDATE commercial_reservation.discount_rule SET
    calculation_base = CASE calculation_base
        WHEN 'Valor original' THEN 'ORIGINAL_VALUE'
        WHEN 'Subtotal posterior al descuento anterior' THEN 'PREVIOUS_SUBTOTAL' END,
    discount_type = CASE discount_type
        WHEN 'Porcentual' THEN 'PERCENTAGE'
        WHEN 'Valor fijo' THEN 'FIXED_AMOUNT' END;
ALTER TABLE commercial_reservation.discount_rule
    ADD CONSTRAINT chk_discount_rule_calculation_base CHECK (
        calculation_base IN ('ORIGINAL_VALUE', 'PREVIOUS_SUBTOTAL')),
    ADD CONSTRAINT chk_discount_rule_type CHECK (discount_type IN ('PERCENTAGE', 'FIXED_AMOUNT')),
    ADD CONSTRAINT chk_discount_rule_value CHECK (
        (discount_type = 'PERCENTAGE' AND discount_percentage_bp IS NOT NULL AND discount_amount_cents IS NULL)
        OR (discount_type = 'FIXED_AMOUNT' AND discount_amount_cents IS NOT NULL AND discount_percentage_bp IS NULL)),
    ADD COLUMN created_at timestamptz CONSTRAINT chk_discount_rule_created_at_required NOT NULL DEFAULT now(),
    ADD COLUMN updated_at timestamptz CONSTRAINT chk_discount_rule_updated_at_required NOT NULL DEFAULT now();
ALTER TABLE commercial_reservation.discount_rule
    ALTER COLUMN created_at DROP DEFAULT,
    ALTER COLUMN updated_at DROP DEFAULT;
