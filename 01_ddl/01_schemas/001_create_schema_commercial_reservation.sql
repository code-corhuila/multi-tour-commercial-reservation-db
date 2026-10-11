-- The schema of this domain. Nothing of the domain lives in public (Annex A rule 9, Annex J.4).
-- The instance, its volume, its extensions and its users belong to multi-tour-infra-postgres.
CREATE SCHEMA commercial_reservation;

COMMENT ON SCHEMA commercial_reservation IS 'Commercial and Reservations macrodomain (ADR-004 D1): catalog, discounts, customers and reservations.';
