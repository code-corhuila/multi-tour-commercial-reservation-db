-- Refuse a downgrade with the new events: the application owns their retention.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM commercial_reservation.outbox_event
               WHERE reservation_id IS NOT NULL OR customer_id IS NOT NULL
                  OR event_type IN ('ReservationModified', 'CustomerRegistered', 'SensitiveDataAccessed')) THEN
        RAISE EXCEPTION 'Cannot revert outbox widening while ReservationModified, CustomerRegistered or SensitiveDataAccessed events remain';
    END IF;
END $$;
ALTER TABLE commercial_reservation.outbox_event
    DROP CONSTRAINT fk_outbox_event_customer,
    DROP CONSTRAINT chk_outbox_event_payload_no_sensitive_keys,
    DROP CONSTRAINT chk_outbox_event_payload,
    DROP CONSTRAINT chk_outbox_event_actor_required,
    DROP CONSTRAINT chk_outbox_event_exactly_one_aggregate,
    DROP CONSTRAINT chk_outbox_event_type_matches_new_condition,
    DROP CONSTRAINT chk_outbox_event_event_type,
    DROP COLUMN payload,
    DROP COLUMN customer_id,
    DROP COLUMN reservation_id,
    ALTER COLUMN actor_id SET NOT NULL,
    ADD CONSTRAINT chk_outbox_event_event_type CHECK (event_type IN (
        'CatalogServiceInactivated', 'CatalogServiceReactivated',
        'EstablishmentAssociationPublished', 'EstablishmentAssociationInactivated',
        'EstablishmentAssociationReactivated', 'DiscountRuleChanged')),
    ADD CONSTRAINT chk_outbox_event_type_matches_new_condition CHECK (
        event_type = 'DiscountRuleChanged' OR (new_catalog_status IS NOT NULL AND (
        (event_type = 'EstablishmentAssociationPublished'
            AND previous_catalog_status IS NULL AND new_catalog_status = 'ACTIVE')
        OR (event_type IN ('CatalogServiceInactivated', 'EstablishmentAssociationInactivated')
            AND new_catalog_status = 'INACTIVE')
        OR (event_type IN ('CatalogServiceReactivated', 'EstablishmentAssociationReactivated')
            AND new_catalog_status = 'ACTIVE')))),
    ADD CONSTRAINT chk_outbox_event_exactly_one_aggregate CHECK (
        num_nonnulls(service_id, association_id, discount_rule_id) = 1 AND (
        (event_type IN ('CatalogServiceInactivated', 'CatalogServiceReactivated')
            AND service_id IS NOT NULL AND previous_catalog_status IS NOT NULL)
        OR (event_type IN ('EstablishmentAssociationPublished',
            'EstablishmentAssociationInactivated', 'EstablishmentAssociationReactivated')
            AND association_id IS NOT NULL)
        OR (event_type = 'DiscountRuleChanged' AND discount_rule_id IS NOT NULL
            AND previous_catalog_status IS NULL AND new_catalog_status IS NULL)));
