-- HU-COM-003 (-db), decision of 2026-11-03 (DP-04, PROPOSED): discount_rule.stackable, the "Acumulable" flag of the mockup.
-- false: once the rule applies, no rule of lower priority applies after it. true: the next rule may apply.
-- NOT NULL DEFAULT true: the rows that exist, and an insert that omits the column, keep today's behavior (no rule is cut).
-- The logical name in 06-data is accumulationPolicy; here its values are read as a boolean (adding values later is additive).
ALTER TABLE commercial_reservation.discount_rule
    ADD COLUMN stackable boolean CONSTRAINT chk_discount_rule_stackable_required NOT NULL DEFAULT true;
