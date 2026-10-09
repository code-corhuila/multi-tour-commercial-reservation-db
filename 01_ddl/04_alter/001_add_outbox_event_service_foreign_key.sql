-- Added here and not in 002_create_outbox_event.sql because the catalog table did not exist yet when
-- the outbox was created. RESTRICT, since an event must never outlive the service it announces.
ALTER TABLE commercial_reservation.outbox_event
    ADD CONSTRAINT fk_outbox_event_service FOREIGN KEY (service_id)
    REFERENCES commercial_reservation.catalog_service (service_id) ON DELETE RESTRICT;
