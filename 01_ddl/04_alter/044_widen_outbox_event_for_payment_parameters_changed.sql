-- HU-COM-009 DP-04 (Project Lead, 2026-11-12; domain-events.md): the tenth widening of outbox_event adds PaymentParametersChanged, the audit trace of a change of the payment parameters. The owner is
-- Commercial and the audit domain stores it, so the service writes one event per changed parameter row in the same transaction as the change. The aggregate is the changed row of payment_condition, so the one
-- change to the aggregate rule is a seventh reference, payment_condition_id uuid NULL (no foreign key, as authorization_id: the outbox is not rewritten when a row is replaced). exactly_one_aggregate now counts
-- seven references, exactly one, and the type says which one. The payload is closed: tenantId, actorId, paymentType and changedAt are required and serviceId is allowed (the tenant level has none), so no value of a
-- parameter, reason or personal datum can travel (chk_outbox_event_payload_no_sensitive_keys of 010 applies as well). The actor (the Tenant Administrator) is required. The five lists are rewritten as 040 left
-- them with the one new event; nothing is removed.
ALTER TABLE commercial_reservation.outbox_event
    ADD COLUMN payment_condition_id uuid,
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
        'ReservationCancelled', 'ClientNotified', 'RefundAuthorized', 'CreditBalanceRecorded', 'CreditBalanceApplied', 'SensitiveDataDeleted', 'ReservationRescheduled',
        'PlatformExceptionalAccessUsed', 'PaymentParametersChanged')),
    ADD CONSTRAINT chk_outbox_event_type_matches_new_condition CHECK (
        event_type IN ('DiscountRuleChanged', 'ReservationModified', 'CustomerRegistered', 'SensitiveDataAccessed',
            'ReservationCreated', 'PaymentEvidenceRegistered', 'CapacityAllocated',
            'PaymentValidated', 'PaymentRejected', 'ReservationConfirmed', 'CapacityReleased', 'ReservationCancelled',
            'ClientNotified', 'RefundAuthorized', 'CreditBalanceRecorded', 'CreditBalanceApplied', 'SensitiveDataDeleted', 'ReservationRescheduled',
            'PlatformExceptionalAccessUsed', 'PaymentParametersChanged')
        OR (new_catalog_status IS NOT NULL AND (
        (event_type = 'EstablishmentAssociationPublished'
            AND previous_catalog_status IS NULL AND new_catalog_status = 'ACTIVE')
        OR (event_type IN ('CatalogServiceInactivated', 'EstablishmentAssociationInactivated')
            AND new_catalog_status = 'INACTIVE')
        OR (event_type IN ('CatalogServiceReactivated', 'EstablishmentAssociationReactivated')
            AND new_catalog_status = 'ACTIVE')))),
    ADD CONSTRAINT chk_outbox_event_exactly_one_aggregate CHECK (
        num_nonnulls(service_id, association_id, discount_rule_id, reservation_id, customer_id, authorization_id, payment_condition_id) = 1 AND (
        (event_type IN ('CatalogServiceInactivated', 'CatalogServiceReactivated')
            AND service_id IS NOT NULL AND previous_catalog_status IS NOT NULL)
        OR (event_type IN ('EstablishmentAssociationPublished',
            'EstablishmentAssociationInactivated', 'EstablishmentAssociationReactivated')
            AND association_id IS NOT NULL)
        OR (event_type = 'DiscountRuleChanged' AND discount_rule_id IS NOT NULL
            AND previous_catalog_status IS NULL AND new_catalog_status IS NULL)
        OR (event_type IN ('ReservationModified', 'ReservationCreated', 'PaymentEvidenceRegistered', 'CapacityAllocated',
            'PaymentValidated', 'PaymentRejected', 'ReservationConfirmed', 'CapacityReleased', 'ReservationCancelled',
            'ClientNotified', 'RefundAuthorized', 'CreditBalanceRecorded', 'CreditBalanceApplied', 'SensitiveDataDeleted', 'ReservationRescheduled')
            AND reservation_id IS NOT NULL AND previous_catalog_status IS NULL AND new_catalog_status IS NULL)
        OR (event_type IN ('CustomerRegistered', 'SensitiveDataAccessed') AND customer_id IS NOT NULL
            AND previous_catalog_status IS NULL AND new_catalog_status IS NULL)
        OR (event_type = 'PlatformExceptionalAccessUsed' AND authorization_id IS NOT NULL
            AND previous_catalog_status IS NULL AND new_catalog_status IS NULL)
        OR (event_type = 'PaymentParametersChanged' AND payment_condition_id IS NOT NULL
            AND previous_catalog_status IS NULL AND new_catalog_status IS NULL))),
    ADD CONSTRAINT chk_outbox_event_payload CHECK (
        (event_type IN ('ReservationModified', 'CustomerRegistered', 'SensitiveDataAccessed',
            'ReservationCreated', 'PaymentEvidenceRegistered', 'CapacityAllocated',
            'PaymentValidated', 'PaymentRejected', 'ReservationConfirmed', 'CapacityReleased', 'ReservationCancelled',
            'ClientNotified', 'RefundAuthorized', 'CreditBalanceRecorded', 'CreditBalanceApplied', 'SensitiveDataDeleted', 'ReservationRescheduled',
            'PlatformExceptionalAccessUsed', 'PaymentParametersChanged')
            AND payload IS NOT NULL AND jsonb_typeof(payload) = 'object')
        OR (event_type NOT IN ('ReservationModified', 'CustomerRegistered', 'SensitiveDataAccessed',
            'ReservationCreated', 'PaymentEvidenceRegistered', 'CapacityAllocated',
            'PaymentValidated', 'PaymentRejected', 'ReservationConfirmed', 'CapacityReleased', 'ReservationCancelled',
            'ClientNotified', 'RefundAuthorized', 'CreditBalanceRecorded', 'CreditBalanceApplied', 'SensitiveDataDeleted', 'ReservationRescheduled',
            'PlatformExceptionalAccessUsed', 'PaymentParametersChanged')
            AND payload IS NULL)),
    ADD CONSTRAINT chk_outbox_event_actor_required CHECK (
        actor_id IS NOT NULL OR event_type IN ('CustomerRegistered', 'ClientNotified', 'RefundAuthorized', 'SensitiveDataDeleted')),
    ADD CONSTRAINT chk_outbox_event_payload_keys_payment_parameters_changed CHECK (
        event_type <> 'PaymentParametersChanged'
        OR (jsonb_exists_all(payload, ARRAY['tenantId', 'actorId', 'paymentType', 'changedAt'])
            AND payload - ARRAY['tenantId', 'actorId', 'paymentType', 'serviceId', 'changedAt'] = '{}'::jsonb
            AND payload ->> 'paymentType' IN ('FULL_PAYMENT', 'DEPOSIT')));
