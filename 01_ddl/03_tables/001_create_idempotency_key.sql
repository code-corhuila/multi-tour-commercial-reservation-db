-- One table for the whole domain (plan.md D-06; the key is unique per tenant, modeling-conventions.md), written in the same transaction as the resource it
-- guards (norm 5.3.8). The resource is referenced by type and identifier with no foreign key: the
-- types are many and the table that holds each one may not exist yet.
CREATE TABLE commercial_reservation.idempotency_key (
    key           text        NOT NULL,
    tenant_id     uuid        NOT NULL,
    resource_type text        NOT NULL,
    resource_id   uuid        NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now(),
    -- scoped by tenant, so a tenant can never be handed the resource another tenant created with the same key
    CONSTRAINT pk_idempotency_key PRIMARY KEY (tenant_id, key),
    -- the length the Idempotency-Key header must have (Annex C)
    CONSTRAINT chk_idempotency_key_key_length CHECK (char_length(key) BETWEEN 8 AND 128),
    CONSTRAINT chk_idempotency_key_resource_type_length CHECK (char_length(resource_type) BETWEEN 1 AND 64)
);
