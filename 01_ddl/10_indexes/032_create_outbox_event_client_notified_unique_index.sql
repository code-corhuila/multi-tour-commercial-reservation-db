-- HU-COM-015 (-db) plan D-03, AC-D15.5: one notice per triggering event and tenant, the engine half of the idempotency of the -api (a unique violation is read as
-- "already written"). The key is the tenant and the triggering event id held in the payload, only for ClientNotified. Built CONCURRENTLY, as the only statement of its
-- changeset and outside a transaction, so writes to the outbox are not blocked (norm 5.2.7). If a failed build left an invalid index, drop it before the retry.
CREATE UNIQUE INDEX CONCURRENTLY uq_outbox_event_client_notified_trigger ON commercial_reservation.outbox_event (tenant_id, (payload ->> 'triggeringEventId')) WHERE event_type = 'ClientNotified';
