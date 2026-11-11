-- HU-COM-007 (-db) plan D-07, announced by 005 D-08 and 004: the two keys that waited for the reservation table.
-- Applied changesets are never edited (Annex A), so the keys arrive here. No environment holds a reservation, so no row can break them.
-- Neither needs an index: the unique that starts with reservation_id covers each (uq_reservation_additional_discount_reservation and the
-- unique (reservation_id, document_number) of 005).
ALTER TABLE commercial_reservation.reservation_companion
    ADD CONSTRAINT fk_reservation_companion_reservation FOREIGN KEY (reservation_id)
        REFERENCES commercial_reservation.reservation (reservation_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.reservation_additional_discount
    ADD CONSTRAINT fk_reservation_additional_discount_reservation FOREIGN KEY (reservation_id)
        REFERENCES commercial_reservation.reservation (reservation_id) ON DELETE RESTRICT;
