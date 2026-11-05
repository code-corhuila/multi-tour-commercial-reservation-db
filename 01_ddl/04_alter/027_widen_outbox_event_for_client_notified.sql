-- HU-COM-015 (-db) plan D-02, DP-D15-1 and DP-D15-2 (PROPOSED defaults): the fourth widening of outbox_event adds ClientNotified (domain-events.md), the notice of RF-019
-- written in the transaction of the fact it announces. The reservation is its aggregate and the customer travels in the payload as a reference, never as data. The payload
-- is closed to customerId, notificationType, triggeringEventType and triggeringEventId, so no address, name, amount or reason can travel (chk_outbox_event_payload_no_sensitive_keys
-- of 010 applies as well). notificationType is one of the eight codes of the -api and triggeringEventType one of the events that domain-events.md names as the source of a
-- notice. The actor is optional for this event, as for CustomerRegistered (a system fact has none). The five lists are rewritten as 023 wrote them, with the one new event.
ALTER TABLE commercial_reservation.outbox_event
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
        actor_id IS NOT NULL OR event_type IN ('CustomerRegistered', 'ClientNotified')),
    ADD CONSTRAINT chk_outbox_event_payload_keys_client_notified CHECK (
        event_type <> 'ClientNotified'
        OR (jsonb_exists_all(payload, ARRAY['customerId', 'notificationType', 'triggeringEventType', 'triggeringEventId'])
            AND payload - ARRAY['customerId', 'notificationType', 'triggeringEventType', 'triggeringEventId'] = '{}'::jsonb)),
    ADD CONSTRAINT chk_outbox_event_client_notified_codes CHECK (
        event_type <> 'ClientNotified'
        OR (coalesce(payload ->> 'notificationType' IN (
            'PROOF_APPROVED', 'PROOF_REJECTED', 'RESERVATION_CONFIRMED', 'RESERVATION_CANCELLED_NON_PAYMENT',
            'REFUND_PROCESSED', 'CREDIT_BALANCE_RECORDED', 'DEPARTURE_CANCELLED', 'RESCHEDULING_PROPOSED'), false)
            AND coalesce(payload ->> 'triggeringEventType' IN (
            'PaymentValidated', 'PaymentRejected', 'ReservationConfirmed', 'ReservationCancelled',
            'RefundExecuted', 'CreditBalanceRecorded', 'SalidaCancelled', 'ReservationRescheduled'), false)));
