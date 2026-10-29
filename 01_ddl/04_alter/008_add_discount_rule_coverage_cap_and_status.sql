-- HU-COM-003 defaults of 2026-10-28 (PROPOSED, pending the Project Lead), never editing applied 007:
-- DP-01 covers_all_services: true = every service of the tenant, false = the rows of discount_rule_service.
-- DP-05 cap_cents: optional cap per rule, minor units, greater than 0.
-- DP-07 status: ACTIVE or INACTIVE (reactivation is an -api decision, not an engine rule).
-- Dates already are calendar dates with CHECK (starts_on <= ends_on) since 007 (DP-02); priority stays without UNIQUE (DP-08).
-- Accumulation (DP-04) and conditions of use (DP-06) are left open: no column.
-- The table has no production data. A rule existing before this change could only mean "every service",
-- so it is backfilled true; the default is dropped right after so that new rows must say it.
ALTER TABLE commercial_reservation.discount_rule
    ADD COLUMN covers_all_services boolean CONSTRAINT chk_discount_rule_coverage_required NOT NULL DEFAULT true,
    ADD COLUMN cap_cents bigint,
    ADD CONSTRAINT chk_discount_rule_cap CHECK (cap_cents > 0),
    ADD CONSTRAINT chk_discount_rule_status CHECK (status IN ('ACTIVE', 'INACTIVE'));
ALTER TABLE commercial_reservation.discount_rule ALTER COLUMN covers_all_services DROP DEFAULT;
