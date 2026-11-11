-- HU-COM-006 (-db), DP-16 and DD-8 answered by the Project Lead: the departure mirror keeps the occurredAt of the last event it applied, so an event older than that instant never overwrites
-- a newer state. The column is nullable because a row born before the marker has no value (the first event after it sets one). No DEFAULT: the service decides the value.
ALTER TABLE commercial_reservation.salida_capacity
    ADD COLUMN last_event_occurred_at timestamptz;
