-- Refuse a downgrade with discount events: the application owns their retention.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM commercial_reservation.outbox_event
               WHERE discount_rule_id IS NOT NULL OR event_type = 'DiscountRuleChanged') THEN
        RAISE EXCEPTION 'Cannot revert outbox generalization while discount rule events remain';
    END IF;
END $$;
ALTER TABLE commercial_reservation.outbox_event
    DROP CONSTRAINT fk_outbox_event_discount_rule,
    DROP CONSTRAINT chk_outbox_event_discount_rule_state,
    DROP CONSTRAINT chk_outbox_event_exactly_one_aggregate,
    DROP CONSTRAINT chk_outbox_event_event_type,
    DROP CONSTRAINT chk_outbox_event_condition_changed,
    DROP CONSTRAINT chk_outbox_event_type_matches_new_condition,
    DROP COLUMN discount_rule_id,
    DROP COLUMN previous_discount_rule_state,
    DROP COLUMN new_discount_rule_state,
    ALTER COLUMN new_catalog_status SET NOT NULL,
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
                AND association_id IS NOT NULL)));
