-- HU-COM-001 (-db), gap G-E closed by default (docs 06-data, 2026-11-02; RN-TRA-002, RN-10): the per-person transport rate of a
-- catalogued item, in whole cents. Optional: NULL means "not parametrized", so no DEFAULT and no backfill, and an existing row
-- stays as it is. A zero rate is allowed (transport at no charge); only a negative one is refused.
-- A tenant-level default rate stays NO DEFINIDO (06-data ND-07) and is not built here.
ALTER TABLE commercial_reservation.catalog_service
    ADD COLUMN transport_rate_per_person_cents bigint,
    ADD CONSTRAINT chk_catalog_service_transport_rate_per_person_cents
        CHECK (transport_rate_per_person_cents IS NULL OR transport_rate_per_person_cents >= 0);
