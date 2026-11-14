-- DD-11 and DD-7: the simple foreign keys as they were before 050. A key is restored on the key column alone, so the revert needs no data and never fails.
ALTER TABLE commercial_reservation.customer_sensitive_data DROP CONSTRAINT fk_customer_sensitive_data_customer,
    ADD CONSTRAINT fk_customer_sensitive_data_customer FOREIGN KEY (customer_id) REFERENCES commercial_reservation.customer (customer_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.reservation_companion_sensitive_data DROP CONSTRAINT fk_reservation_companion_sensitive_data_companion,
    ADD CONSTRAINT fk_reservation_companion_sensitive_data_companion FOREIGN KEY (reservation_companion_id) REFERENCES commercial_reservation.reservation_companion (reservation_companion_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.discount_rule_service DROP CONSTRAINT fk_discount_rule_service_rule,
    ADD CONSTRAINT fk_discount_rule_service_rule FOREIGN KEY (discount_rule_id) REFERENCES commercial_reservation.discount_rule (discount_rule_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.discount_rule_service DROP CONSTRAINT fk_discount_rule_service_service,
    ADD CONSTRAINT fk_discount_rule_service_service FOREIGN KEY (service_id) REFERENCES commercial_reservation.catalog_service (service_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.reservation DROP CONSTRAINT fk_reservation_customer,
    ADD CONSTRAINT fk_reservation_customer FOREIGN KEY (customer_id) REFERENCES commercial_reservation.customer (customer_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.reservation DROP CONSTRAINT fk_reservation_service,
    ADD CONSTRAINT fk_reservation_service FOREIGN KEY (service_id) REFERENCES commercial_reservation.catalog_service (service_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.reserved_service DROP CONSTRAINT fk_reserved_service_reservation,
    ADD CONSTRAINT fk_reserved_service_reservation FOREIGN KEY (reservation_id) REFERENCES commercial_reservation.reservation (reservation_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.reserved_service DROP CONSTRAINT fk_reserved_service_service,
    ADD CONSTRAINT fk_reserved_service_service FOREIGN KEY (service_id) REFERENCES commercial_reservation.catalog_service (service_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.reservation_fixed_discount DROP CONSTRAINT fk_reservation_fixed_discount_reservation,
    ADD CONSTRAINT fk_reservation_fixed_discount_reservation FOREIGN KEY (reservation_id) REFERENCES commercial_reservation.reservation (reservation_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.reservation_fixed_discount DROP CONSTRAINT fk_reservation_fixed_discount_rule,
    ADD CONSTRAINT fk_reservation_fixed_discount_rule FOREIGN KEY (discount_rule_id) REFERENCES commercial_reservation.discount_rule (discount_rule_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.payment_attempt DROP CONSTRAINT fk_payment_attempt_reservation,
    ADD CONSTRAINT fk_payment_attempt_reservation FOREIGN KEY (reservation_id) REFERENCES commercial_reservation.reservation (reservation_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.payment_proof_file DROP CONSTRAINT fk_payment_proof_file_payment_attempt,
    ADD CONSTRAINT fk_payment_proof_file_payment_attempt FOREIGN KEY (payment_attempt_id) REFERENCES commercial_reservation.payment_attempt (payment_attempt_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.capacity_allocation DROP CONSTRAINT fk_capacity_allocation_reservation,
    ADD CONSTRAINT fk_capacity_allocation_reservation FOREIGN KEY (reservation_id) REFERENCES commercial_reservation.reservation (reservation_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.payment_condition DROP CONSTRAINT fk_payment_condition_service,
    ADD CONSTRAINT fk_payment_condition_service FOREIGN KEY (service_id) REFERENCES commercial_reservation.catalog_service (service_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.payment_deadline DROP CONSTRAINT fk_payment_deadline_reservation,
    ADD CONSTRAINT fk_payment_deadline_reservation FOREIGN KEY (reservation_id) REFERENCES commercial_reservation.reservation (reservation_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.payment_followup DROP CONSTRAINT fk_payment_followup_reservation,
    ADD CONSTRAINT fk_payment_followup_reservation FOREIGN KEY (reservation_id) REFERENCES commercial_reservation.reservation (reservation_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.reservation_modification DROP CONSTRAINT fk_reservation_modification_reservation,
    ADD CONSTRAINT fk_reservation_modification_reservation FOREIGN KEY (reservation_id) REFERENCES commercial_reservation.reservation (reservation_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.reservation_modification DROP CONSTRAINT fk_reservation_modification_previous_service,
    ADD CONSTRAINT fk_reservation_modification_previous_service FOREIGN KEY (previous_service_id) REFERENCES commercial_reservation.catalog_service (service_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.reservation_modification DROP CONSTRAINT fk_reservation_modification_new_service,
    ADD CONSTRAINT fk_reservation_modification_new_service FOREIGN KEY (new_service_id) REFERENCES commercial_reservation.catalog_service (service_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.service_change_policy DROP CONSTRAINT fk_service_change_policy_service,
    ADD CONSTRAINT fk_service_change_policy_service FOREIGN KEY (service_id) REFERENCES commercial_reservation.catalog_service (service_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.financial_decision DROP CONSTRAINT fk_financial_decision_reservation,
    ADD CONSTRAINT fk_financial_decision_reservation FOREIGN KEY (reservation_id) REFERENCES commercial_reservation.reservation (reservation_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.financial_decision DROP CONSTRAINT fk_financial_decision_credit_balance,
    ADD CONSTRAINT fk_financial_decision_credit_balance FOREIGN KEY (credit_balance_id) REFERENCES commercial_reservation.credit_balance (credit_balance_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.refund_authorization DROP CONSTRAINT fk_refund_authorization_reservation,
    ADD CONSTRAINT fk_refund_authorization_reservation FOREIGN KEY (reservation_id) REFERENCES commercial_reservation.reservation (reservation_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.refund_authorization DROP CONSTRAINT fk_refund_authorization_decision,
    ADD CONSTRAINT fk_refund_authorization_decision FOREIGN KEY (financial_decision_id) REFERENCES commercial_reservation.financial_decision (financial_decision_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.credit_balance DROP CONSTRAINT fk_credit_balance_reservation,
    ADD CONSTRAINT fk_credit_balance_reservation FOREIGN KEY (source_reservation_id) REFERENCES commercial_reservation.reservation (reservation_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.credit_balance DROP CONSTRAINT fk_credit_balance_decision,
    ADD CONSTRAINT fk_credit_balance_decision FOREIGN KEY (source_financial_decision_id) REFERENCES commercial_reservation.financial_decision (financial_decision_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.credit_balance DROP CONSTRAINT fk_credit_balance_payment_attempt,
    ADD CONSTRAINT fk_credit_balance_payment_attempt FOREIGN KEY (source_payment_attempt_id) REFERENCES commercial_reservation.payment_attempt (payment_attempt_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.credit_balance_application DROP CONSTRAINT fk_credit_balance_application_credit,
    ADD CONSTRAINT fk_credit_balance_application_credit FOREIGN KEY (credit_balance_id) REFERENCES commercial_reservation.credit_balance (credit_balance_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.credit_balance_application DROP CONSTRAINT fk_credit_balance_application_reservation,
    ADD CONSTRAINT fk_credit_balance_application_reservation FOREIGN KEY (target_reservation_id) REFERENCES commercial_reservation.reservation (reservation_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.sensitive_data_deletion DROP CONSTRAINT fk_sensitive_data_deletion_reservation,
    ADD CONSTRAINT fk_sensitive_data_deletion_reservation FOREIGN KEY (reservation_id) REFERENCES commercial_reservation.reservation (reservation_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.sensitive_data_deletion DROP CONSTRAINT fk_sensitive_data_deletion_customer,
    ADD CONSTRAINT fk_sensitive_data_deletion_customer FOREIGN KEY (customer_id) REFERENCES commercial_reservation.customer (customer_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.rescheduling_episode DROP CONSTRAINT fk_rescheduling_episode_reservation,
    ADD CONSTRAINT fk_rescheduling_episode_reservation FOREIGN KEY (reservation_id) REFERENCES commercial_reservation.reservation (reservation_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.rescheduling_proposal DROP CONSTRAINT fk_rescheduling_proposal_episode,
    ADD CONSTRAINT fk_rescheduling_proposal_episode FOREIGN KEY (rescheduling_episode_id) REFERENCES commercial_reservation.rescheduling_episode (rescheduling_episode_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.rescheduling_proposal DROP CONSTRAINT fk_rescheduling_proposal_reservation,
    ADD CONSTRAINT fk_rescheduling_proposal_reservation FOREIGN KEY (reservation_id) REFERENCES commercial_reservation.reservation (reservation_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.rescheduling_record DROP CONSTRAINT fk_rescheduling_record_episode,
    ADD CONSTRAINT fk_rescheduling_record_episode FOREIGN KEY (rescheduling_episode_id) REFERENCES commercial_reservation.rescheduling_episode (rescheduling_episode_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.rescheduling_record DROP CONSTRAINT fk_rescheduling_record_original,
    ADD CONSTRAINT fk_rescheduling_record_original FOREIGN KEY (original_reservation_id) REFERENCES commercial_reservation.reservation (reservation_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.rescheduling_record DROP CONSTRAINT fk_rescheduling_record_linked,
    ADD CONSTRAINT fk_rescheduling_record_linked FOREIGN KEY (linked_reservation_id) REFERENCES commercial_reservation.reservation (reservation_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.associated_establishment_change DROP CONSTRAINT fk_associated_establishment_change_association,
    ADD CONSTRAINT fk_associated_establishment_change_association FOREIGN KEY (association_id) REFERENCES commercial_reservation.associated_establishment (association_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.outbox_event DROP CONSTRAINT fk_outbox_event_service,
    ADD CONSTRAINT fk_outbox_event_service FOREIGN KEY (service_id) REFERENCES commercial_reservation.catalog_service (service_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.outbox_event DROP CONSTRAINT fk_outbox_event_association,
    ADD CONSTRAINT fk_outbox_event_association FOREIGN KEY (association_id) REFERENCES commercial_reservation.associated_establishment (association_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.outbox_event DROP CONSTRAINT fk_outbox_event_discount_rule,
    ADD CONSTRAINT fk_outbox_event_discount_rule FOREIGN KEY (discount_rule_id) REFERENCES commercial_reservation.discount_rule (discount_rule_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.outbox_event DROP CONSTRAINT fk_outbox_event_customer,
    ADD CONSTRAINT fk_outbox_event_customer FOREIGN KEY (customer_id) REFERENCES commercial_reservation.customer (customer_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.outbox_event DROP CONSTRAINT fk_outbox_event_reservation,
    ADD CONSTRAINT fk_outbox_event_reservation FOREIGN KEY (reservation_id) REFERENCES commercial_reservation.reservation (reservation_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.salida_capacity DROP CONSTRAINT fk_salida_capacity_service,
    ADD CONSTRAINT fk_salida_capacity_service FOREIGN KEY (service_id) REFERENCES commercial_reservation.catalog_service (service_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.associated_establishment_image DROP CONSTRAINT fk_associated_establishment_image_association,
    ADD CONSTRAINT fk_associated_establishment_image_association FOREIGN KEY (association_id) REFERENCES commercial_reservation.associated_establishment (association_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.reservation_companion DROP CONSTRAINT fk_reservation_companion_reservation,
    ADD CONSTRAINT fk_reservation_companion_reservation FOREIGN KEY (reservation_id) REFERENCES commercial_reservation.reservation (reservation_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.reservation_additional_discount DROP CONSTRAINT fk_reservation_additional_discount_reservation,
    ADD CONSTRAINT fk_reservation_additional_discount_reservation FOREIGN KEY (reservation_id) REFERENCES commercial_reservation.reservation (reservation_id) ON DELETE RESTRICT;
ALTER TABLE commercial_reservation.cancellation_penalty_policy DROP CONSTRAINT fk_cancellation_penalty_policy_service,
    ADD CONSTRAINT fk_cancellation_penalty_policy_service FOREIGN KEY (service_id) REFERENCES commercial_reservation.catalog_service (service_id) ON DELETE RESTRICT;
