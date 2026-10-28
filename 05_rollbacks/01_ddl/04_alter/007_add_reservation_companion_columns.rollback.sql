ALTER TABLE commercial_reservation.reservation_companion
    DROP CONSTRAINT uq_reservation_companion_reservation_document,
    DROP CONSTRAINT chk_reservation_companion_document_number_normalized,
    DROP COLUMN birth_date_or_age,
    DROP COLUMN document_number;
