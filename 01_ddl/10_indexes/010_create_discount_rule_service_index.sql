-- Own index for the service foreign key of discount_rule_service (Annex A); the rule side is the primary key.
CREATE INDEX CONCURRENTLY idx_discount_rule_service_service_id ON commercial_reservation.discount_rule_service (service_id);
