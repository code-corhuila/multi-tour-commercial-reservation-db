-- Written by this domain's API in the same transaction as the change it announces (norm 5.3.11,
-- plan.md D-07). The relay reads it through the API, never by connecting here.
--
-- The columns are the ones both catalog events declare in domain-events.md. They are explicit, and
-- not a jsonb payload, so that the engine itself refuses an event without its actor or with an
-- unknown condition; a payload would need one CHECK per key to say the same.
-- service_id carries no foreign key yet: the catalog table arrives in T-08, which adds it in 04_alter.
CREATE TABLE commercial_reservation.outbox_event (
    outbox_event_id         uuid        NOT NULL DEFAULT gen_random_uuid(),
    tenant_id               uuid        NOT NULL,
    event_type              text        NOT NULL,
    service_id              uuid        NOT NULL,
    previous_catalog_status text        NOT NULL,
    new_catalog_status      text        NOT NULL,
    actor_id                uuid        NOT NULL,
    occurred_at             timestamptz NOT NULL,
    -- null until the relay has delivered the event
    published_at            timestamptz,
    CONSTRAINT pk_outbox_event PRIMARY KEY (outbox_event_id),
    CONSTRAINT chk_outbox_event_event_type CHECK (event_type IN ('CatalogServiceInactivated', 'CatalogServiceReactivated')),
    CONSTRAINT chk_outbox_event_previous_catalog_status CHECK (previous_catalog_status IN ('ACTIVE', 'INACTIVE')),
    CONSTRAINT chk_outbox_event_new_catalog_status CHECK (new_catalog_status IN ('ACTIVE', 'INACTIVE')),
    -- an event announces a change, so the two conditions differ and the type says which way it went
    CONSTRAINT chk_outbox_event_condition_changed CHECK (previous_catalog_status <> new_catalog_status),
    CONSTRAINT chk_outbox_event_type_matches_new_condition CHECK (
        (event_type = 'CatalogServiceInactivated' AND new_catalog_status = 'INACTIVE')
        OR (event_type = 'CatalogServiceReactivated' AND new_catalog_status = 'ACTIVE')
    )
);
