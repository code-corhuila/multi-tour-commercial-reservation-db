-- PROPUESTO (HU-COM-002 D-07): restore the catalog-only outbox exactly.
-- Association events must first be drained by the application's retention process.
-- Refuse an unsafe downgrade rather than deleting events or fabricating catalog IDs.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM commercial_reservation.outbox_event
               WHERE association_id IS NOT NULL OR service_id IS NULL
                  OR previous_catalog_status IS NULL) THEN
        RAISE EXCEPTION 'Cannot revert outbox generalization while association events remain';
    END IF;
END $$;
ALTER TABLE commercial_reservation.outbox_event
    DROP CONSTRAINT fk_outbox_event_association,
    DROP CONSTRAINT chk_outbox_event_exactly_one_aggregate,
    DROP CONSTRAINT chk_outbox_event_event_type,
    DROP CONSTRAINT chk_outbox_event_condition_changed,
    DROP CONSTRAINT chk_outbox_event_type_matches_new_condition,
    DROP COLUMN association_id,
    ALTER COLUMN service_id SET NOT NULL,
    ALTER COLUMN previous_catalog_status SET NOT NULL,
    ADD CONSTRAINT chk_outbox_event_event_type CHECK (
        event_type IN ('CatalogServiceInactivated', 'CatalogServiceReactivated')),
    ADD CONSTRAINT chk_outbox_event_condition_changed CHECK (
        previous_catalog_status <> new_catalog_status),
    ADD CONSTRAINT chk_outbox_event_type_matches_new_condition CHECK (
        (event_type = 'CatalogServiceInactivated' AND new_catalog_status = 'INACTIVE')
        OR (event_type = 'CatalogServiceReactivated' AND new_catalog_status = 'ACTIVE'));
