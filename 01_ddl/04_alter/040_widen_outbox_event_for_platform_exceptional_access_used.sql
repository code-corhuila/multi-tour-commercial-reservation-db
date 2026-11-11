-- HU-SEC-007 G-SEC9-1 (ADR-004 D5; Project Lead, 2026-11-11): the ninth widening of outbox_event adds PlatformExceptionalAccessUsed, the audit of each use of the token of an exceptional or
-- emergency access, written by the service in the same step as the read it audits. The event has no business aggregate: its aggregate is the authorization of the access, so the one change to the
-- aggregate rule is a sixth reference, authorization_id uuid NULL (no foreign key: the access lives in the security service). exactly_one_aggregate now counts six references, exactly one, and the
-- type says which one. The payload is closed to eight keys of identifiers, a method, a route template, an area and an instant, so no data of the request or of the response can travel
-- (chk_outbox_event_payload_no_sensitive_keys of 010 applies as well). The actor (the Platform Administrator, the sub of the token) is required. The five lists are rewritten as 036 left them with
-- the one new event; nothing is removed.
ALTER TABLE commercial_reservation.outbox_event
    ADD COLUMN authorization_id uuid,
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
        'PlatformExceptionalAccessUsed')),
    ADD CONSTRAINT chk_outbox_event_type_matches_new_condition CHECK (
        event_type IN ('DiscountRuleChanged', 'ReservationModified', 'CustomerRegistered', 'SensitiveDataAccessed',
            'ReservationCreated', 'PaymentEvidenceRegistered', 'CapacityAllocated',
            'PaymentValidated', 'PaymentRejected', 'ReservationConfirmed', 'CapacityReleased', 'ReservationCancelled',
            'ClientNotified', 'RefundAuthorized', 'CreditBalanceRecorded', 'CreditBalanceApplied', 'SensitiveDataDeleted', 'ReservationRescheduled',
            'PlatformExceptionalAccessUsed')
        OR (new_catalog_status IS NOT NULL AND (
        (event_type = 'EstablishmentAssociationPublished'
            AND previous_catalog_status IS NULL AND new_catalog_status = 'ACTIVE')
        OR (event_type IN ('CatalogServiceInactivated', 'EstablishmentAssociationInactivated')
            AND new_catalog_status = 'INACTIVE')
        OR (event_type IN ('CatalogServiceReactivated', 'EstablishmentAssociationReactivated')
            AND new_catalog_status = 'ACTIVE')))),
    ADD CONSTRAINT chk_outbox_event_exactly_one_aggregate CHECK (
        num_nonnulls(service_id, association_id, discount_rule_id, reservation_id, customer_id, authorization_id) = 1 AND (
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
            AND previous_catalog_status IS NULL AND new_catalog_status IS NULL))),
    ADD CONSTRAINT chk_outbox_event_payload CHECK (
        (event_type IN ('ReservationModified', 'CustomerRegistered', 'SensitiveDataAccessed',
            'ReservationCreated', 'PaymentEvidenceRegistered', 'CapacityAllocated',
            'PaymentValidated', 'PaymentRejected', 'ReservationConfirmed', 'CapacityReleased', 'ReservationCancelled',
            'ClientNotified', 'RefundAuthorized', 'CreditBalanceRecorded', 'CreditBalanceApplied', 'SensitiveDataDeleted', 'ReservationRescheduled',
            'PlatformExceptionalAccessUsed')
            AND payload IS NOT NULL AND jsonb_typeof(payload) = 'object')
        OR (event_type NOT IN ('ReservationModified', 'CustomerRegistered', 'SensitiveDataAccessed',
            'ReservationCreated', 'PaymentEvidenceRegistered', 'CapacityAllocated',
            'PaymentValidated', 'PaymentRejected', 'ReservationConfirmed', 'CapacityReleased', 'ReservationCancelled',
            'ClientNotified', 'RefundAuthorized', 'CreditBalanceRecorded', 'CreditBalanceApplied', 'SensitiveDataDeleted', 'ReservationRescheduled',
            'PlatformExceptionalAccessUsed')
            AND payload IS NULL)),
    ADD CONSTRAINT chk_outbox_event_actor_required CHECK (
        actor_id IS NOT NULL OR event_type IN ('CustomerRegistered', 'ClientNotified', 'RefundAuthorized', 'SensitiveDataDeleted')),
    ADD CONSTRAINT chk_outbox_event_payload_keys_platform_exceptional_access_used CHECK (
        event_type <> 'PlatformExceptionalAccessUsed'
        OR (jsonb_exists_all(payload, ARRAY['authorizationId', 'platformAdministratorId', 'tenantId', 'method', 'route', 'area', 'occurredAt', 'correlationId'])
            AND payload - ARRAY['authorizationId', 'platformAdministratorId', 'tenantId', 'method', 'route', 'area', 'occurredAt', 'correlationId'] = '{}'::jsonb));
