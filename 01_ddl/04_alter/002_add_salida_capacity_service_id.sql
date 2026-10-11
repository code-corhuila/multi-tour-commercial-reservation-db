-- PROPOSED, not confirmed by 06-data (spec.md DD-6): salida_capacity did not say which catalog service
-- a departure belongs to, and without it the api cannot compare the new capacity of a tour against the
-- seats held on ITS departures, in local rows and in the same transaction (api plan D-05, RN-05, T-06).
-- It lives in 04_alter because 004_create_salida_capacity.sql is already applied and is never edited.
--
-- NOT NULL and no DEFAULT: the service decides the value (plan.md DD-8). The table is empty and has had
-- no release, so adding the column without a backfill cannot fail.
-- The foreign key is simple, (service_id) alone, and not (tenant_id, service_id): the key of
-- catalog_service is service_id by itself (pk_catalog_service) and no UNIQUE carries tenant_id, so a
-- composite key has nothing to point at. The tenant of the service is therefore kept by the
-- application, not by the engine; the debt is recorded in spec.md DD-6.
-- RESTRICT, since a service with capacity rows must not disappear from under its departures.
-- salida_id keeps NO foreign key: the departure belongs to operations-cost, another domain (Annex J.3.4).
ALTER TABLE commercial_reservation.salida_capacity ADD COLUMN service_id uuid NOT NULL;

ALTER TABLE commercial_reservation.salida_capacity
    ADD CONSTRAINT fk_salida_capacity_service FOREIGN KEY (service_id)
    REFERENCES commercial_reservation.catalog_service (service_id) ON DELETE RESTRICT;
