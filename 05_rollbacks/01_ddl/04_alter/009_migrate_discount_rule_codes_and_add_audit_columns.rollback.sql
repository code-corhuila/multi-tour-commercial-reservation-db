-- Back to the Spanish words and without the moments. Rows are converted back, so none is lost.
ALTER TABLE commercial_reservation.discount_rule
    DROP CONSTRAINT chk_discount_rule_value,
    DROP CONSTRAINT chk_discount_rule_type,
    DROP CONSTRAINT chk_discount_rule_calculation_base,
    DROP COLUMN updated_at,
    DROP COLUMN created_at;
UPDATE commercial_reservation.discount_rule SET
    calculation_base = CASE calculation_base
        WHEN 'ORIGINAL_VALUE' THEN 'Valor original'
        WHEN 'PREVIOUS_SUBTOTAL' THEN 'Subtotal posterior al descuento anterior' END,
    discount_type = CASE discount_type
        WHEN 'PERCENTAGE' THEN 'Porcentual'
        WHEN 'FIXED_AMOUNT' THEN 'Valor fijo' END;
ALTER TABLE commercial_reservation.discount_rule
    ADD CONSTRAINT chk_discount_rule_calculation_base CHECK (
        calculation_base IN ('Valor original', 'Subtotal posterior al descuento anterior')),
    ADD CONSTRAINT chk_discount_rule_type CHECK (discount_type IN ('Porcentual', 'Valor fijo')),
    ADD CONSTRAINT chk_discount_rule_value CHECK (
        (discount_type = 'Porcentual' AND discount_percentage_bp IS NOT NULL AND discount_amount_cents IS NULL)
        OR (discount_type = 'Valor fijo' AND discount_amount_cents IS NOT NULL AND discount_percentage_bp IS NULL));
