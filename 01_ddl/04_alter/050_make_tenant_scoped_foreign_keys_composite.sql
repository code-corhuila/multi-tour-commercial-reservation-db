-- DD-11 of the follow-up spec (HU-COM-011) and DD-7 of the payment spec (HU-COM-009, DP-D9-12): every foreign key between two tables that both carry tenant_id now includes it,
-- so the engine refuses a row of one tenant that points at a row of another (INV-TEN-001, CA-016). The keys keep their names, so no message of an adapter changes.
-- Each key is rebuilt in one statement: the simple key is dropped, the composite one added NOT VALID, then validated; a row that already crosses tenants stops the changeset naming the key, and nothing is deleted.
ALTER TABLE commercial_reservation.customer_sensitive_data DROP CONSTRAINT fk_customer_sensitive_data_customer,
    ADD CONSTRAINT fk_customer_sensitive_data_customer FOREIGN KEY (tenant_id, customer_id) REFERENCES commercial_reservation.customer (tenant_id, customer_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.customer_sensitive_data VALIDATE CONSTRAINT fk_customer_sensitive_data_customer;
ALTER TABLE commercial_reservation.reservation_companion_sensitive_data DROP CONSTRAINT fk_reservation_companion_sensitive_data_companion,
    ADD CONSTRAINT fk_reservation_companion_sensitive_data_companion FOREIGN KEY (tenant_id, reservation_companion_id) REFERENCES commercial_reservation.reservation_companion (tenant_id, reservation_companion_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.reservation_companion_sensitive_data VALIDATE CONSTRAINT fk_reservation_companion_sensitive_data_companion;
ALTER TABLE commercial_reservation.discount_rule_service DROP CONSTRAINT fk_discount_rule_service_rule,
    ADD CONSTRAINT fk_discount_rule_service_rule FOREIGN KEY (tenant_id, discount_rule_id) REFERENCES commercial_reservation.discount_rule (tenant_id, discount_rule_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.discount_rule_service VALIDATE CONSTRAINT fk_discount_rule_service_rule;
ALTER TABLE commercial_reservation.discount_rule_service DROP CONSTRAINT fk_discount_rule_service_service,
    ADD CONSTRAINT fk_discount_rule_service_service FOREIGN KEY (tenant_id, service_id) REFERENCES commercial_reservation.catalog_service (tenant_id, service_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.discount_rule_service VALIDATE CONSTRAINT fk_discount_rule_service_service;
ALTER TABLE commercial_reservation.reservation DROP CONSTRAINT fk_reservation_customer,
    ADD CONSTRAINT fk_reservation_customer FOREIGN KEY (tenant_id, customer_id) REFERENCES commercial_reservation.customer (tenant_id, customer_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.reservation VALIDATE CONSTRAINT fk_reservation_customer;
ALTER TABLE commercial_reservation.reservation DROP CONSTRAINT fk_reservation_service,
    ADD CONSTRAINT fk_reservation_service FOREIGN KEY (tenant_id, service_id) REFERENCES commercial_reservation.catalog_service (tenant_id, service_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.reservation VALIDATE CONSTRAINT fk_reservation_service;
ALTER TABLE commercial_reservation.reserved_service DROP CONSTRAINT fk_reserved_service_reservation,
    ADD CONSTRAINT fk_reserved_service_reservation FOREIGN KEY (tenant_id, reservation_id) REFERENCES commercial_reservation.reservation (tenant_id, reservation_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.reserved_service VALIDATE CONSTRAINT fk_reserved_service_reservation;
ALTER TABLE commercial_reservation.reserved_service DROP CONSTRAINT fk_reserved_service_service,
    ADD CONSTRAINT fk_reserved_service_service FOREIGN KEY (tenant_id, service_id) REFERENCES commercial_reservation.catalog_service (tenant_id, service_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.reserved_service VALIDATE CONSTRAINT fk_reserved_service_service;
ALTER TABLE commercial_reservation.reservation_fixed_discount DROP CONSTRAINT fk_reservation_fixed_discount_reservation,
    ADD CONSTRAINT fk_reservation_fixed_discount_reservation FOREIGN KEY (tenant_id, reservation_id) REFERENCES commercial_reservation.reservation (tenant_id, reservation_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.reservation_fixed_discount VALIDATE CONSTRAINT fk_reservation_fixed_discount_reservation;
ALTER TABLE commercial_reservation.reservation_fixed_discount DROP CONSTRAINT fk_reservation_fixed_discount_rule,
    ADD CONSTRAINT fk_reservation_fixed_discount_rule FOREIGN KEY (tenant_id, discount_rule_id) REFERENCES commercial_reservation.discount_rule (tenant_id, discount_rule_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.reservation_fixed_discount VALIDATE CONSTRAINT fk_reservation_fixed_discount_rule;
ALTER TABLE commercial_reservation.payment_attempt DROP CONSTRAINT fk_payment_attempt_reservation,
    ADD CONSTRAINT fk_payment_attempt_reservation FOREIGN KEY (tenant_id, reservation_id) REFERENCES commercial_reservation.reservation (tenant_id, reservation_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.payment_attempt VALIDATE CONSTRAINT fk_payment_attempt_reservation;
ALTER TABLE commercial_reservation.payment_proof_file DROP CONSTRAINT fk_payment_proof_file_payment_attempt,
    ADD CONSTRAINT fk_payment_proof_file_payment_attempt FOREIGN KEY (tenant_id, payment_attempt_id) REFERENCES commercial_reservation.payment_attempt (tenant_id, payment_attempt_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.payment_proof_file VALIDATE CONSTRAINT fk_payment_proof_file_payment_attempt;
ALTER TABLE commercial_reservation.capacity_allocation DROP CONSTRAINT fk_capacity_allocation_reservation,
    ADD CONSTRAINT fk_capacity_allocation_reservation FOREIGN KEY (tenant_id, reservation_id) REFERENCES commercial_reservation.reservation (tenant_id, reservation_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.capacity_allocation VALIDATE CONSTRAINT fk_capacity_allocation_reservation;
ALTER TABLE commercial_reservation.payment_condition DROP CONSTRAINT fk_payment_condition_service,
    ADD CONSTRAINT fk_payment_condition_service FOREIGN KEY (tenant_id, service_id) REFERENCES commercial_reservation.catalog_service (tenant_id, service_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.payment_condition VALIDATE CONSTRAINT fk_payment_condition_service;
ALTER TABLE commercial_reservation.payment_deadline DROP CONSTRAINT fk_payment_deadline_reservation,
    ADD CONSTRAINT fk_payment_deadline_reservation FOREIGN KEY (tenant_id, reservation_id) REFERENCES commercial_reservation.reservation (tenant_id, reservation_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.payment_deadline VALIDATE CONSTRAINT fk_payment_deadline_reservation;
ALTER TABLE commercial_reservation.payment_followup DROP CONSTRAINT fk_payment_followup_reservation,
    ADD CONSTRAINT fk_payment_followup_reservation FOREIGN KEY (tenant_id, reservation_id) REFERENCES commercial_reservation.reservation (tenant_id, reservation_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.payment_followup VALIDATE CONSTRAINT fk_payment_followup_reservation;
ALTER TABLE commercial_reservation.reservation_modification DROP CONSTRAINT fk_reservation_modification_reservation,
    ADD CONSTRAINT fk_reservation_modification_reservation FOREIGN KEY (tenant_id, reservation_id) REFERENCES commercial_reservation.reservation (tenant_id, reservation_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.reservation_modification VALIDATE CONSTRAINT fk_reservation_modification_reservation;
ALTER TABLE commercial_reservation.reservation_modification DROP CONSTRAINT fk_reservation_modification_previous_service,
    ADD CONSTRAINT fk_reservation_modification_previous_service FOREIGN KEY (tenant_id, previous_service_id) REFERENCES commercial_reservation.catalog_service (tenant_id, service_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.reservation_modification VALIDATE CONSTRAINT fk_reservation_modification_previous_service;
ALTER TABLE commercial_reservation.reservation_modification DROP CONSTRAINT fk_reservation_modification_new_service,
    ADD CONSTRAINT fk_reservation_modification_new_service FOREIGN KEY (tenant_id, new_service_id) REFERENCES commercial_reservation.catalog_service (tenant_id, service_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.reservation_modification VALIDATE CONSTRAINT fk_reservation_modification_new_service;
ALTER TABLE commercial_reservation.service_change_policy DROP CONSTRAINT fk_service_change_policy_service,
    ADD CONSTRAINT fk_service_change_policy_service FOREIGN KEY (tenant_id, service_id) REFERENCES commercial_reservation.catalog_service (tenant_id, service_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.service_change_policy VALIDATE CONSTRAINT fk_service_change_policy_service;
ALTER TABLE commercial_reservation.financial_decision DROP CONSTRAINT fk_financial_decision_reservation,
    ADD CONSTRAINT fk_financial_decision_reservation FOREIGN KEY (tenant_id, reservation_id) REFERENCES commercial_reservation.reservation (tenant_id, reservation_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.financial_decision VALIDATE CONSTRAINT fk_financial_decision_reservation;
ALTER TABLE commercial_reservation.financial_decision DROP CONSTRAINT fk_financial_decision_credit_balance,
    ADD CONSTRAINT fk_financial_decision_credit_balance FOREIGN KEY (tenant_id, credit_balance_id) REFERENCES commercial_reservation.credit_balance (tenant_id, credit_balance_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.financial_decision VALIDATE CONSTRAINT fk_financial_decision_credit_balance;
ALTER TABLE commercial_reservation.refund_authorization DROP CONSTRAINT fk_refund_authorization_reservation,
    ADD CONSTRAINT fk_refund_authorization_reservation FOREIGN KEY (tenant_id, reservation_id) REFERENCES commercial_reservation.reservation (tenant_id, reservation_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.refund_authorization VALIDATE CONSTRAINT fk_refund_authorization_reservation;
ALTER TABLE commercial_reservation.refund_authorization DROP CONSTRAINT fk_refund_authorization_decision,
    ADD CONSTRAINT fk_refund_authorization_decision FOREIGN KEY (tenant_id, financial_decision_id) REFERENCES commercial_reservation.financial_decision (tenant_id, financial_decision_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.refund_authorization VALIDATE CONSTRAINT fk_refund_authorization_decision;
ALTER TABLE commercial_reservation.credit_balance DROP CONSTRAINT fk_credit_balance_reservation,
    ADD CONSTRAINT fk_credit_balance_reservation FOREIGN KEY (tenant_id, source_reservation_id) REFERENCES commercial_reservation.reservation (tenant_id, reservation_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.credit_balance VALIDATE CONSTRAINT fk_credit_balance_reservation;
ALTER TABLE commercial_reservation.credit_balance DROP CONSTRAINT fk_credit_balance_decision,
    ADD CONSTRAINT fk_credit_balance_decision FOREIGN KEY (tenant_id, source_financial_decision_id) REFERENCES commercial_reservation.financial_decision (tenant_id, financial_decision_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.credit_balance VALIDATE CONSTRAINT fk_credit_balance_decision;
ALTER TABLE commercial_reservation.credit_balance DROP CONSTRAINT fk_credit_balance_payment_attempt,
    ADD CONSTRAINT fk_credit_balance_payment_attempt FOREIGN KEY (tenant_id, source_payment_attempt_id) REFERENCES commercial_reservation.payment_attempt (tenant_id, payment_attempt_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.credit_balance VALIDATE CONSTRAINT fk_credit_balance_payment_attempt;
ALTER TABLE commercial_reservation.credit_balance_application DROP CONSTRAINT fk_credit_balance_application_credit,
    ADD CONSTRAINT fk_credit_balance_application_credit FOREIGN KEY (tenant_id, credit_balance_id) REFERENCES commercial_reservation.credit_balance (tenant_id, credit_balance_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.credit_balance_application VALIDATE CONSTRAINT fk_credit_balance_application_credit;
ALTER TABLE commercial_reservation.credit_balance_application DROP CONSTRAINT fk_credit_balance_application_reservation,
    ADD CONSTRAINT fk_credit_balance_application_reservation FOREIGN KEY (tenant_id, target_reservation_id) REFERENCES commercial_reservation.reservation (tenant_id, reservation_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.credit_balance_application VALIDATE CONSTRAINT fk_credit_balance_application_reservation;
ALTER TABLE commercial_reservation.sensitive_data_deletion DROP CONSTRAINT fk_sensitive_data_deletion_reservation,
    ADD CONSTRAINT fk_sensitive_data_deletion_reservation FOREIGN KEY (tenant_id, reservation_id) REFERENCES commercial_reservation.reservation (tenant_id, reservation_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.sensitive_data_deletion VALIDATE CONSTRAINT fk_sensitive_data_deletion_reservation;
ALTER TABLE commercial_reservation.sensitive_data_deletion DROP CONSTRAINT fk_sensitive_data_deletion_customer,
    ADD CONSTRAINT fk_sensitive_data_deletion_customer FOREIGN KEY (tenant_id, customer_id) REFERENCES commercial_reservation.customer (tenant_id, customer_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.sensitive_data_deletion VALIDATE CONSTRAINT fk_sensitive_data_deletion_customer;
ALTER TABLE commercial_reservation.rescheduling_episode DROP CONSTRAINT fk_rescheduling_episode_reservation,
    ADD CONSTRAINT fk_rescheduling_episode_reservation FOREIGN KEY (tenant_id, reservation_id) REFERENCES commercial_reservation.reservation (tenant_id, reservation_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.rescheduling_episode VALIDATE CONSTRAINT fk_rescheduling_episode_reservation;
ALTER TABLE commercial_reservation.rescheduling_proposal DROP CONSTRAINT fk_rescheduling_proposal_episode,
    ADD CONSTRAINT fk_rescheduling_proposal_episode FOREIGN KEY (tenant_id, rescheduling_episode_id) REFERENCES commercial_reservation.rescheduling_episode (tenant_id, rescheduling_episode_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.rescheduling_proposal VALIDATE CONSTRAINT fk_rescheduling_proposal_episode;
ALTER TABLE commercial_reservation.rescheduling_proposal DROP CONSTRAINT fk_rescheduling_proposal_reservation,
    ADD CONSTRAINT fk_rescheduling_proposal_reservation FOREIGN KEY (tenant_id, reservation_id) REFERENCES commercial_reservation.reservation (tenant_id, reservation_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.rescheduling_proposal VALIDATE CONSTRAINT fk_rescheduling_proposal_reservation;
ALTER TABLE commercial_reservation.rescheduling_record DROP CONSTRAINT fk_rescheduling_record_episode,
    ADD CONSTRAINT fk_rescheduling_record_episode FOREIGN KEY (tenant_id, rescheduling_episode_id) REFERENCES commercial_reservation.rescheduling_episode (tenant_id, rescheduling_episode_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.rescheduling_record VALIDATE CONSTRAINT fk_rescheduling_record_episode;
ALTER TABLE commercial_reservation.rescheduling_record DROP CONSTRAINT fk_rescheduling_record_original,
    ADD CONSTRAINT fk_rescheduling_record_original FOREIGN KEY (tenant_id, original_reservation_id) REFERENCES commercial_reservation.reservation (tenant_id, reservation_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.rescheduling_record VALIDATE CONSTRAINT fk_rescheduling_record_original;
ALTER TABLE commercial_reservation.rescheduling_record DROP CONSTRAINT fk_rescheduling_record_linked,
    ADD CONSTRAINT fk_rescheduling_record_linked FOREIGN KEY (tenant_id, linked_reservation_id) REFERENCES commercial_reservation.reservation (tenant_id, reservation_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.rescheduling_record VALIDATE CONSTRAINT fk_rescheduling_record_linked;
ALTER TABLE commercial_reservation.associated_establishment_change DROP CONSTRAINT fk_associated_establishment_change_association,
    ADD CONSTRAINT fk_associated_establishment_change_association FOREIGN KEY (tenant_id, association_id) REFERENCES commercial_reservation.associated_establishment (tenant_id, association_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.associated_establishment_change VALIDATE CONSTRAINT fk_associated_establishment_change_association;
ALTER TABLE commercial_reservation.outbox_event DROP CONSTRAINT fk_outbox_event_service,
    ADD CONSTRAINT fk_outbox_event_service FOREIGN KEY (tenant_id, service_id) REFERENCES commercial_reservation.catalog_service (tenant_id, service_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.outbox_event VALIDATE CONSTRAINT fk_outbox_event_service;
ALTER TABLE commercial_reservation.outbox_event DROP CONSTRAINT fk_outbox_event_association,
    ADD CONSTRAINT fk_outbox_event_association FOREIGN KEY (tenant_id, association_id) REFERENCES commercial_reservation.associated_establishment (tenant_id, association_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.outbox_event VALIDATE CONSTRAINT fk_outbox_event_association;
ALTER TABLE commercial_reservation.outbox_event DROP CONSTRAINT fk_outbox_event_discount_rule,
    ADD CONSTRAINT fk_outbox_event_discount_rule FOREIGN KEY (tenant_id, discount_rule_id) REFERENCES commercial_reservation.discount_rule (tenant_id, discount_rule_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.outbox_event VALIDATE CONSTRAINT fk_outbox_event_discount_rule;
ALTER TABLE commercial_reservation.outbox_event DROP CONSTRAINT fk_outbox_event_customer,
    ADD CONSTRAINT fk_outbox_event_customer FOREIGN KEY (tenant_id, customer_id) REFERENCES commercial_reservation.customer (tenant_id, customer_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.outbox_event VALIDATE CONSTRAINT fk_outbox_event_customer;
ALTER TABLE commercial_reservation.outbox_event DROP CONSTRAINT fk_outbox_event_reservation,
    ADD CONSTRAINT fk_outbox_event_reservation FOREIGN KEY (tenant_id, reservation_id) REFERENCES commercial_reservation.reservation (tenant_id, reservation_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.outbox_event VALIDATE CONSTRAINT fk_outbox_event_reservation;
ALTER TABLE commercial_reservation.salida_capacity DROP CONSTRAINT fk_salida_capacity_service,
    ADD CONSTRAINT fk_salida_capacity_service FOREIGN KEY (tenant_id, service_id) REFERENCES commercial_reservation.catalog_service (tenant_id, service_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.salida_capacity VALIDATE CONSTRAINT fk_salida_capacity_service;
ALTER TABLE commercial_reservation.associated_establishment_image DROP CONSTRAINT fk_associated_establishment_image_association,
    ADD CONSTRAINT fk_associated_establishment_image_association FOREIGN KEY (tenant_id, association_id) REFERENCES commercial_reservation.associated_establishment (tenant_id, association_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.associated_establishment_image VALIDATE CONSTRAINT fk_associated_establishment_image_association;
ALTER TABLE commercial_reservation.reservation_companion DROP CONSTRAINT fk_reservation_companion_reservation,
    ADD CONSTRAINT fk_reservation_companion_reservation FOREIGN KEY (tenant_id, reservation_id) REFERENCES commercial_reservation.reservation (tenant_id, reservation_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.reservation_companion VALIDATE CONSTRAINT fk_reservation_companion_reservation;
ALTER TABLE commercial_reservation.reservation_additional_discount DROP CONSTRAINT fk_reservation_additional_discount_reservation,
    ADD CONSTRAINT fk_reservation_additional_discount_reservation FOREIGN KEY (tenant_id, reservation_id) REFERENCES commercial_reservation.reservation (tenant_id, reservation_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.reservation_additional_discount VALIDATE CONSTRAINT fk_reservation_additional_discount_reservation;
ALTER TABLE commercial_reservation.cancellation_penalty_policy DROP CONSTRAINT fk_cancellation_penalty_policy_service,
    ADD CONSTRAINT fk_cancellation_penalty_policy_service FOREIGN KEY (tenant_id, service_id) REFERENCES commercial_reservation.catalog_service (tenant_id, service_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE commercial_reservation.cancellation_penalty_policy VALIDATE CONSTRAINT fk_cancellation_penalty_policy_service;
