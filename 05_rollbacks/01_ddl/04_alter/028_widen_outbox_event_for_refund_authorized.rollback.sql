-- HU-COM-016 (-db): the five lists as 027 left them, without RefundAuthorized.
ALTER TABLE commercial_reservation.outbox_event
    DROP CONSTRAINT chk_outbox_event_payload_keys_refund_authorized,
    DROP CONSTRAINT chk_outbox_event_event_type,
    DROP CONSTRAINT chk_outbox_event_type_matches_new_condition,
    DROP CONSTRAINT chk_outbox_event_exactly_one_aggregate,
    DROP CONSTRAINT chk_outbox_event_payload,
    DROP CONSTRAINT chk_outbox_event_actor_required,
    ADD CONSTRAINT chk_outbox_event_event_type CHECK (event_type IN (
        'CatalogServiceInactivated', 'CatalogServiceReactivated',
        'EstablishmentAssociationPublished', 'EstablishmentAssociationInactivated',
        'EstablishmentAssociationReactivated', 'DiscountRuleChanged',
        'ReservationModified', 'CustomerRegistered', 'SensitiveDataAccessed',
        'ReservationCreated', 'PaymentEvidenceRegistered', 'CapacityAllocated',
        'PaymentValidated', 'PaymentRejected', 'ReservationConfirmed', 'CapacityReleased',
        'ReservationCancelled', 'ClientNotified')),
    ADD CONSTRAINT chk_outbox_event_type_matches_new_condition CHECK (
        event_type IN ('DiscountRuleChanged', 'ReservationModified', 'CustomerRegistered', 'SensitiveDataAccessed',
            'ReservationCreated', 'PaymentEvidenceRegistered', 'CapacityAllocated',
            'PaymentValidated', 'PaymentRejected', 'ReservationConfirmed', 'CapacityReleased', 'ReservationCancelled',
            'ClientNotified')
        OR (new_catalog_status IS NOT NULL AND (
        (event_type = 'EstablishmentAssociationPublished'
            AND previous_catalog_status IS NULL AND new_catalog_status = 'ACTIVE')
        OR (event_type IN ('CatalogServiceInactivated', 'EstablishmentAssociationInactivated')
            AND new_catalog_status = 'INACTIVE')
        OR (event_type IN ('CatalogServiceReactivated', 'EstablishmentAssociationReactivated')
            AND new_catalog_status = 'ACTIVE')))),
    ADD CONSTRAINT chk_outbox_event_exactly_one_aggregate CHECK (
        num_nonnulls(service_id, association_id, discount_rule_id, reservation_id, customer_id) = 1 AND (
        (event_type IN ('CatalogServiceInactivated', 'CatalogServiceReactivated')
            AND service_id IS NOT NULL AND previous_catalog_status IS NOT NULL)
        OR (event_type IN ('EstablishmentAssociationPublished',
            'EstablishmentAssociationInactivated', 'EstablishmentAssociationReactivated')
            AND association_id IS NOT NULL)
        OR (event_type = 'DiscountRuleChanged' AND discount_rule_id IS NOT NULL
            AND previous_catalog_status IS NULL AND new_catalog_status IS NULL)
        OR (event_type IN ('ReservationModified', 'ReservationCreated', 'PaymentEvidenceRegistered', 'CapacityAllocated',
            'PaymentValidated', 'PaymentRejected', 'ReservationConfirmed', 'CapacityReleased', 'ReservationCancelled',
            'ClientNotified')
            AND reservation_id IS NOT NULL AND previous_catalog_status IS NULL AND new_catalog_status IS NULL)
        OR (event_type IN ('CustomerRegistered', 'SensitiveDataAccessed') AND customer_id IS NOT NULL
            AND previous_catalog_status IS NULL AND new_catalog_status IS NULL))),
    ADD CONSTRAINT chk_outbox_event_payload CHECK (
        (event_type IN ('ReservationModified', 'CustomerRegistered', 'SensitiveDataAccessed',
            'ReservationCreated', 'PaymentEvidenceRegistered', 'CapacityAllocated',
            'PaymentValidated', 'PaymentRejected', 'ReservationConfirmed', 'CapacityReleased', 'ReservationCancelled',
            'ClientNotified')
            AND payload IS NOT NULL AND jsonb_typeof(payload) = 'object')
        OR (event_type NOT IN ('ReservationModified', 'CustomerRegistered', 'SensitiveDataAccessed',
            'ReservationCreated', 'PaymentEvidenceRegistered', 'CapacityAllocated',
            'PaymentValidated', 'PaymentRejected', 'ReservationConfirmed', 'CapacityReleased', 'ReservationCancelled',
            'ClientNotified')
            AND payload IS NULL)),
    ADD CONSTRAINT chk_outbox_event_actor_required CHECK (
        actor_id IS NOT NULL OR event_type IN ('CustomerRegistered', 'ClientNotified'));
