-- HU-COM-020 AC-20.13, RN-12 (docs spec 020 DP-05 and DP-D20-5 of the db spec, PROPOSED default): the envelope of outbox_event gains one nullable column, reason, that carries the marker RESTRICTED_ACCESS when the event was
-- written by the restricted Administrator of an inactive tenant. It is allowed and not required, so every row already stored stays valid. It admits one value and nothing else, so no free text, address or amount can travel in it;
-- no payload key list changes. The guard of the delivery columns (07_functions/008) freezes the column after the write because it is not a delivery column.
ALTER TABLE commercial_reservation.outbox_event
    ADD COLUMN reason text,
    ADD CONSTRAINT chk_outbox_event_reason CHECK (reason IS NULL OR reason = 'RESTRICTED_ACCESS');
