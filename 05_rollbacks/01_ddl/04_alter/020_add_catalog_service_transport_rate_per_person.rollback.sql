ALTER TABLE commercial_reservation.catalog_service
    DROP CONSTRAINT chk_catalog_service_transport_rate_per_person_cents,
    DROP COLUMN transport_rate_per_person_cents;
