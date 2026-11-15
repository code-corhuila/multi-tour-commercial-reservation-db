-- HU-COM-019 (-db) plan D-05, AC-D19.10 (DP-D19-4, PROPOSED default): the seventh widening of outbox_event adds SensitiveDataDeleted, written in the transaction of the deletion. The reservation
-- is the aggregate and the customer travels in the payload. The payload is closed to ids, the anchor, the basis, a flag and a count, so no name, document, contact or medical value can travel.
-- The actor is optional, because the retention job acts for the system. The four lists are rewritten as 031 wrote them with the one new event, and the actor rule with it; nothing is removed.
ALTER TABLE commercial_reservation.outbox_event
    DROP CONSTRAINT chk_outbox_event_actor_required,
    DROP CONSTRAINT chk_outbox_event_event_type,
    DROP CONSTRAINT chk_outbox_event_type_matches_new_condition,
    DROP CONSTRAINT chk_outbox_event_exactly_one_aggregate,
    DROP CONSTRAINT chk_outbox_event_payload,
    ADD CONSTRAINT chk_outbox_event_event_type CHECK (event_type IN (
        'CatalogServiceInactivated', 'CatalogServiceReactivated',
        'EstablishmentAssociationPublished', 'EstablishmentAssociationInactivated',
        'EstablishmentAssociationReactivated', 'DiscountRuleChanged',
        'ReservationModified', 'CustomerRegistered', 'SensitiveDataAccessed',
        'ReservationCreated', 'PaymentEvidenceRegistered', 'CapacityAllocated',
        'PaymentValidated', 'PaymentRejected', 'ReservationConfirmed', 'CapacityReleased',
        'ReservationCancelled', 'ClientNotified', 'RefundAuthorized', 'CreditBalanceRecorded', 'CreditBalanceApplied', 'SensitiveDataDeleted')),
    ADD CONSTRAINT chk_outbox_event_type_matches_new_condition CHECK (
        event_type IN ('DiscountRuleChanged', 'ReservationModified', 'CustomerRegistered', 'SensitiveDataAccessed',
            'ReservationCreated', 'PaymentEvidenceRegistered', 'CapacityAllocated',
            'PaymentValidated', 'PaymentRejected', 'ReservationConfirmed', 'CapacityReleased', 'ReservationCancelled',
            'ClientNotified', 'RefundAuthorized', 'CreditBalanceRecorded', 'CreditBalanceApplied', 'SensitiveDataDeleted')
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
            'ClientNotified', 'RefundAuthorized', 'CreditBalanceRecorded', 'CreditBalanceApplied', 'SensitiveDataDeleted')
            AND reservation_id IS NOT NULL AND previous_catalog_status IS NULL AND new_catalog_status IS NULL)
        OR (event_type IN ('CustomerRegistered', 'SensitiveDataAccessed') AND customer_id IS NOT NULL
            AND previous_catalog_status IS NULL AND new_catalog_status IS NULL))),
    ADD CONSTRAINT chk_outbox_event_payload CHECK (
        (event_type IN ('ReservationModified', 'CustomerRegistered', 'SensitiveDataAccessed',
            'ReservationCreated', 'PaymentEvidenceRegistered', 'CapacityAllocated',
            'PaymentValidated', 'PaymentRejected', 'ReservationConfirmed', 'CapacityReleased', 'ReservationCancelled',
            'ClientNotified', 'RefundAuthorized', 'CreditBalanceRecorded', 'CreditBalanceApplied', 'SensitiveDataDeleted')
            AND payload IS NOT NULL AND jsonb_typeof(payload) = 'object')
        OR (event_type NOT IN ('ReservationModified', 'CustomerRegistered', 'SensitiveDataAccessed',
            'ReservationCreated', 'PaymentEvidenceRegistered', 'CapacityAllocated',
            'PaymentValidated', 'PaymentRejected', 'ReservationConfirmed', 'CapacityReleased', 'ReservationCancelled',
            'ClientNotified', 'RefundAuthorized', 'CreditBalanceRecorded', 'CreditBalanceApplied', 'SensitiveDataDeleted')
            AND payload IS NULL)),
    ADD CONSTRAINT chk_outbox_event_actor_required CHECK (
        actor_id IS NOT NULL OR event_type IN ('CustomerRegistered', 'ClientNotified', 'RefundAuthorized', 'SensitiveDataDeleted')),
    ADD CONSTRAINT chk_outbox_event_payload_keys_sensitive_data_deleted CHECK (
        event_type <> 'SensitiveDataDeleted'
        OR (jsonb_exists_all(payload, ARRAY['reservationId', 'customerId', 'anchorBasis', 'anchorAt', 'customerDataDeleted', 'companionRowsDeleted'])
            AND payload - ARRAY['reservationId', 'customerId', 'anchorBasis', 'anchorAt', 'customerDataDeleted', 'companionRowsDeleted'] = '{}'::jsonb));
