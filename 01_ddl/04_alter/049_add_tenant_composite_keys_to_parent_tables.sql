-- DD-11 of the follow-up spec (HU-COM-011) and DD-7 of the payment spec (HU-COM-009, DP-D9-12): the keys the composite foreign keys of 050 point at.
-- Every parent that is referenced by a table with its own tenant_id gets UNIQUE (tenant_id, <its key>). The key is already unique alone, so no row can break it.
ALTER TABLE commercial_reservation.customer
    ADD CONSTRAINT uq_customer_tenant_id_customer_id UNIQUE (tenant_id, customer_id);
ALTER TABLE commercial_reservation.catalog_service
    ADD CONSTRAINT uq_catalog_service_tenant_id_service_id UNIQUE (tenant_id, service_id);
ALTER TABLE commercial_reservation.discount_rule
    ADD CONSTRAINT uq_discount_rule_tenant_id_discount_rule_id UNIQUE (tenant_id, discount_rule_id);
ALTER TABLE commercial_reservation.reservation
    ADD CONSTRAINT uq_reservation_tenant_id_reservation_id UNIQUE (tenant_id, reservation_id);
ALTER TABLE commercial_reservation.reservation_companion
    ADD CONSTRAINT uq_reservation_companion_tenant_id_reservation_companion_id UNIQUE (tenant_id, reservation_companion_id);
ALTER TABLE commercial_reservation.payment_attempt
    ADD CONSTRAINT uq_payment_attempt_tenant_id_payment_attempt_id UNIQUE (tenant_id, payment_attempt_id);
ALTER TABLE commercial_reservation.financial_decision
    ADD CONSTRAINT uq_financial_decision_tenant_id_financial_decision_id UNIQUE (tenant_id, financial_decision_id);
ALTER TABLE commercial_reservation.credit_balance
    ADD CONSTRAINT uq_credit_balance_tenant_id_credit_balance_id UNIQUE (tenant_id, credit_balance_id);
ALTER TABLE commercial_reservation.rescheduling_episode
    ADD CONSTRAINT uq_rescheduling_episode_tenant_id_rescheduling_episode_id UNIQUE (tenant_id, rescheduling_episode_id);
ALTER TABLE commercial_reservation.associated_establishment
    ADD CONSTRAINT uq_associated_establishment_tenant_id_association_id UNIQUE (tenant_id, association_id);
