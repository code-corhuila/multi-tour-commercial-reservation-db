-- HU-COM-015 (-db) plan D-04, AC-D15.6 and AC-D15.7 (PROPOSED names, ADR-004 D4 and D10): the delivery data of an outbox event stays on the event itself. attempts counts the
-- failed deliveries (0 to 20), last_error keeps a truncated reason and never a body, next_attempt_at is the wait before the next try, failed_at marks the event that
-- exhausted its attempts and stays visible, correlation_id carries the trace of the request that wrote the fact. attempts is the one DEFAULT of the slice, so every row
-- written before it is valid; the others are null. delivery_state refuses the impossible combinations: published and failed together, a failed mark with no attempt, and
-- a wait on a row that is published or failed.
ALTER TABLE commercial_reservation.outbox_event
    ADD COLUMN attempts integer NOT NULL DEFAULT 0,
    ADD COLUMN last_error text,
    ADD COLUMN next_attempt_at timestamptz,
    ADD COLUMN failed_at timestamptz,
    ADD COLUMN correlation_id text,
    ADD CONSTRAINT chk_outbox_event_attempts_range CHECK (attempts BETWEEN 0 AND 20),
    ADD CONSTRAINT chk_outbox_event_last_error_length CHECK (last_error IS NULL OR char_length(last_error) <= 500),
    ADD CONSTRAINT chk_outbox_event_correlation_id_length CHECK (correlation_id IS NULL OR char_length(correlation_id) <= 64),
    ADD CONSTRAINT chk_outbox_event_delivery_state CHECK (
        (published_at IS NULL OR failed_at IS NULL)
        AND (failed_at IS NULL OR attempts >= 1)
        AND (next_attempt_at IS NULL OR (published_at IS NULL AND failed_at IS NULL)));
