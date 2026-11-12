-- HU-SEC-007 G-SEC9-1 (-db): the closed list of 040, with occurredAt in place of usedAt. A database that already holds rows with usedAt refuses this revert on purpose: the audit is never rewritten.
ALTER TABLE commercial_reservation.outbox_event
    DROP CONSTRAINT chk_outbox_event_payload_keys_platform_exceptional_access_used,
    ADD CONSTRAINT chk_outbox_event_payload_keys_platform_exceptional_access_used CHECK (
        event_type <> 'PlatformExceptionalAccessUsed'
        OR (jsonb_exists_all(payload, ARRAY['authorizationId', 'platformAdministratorId', 'tenantId', 'method', 'route', 'area', 'occurredAt', 'correlationId'])
            AND payload - ARRAY['authorizationId', 'platformAdministratorId', 'tenantId', 'method', 'route', 'area', 'occurredAt', 'correlationId'] = '{}'::jsonb));
