-- HU-COM-012 (-db) plan D-05, DP-D12-3 (PROPOSED default): the closed key list of the modification shape of ReservationModified. A payload that has the key
-- changeType must hold exactly these nine keys and no more, so no name, document, contact or free-text reason can travel (reasonCode only). A payload without
-- changeType keeps the shape of the additional discount (HU-COM-004), which this constraint does not touch. Additive: nothing existing is rewritten.
ALTER TABLE commercial_reservation.outbox_event
    ADD CONSTRAINT chk_outbox_event_payload_keys_reservation_modified_change CHECK (
        event_type <> 'ReservationModified'
        OR NOT jsonb_exists(payload, 'changeType')
        OR (jsonb_exists_all(payload, ARRAY['reservationId', 'changeType', 'previousFinalValueCents', 'newFinalValueCents',
                'previousPendingBalanceCents', 'newPendingBalanceCents', 'partySize', 'departureChanged', 'reasonCode'])
            AND payload - ARRAY['reservationId', 'changeType', 'previousFinalValueCents', 'newFinalValueCents',
                'previousPendingBalanceCents', 'newPendingBalanceCents', 'partySize', 'departureChanged', 'reasonCode'] = '{}'::jsonb));
