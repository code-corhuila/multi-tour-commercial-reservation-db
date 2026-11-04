-- HU-COM-013 (-db) plan D-03, AC-D13.4 (PROPOSED, amended 2026-11-04): a settlement can hang only from a reservation that was cancelled at the customer's request
-- and belongs to the same tenant. The unique key on (tenant, reservation, cause) is what the composite foreign key points at; it is added here and not in the
-- table because the key must exist first. The reservation is updated to CANCELLED before the settlement is inserted, so the immediate check passes.
ALTER TABLE commercial_reservation.reservation
    ADD CONSTRAINT uq_reservation_tenant_id_cancellation_cause UNIQUE (tenant_id, reservation_id, cancellation_cause);
ALTER TABLE commercial_reservation.reservation_cancellation
    ADD CONSTRAINT fk_reservation_cancellation_reservation FOREIGN KEY (tenant_id, reservation_id, cancellation_cause)
        REFERENCES commercial_reservation.reservation (tenant_id, reservation_id, cancellation_cause) ON DELETE RESTRICT;
