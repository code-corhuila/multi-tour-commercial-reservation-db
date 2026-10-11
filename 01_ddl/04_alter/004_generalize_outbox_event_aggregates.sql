-- PROPUESTO (HU-COM-002 D-07): D-07 assumed HU-COM-001's outbox was already generic.
-- The observed schema accepts catalog events only. Extend that same table, without
-- changing any applied SQL or losing existing catalog events (docs issue #168).
ALTER TABLE commercial_reservation.outbox_event
    ADD COLUMN association_id uuid,
    ALTER COLUMN service_id DROP NOT NULL,
    ALTER COLUMN previous_catalog_status DROP NOT NULL,
    DROP CONSTRAINT chk_outbox_event_event_type,
    DROP CONSTRAINT chk_outbox_event_condition_changed,
    DROP CONSTRAINT chk_outbox_event_type_matches_new_condition,
    ADD CONSTRAINT chk_outbox_event_event_type CHECK (event_type IN (
        'CatalogServiceInactivated', 'CatalogServiceReactivated',
        'EstablishmentAssociationPublished', 'EstablishmentAssociationInactivated',
        'EstablishmentAssociationReactivated')),
    ADD CONSTRAINT chk_outbox_event_condition_changed CHECK (
        previous_catalog_status IS NULL OR previous_catalog_status <> new_catalog_status),
    ADD CONSTRAINT chk_outbox_event_type_matches_new_condition CHECK (
        (event_type = 'EstablishmentAssociationPublished'
            AND previous_catalog_status IS NULL AND new_catalog_status = 'ACTIVE')
        OR (event_type IN ('CatalogServiceInactivated', 'EstablishmentAssociationInactivated')
            AND new_catalog_status = 'INACTIVE')
        OR (event_type IN ('CatalogServiceReactivated', 'EstablishmentAssociationReactivated')
            AND new_catalog_status = 'ACTIVE')),
    ADD CONSTRAINT chk_outbox_event_exactly_one_aggregate CHECK (
        ((service_id IS NOT NULL) <> (association_id IS NOT NULL))
        AND ((event_type IN ('CatalogServiceInactivated', 'CatalogServiceReactivated')
                AND service_id IS NOT NULL AND previous_catalog_status IS NOT NULL)
            OR (event_type IN ('EstablishmentAssociationPublished',
                'EstablishmentAssociationInactivated', 'EstablishmentAssociationReactivated')
                AND association_id IS NOT NULL))),
    ADD CONSTRAINT fk_outbox_event_association FOREIGN KEY (association_id)
        REFERENCES commercial_reservation.associated_establishment (association_id)
        ON DELETE RESTRICT;
