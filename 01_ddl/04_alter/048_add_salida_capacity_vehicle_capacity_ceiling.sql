-- HU-COM-006 (-db), ND-08 and DP-D6-8 (PROPOSED default, owner Fernanda): the total capacity of the vehicles assigned to the departure, as the last
-- SalidaVehiclesChanged reported it (data-dictionary field vehicleCapacityCeiling, INFERIDO). The service keeps it so that effective_capacity can be recomputed
-- when the tour capacity changes, as max(min(tour capacity, total), held seats) (RN-SAL-001, H8), without a call to operations-cost. It is not stored anywhere else:
-- effective_capacity may be bound by the tour, so the total cannot be derived from it.
-- Nullable and without DEFAULT: a row born before this column, or a departure with no vehicle event yet, has no known total, and the service then leaves its effective
-- capacity as it is (no backfill). A known total is never negative; zero is allowed (mandatory transport with no vehicle assigned yet). effective_capacity and held_seats are untouched.
ALTER TABLE commercial_reservation.salida_capacity
    ADD COLUMN vehicle_capacity_ceiling integer,
    ADD CONSTRAINT chk_salida_capacity_vehicle_capacity_ceiling CHECK (vehicle_capacity_ceiling IS NULL OR vehicle_capacity_ceiling >= 0);
