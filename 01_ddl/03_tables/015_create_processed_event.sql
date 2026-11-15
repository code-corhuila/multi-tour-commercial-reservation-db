-- HU-COM-006 (-db) plan D-05 (PROPOSED, debt DD-2): the events this micro has already applied, so that a repeated delivery is
-- recognized by its id (ADR-004 D4, idempotent consumption). The columns are the two of modeling-conventions.md (DP-D6-4): a
-- consumer asks for an id, not for a tenant. No DEFAULT: the service states the moment. The ids are purged after 30 days.
CREATE TABLE commercial_reservation.processed_event (
    event_id uuid NOT NULL,
    processed_at timestamptz NOT NULL,
    CONSTRAINT pk_processed_event PRIMARY KEY (event_id)
);
