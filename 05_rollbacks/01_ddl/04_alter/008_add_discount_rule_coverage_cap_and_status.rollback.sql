ALTER TABLE commercial_reservation.discount_rule
    DROP CONSTRAINT chk_discount_rule_status,
    DROP CONSTRAINT chk_discount_rule_cap,
    DROP COLUMN cap_cents,
    DROP COLUMN covers_all_services;
