-- HU-COM-005 (-db) DP-D5-7, AC-D5.7: the default privileges of 001 gave the reader SELECT on every table
-- of the schema. It is withdrawn from the two sensitive tables, after they exist. The writer keeps its
-- SELECT, INSERT and UPDATE; the permission "Consultar datos sensibles" is the API's.
REVOKE SELECT ON commercial_reservation.customer_sensitive_data FROM commercial_reservation_reader;
REVOKE SELECT ON commercial_reservation.reservation_companion_sensitive_data FROM commercial_reservation_reader;
