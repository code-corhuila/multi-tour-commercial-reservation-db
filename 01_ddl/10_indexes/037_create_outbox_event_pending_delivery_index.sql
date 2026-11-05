-- HU-COM-015 (-db) plan D-05, AC-D15.10: the read of the relay (job 7) takes the pending events, the ones never tried first and then the ones whose wait elapsed, oldest first. Partial on
-- published_at IS NULL AND failed_at IS NULL, so it holds the pending events only and stays small however many published rows pile up behind it; idx_outbox_event_unpublished of 001 stays
-- (an applied changeset is never edited) and keeps serving the older reads. Built CONCURRENTLY, as the only statement of its changeset and outside a transaction, so writes to the outbox
-- are not blocked (norm 5.2.7). If a failed build left an invalid index, drop it before the retry.
CREATE INDEX CONCURRENTLY idx_outbox_event_pending_delivery ON commercial_reservation.outbox_event (next_attempt_at NULLS FIRST, occurred_at) WHERE published_at IS NULL AND failed_at IS NULL;
