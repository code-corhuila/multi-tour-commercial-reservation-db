#!/usr/bin/env bash
# Sourced by db-ci.sh after refund-authorization-checks.sh, on the same disposable PostgreSQL instance, with every changeset of HU-COM-016 applied.
# HU-COM-016 -db (issue multi-tour-docs#182), plan D-04 to D-06, slice 2: the two guards, the one-treatment-decision unique key, the indexes, the
# no-delete rule, the tenant isolation, the idempotency key and the RefundAuthorized key list of the outbox. Probes are written first: red before the
# changesets, green after (Annex J.1). The rows of the probes are removed by the postgres owner at the end.
rg_t_fd="$SCHEMA.financial_decision"; rg_t_ra="$SCHEMA.refund_authorization"; rg_ob="$SCHEMA.outbox_event"
rg_tenant_b="00000000-0000-0000-0000-000000000002"
rg_cust="$(aid 5501)"; rg_cust_b="$(aid 5502)"; rg_svc="$(aid 5503)"
rg_res1="$(aid 5510)"; rg_res2="$(aid 5511)"; rg_res3="$(aid 5512)"; rg_res_b="$(aid 5513)"
rg_d1="$(aid 5520)"; rg_d2="$(aid 5521)"; rg_d_b="$(aid 5522)"
rg_r1="$(aid 5530)"; rg_r2="$(aid 5531)"; rg_r3="$(aid 5532)"; rg_r_b="$(aid 5533)"
rg_mv="$(aid 5540)"
rg_sql() { sql "$1" 2>/dev/null || true; }
rg_refusal() { # SQL, text of the engine answer, description
  local answer
  answer="$(engine "$1" 2>&1 || true)"; printf '%s\n' "$answer"
  check "HU-COM-016 db: $3 is refused by $2" "$(printf '%s\n' "$answer" | grep -q "$2"; echo $?)"
}
rg_accepted() { # SQL, description
  local status=0
  engine "$1" >/dev/null || status=$?
  check "HU-COM-016 db: $2 is accepted" "$status"
}
rg_explain() { printf '%s\n' 'set enable_seqscan = off;' "explain $1;" | docker exec -i -e PGPASSWORD "$container" psql -X -U postgres -d postgres 2>&1 || true; }
rg_event() { # payload (SQL literal), then column/value pairs that replace the defaults
  local -A v=([reservation_id]="'$rg_res3'" [event_type]="'RefundAuthorized'" [actor_id]="'$actor'")
  while [ $# -ge 2 ]; do v[$1]="$2"; shift 2; done
  echo "insert into $rg_ob (tenant_id, event_type, reservation_id, actor_id, occurred_at, payload) values ('$tenant', ${v[event_type]}, ${v[reservation_id]}, ${v[actor_id]}, now(), $payload)"
}
rg_set_ra() { echo "update $rg_t_ra set $2 where refund_authorization_id = '$1'"; }
rg_set_fd() { echo "update $rg_t_fd set $2 where financial_decision_id = '$1'"; }

echo 'HU-COM-016 db slice 2 - the probe rows'
sql "insert into $SCHEMA.customer (customer_id, tenant_id, full_name, created_at, document_number, birth_date_or_age, contact_info, status, terms_accepted, terms_accepted_at) values ('$rg_cust', '$tenant', 'Guard probe A', now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE', true, now()), ('$rg_cust_b', '$rg_tenant_b', 'Guard probe B', now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE', true, now());
     insert into $SCHEMA.catalog_service (service_id, tenant_id, service_type, commercial_name, catalog_status, base_rate_cents, base_operational_cost_cents, configured_capacity, transport_required, high_risk, created_at, updated_at) values ('$rg_svc', '$tenant', 'TOUR', 'Guard probe tour', 'ACTIVE', 150000, 90000, 12, false, false, now(), now())" >/dev/null 2>&1 || true
engine "$(for r in "$rg_res1" "$rg_res2" "$rg_res3"; do rs_row reservation_id "'$r'" customer_id "'$rg_cust'" service_id "'$rg_svc'"; echo ';'; done) $(rs_row reservation_id "'$rg_res_b'" tenant_id "'$rg_tenant_b'" customer_id "'$rg_cust_b'" service_id "'$rg_svc'");" >/dev/null || true
engine "$(fd_row financial_decision_id "'$rg_d1'" reservation_id "'$rg_res1'"); $(fd_row financial_decision_id "'$rg_d2'" reservation_id "'$rg_res2'" decision_kind "'PENDING_TREATMENT'" penalty_amount_cents NULL); $(fd_row financial_decision_id "'$rg_d_b'" tenant_id "'$rg_tenant_b'" reservation_id "'$rg_res_b'");" >/dev/null || true
check 'the probe reservations and the two open decisions exist' "$([ "$(rg_sql "select count(*) from $SCHEMA.reservation where reservation_id in ('$rg_res1','$rg_res2','$rg_res3','$rg_res_b')")" = 4 ] && [ "$(rg_sql "select count(*) from $rg_t_fd where financial_decision_id in ('$rg_d1','$rg_d2','$rg_d_b')")" = 3 ]; echo $?)"

echo 'aDecidedDecisionCannotChangeAndAnOpenOneChangesOnlyItsAmountsAndFreeze (AC-D16.6)'
rg_accepted "$(rg_set_fd "$rg_d1" "base_amount_cents = 120000, penalty_amount_cents = 30000")" 'a late value that raises the base amount and the penalty of an open decision'
rg_accepted "$(rg_set_fd "$rg_d1" "frozen_at = now(), remaining_at_freeze_minutes = 600")" 'the freeze of an open decision'
rg_accepted "$(rg_set_fd "$rg_d1" "frozen_at = NULL, remaining_at_freeze_minutes = NULL")" 'the resume of a frozen decision'
rg_refusal "$(rg_set_fd "$rg_d1" "decision_kind = 'MODIFICATION_EXCESS', penalty_amount_cents = NULL");" trg_financial_decision_guard 'the change of kind of an open decision'
rg_refusal "$(rg_set_fd "$rg_d1" "recognized_at = now() + interval '1 day'");" trg_financial_decision_guard 'the change of the recognition instant'
rg_refusal "$(rg_set_fd "$rg_d1" "reservation_id = '$rg_res2'");" trg_financial_decision_guard 'the move of a decision to another reservation'
rg_accepted "$(rg_set_fd "$rg_d1" "outcome = 'REFUND_FULL', decided_by_system = false, decided_by = '$actor', decided_at = now()")" 'the recording of the outcome by the administrator'
rg_refusal "$(rg_set_fd "$rg_d1" "base_amount_cents = 1");" trg_financial_decision_guard 'the change of the amount of a decided decision'
rg_refusal "$(rg_set_fd "$rg_d1" "outcome = 'CREDIT_FULL'");" trg_financial_decision_guard 'the change of the outcome of a decided decision'
rg_refusal "$(rg_set_fd "$rg_d1" "frozen_at = now(), remaining_at_freeze_minutes = 5");" trg_financial_decision_guard 'the freeze of a decided decision'

echo 'onlyOneTreatmentDecisionPerReservationAndKind (AC-D16.7)'
rg_refusal "$(fd_row reservation_id "'$rg_res1'");" uq_financial_decision_treatment_reservation 'a second customer-cancellation decision for the same reservation'
rg_refusal "$(fd_row reservation_id "'$rg_res2'" decision_kind "'PENDING_TREATMENT'" penalty_amount_cents NULL);" uq_financial_decision_treatment_reservation 'a second pending-treatment decision for the same reservation'
rg_accepted "$(fd_row reservation_id "'$rg_res2'" decision_kind "'MODIFICATION_EXCESS'" penalty_amount_cents NULL); $(fd_row reservation_id "'$rg_res2'" decision_kind "'MODIFICATION_EXCESS'" penalty_amount_cents NULL)" 'two modification-excess decisions for one reservation'
rg_accepted "$(fd_row reservation_id "'$rg_res3'" decision_kind "'CREDIT_BALANCE_REFUND_REQUEST'" credit_balance_id "'$(aid 5550)'" penalty_amount_cents NULL); $(fd_row reservation_id "'$rg_res3'" decision_kind "'CREDIT_BALANCE_REFUND_REQUEST'" credit_balance_id "'$(aid 5551)'" penalty_amount_cents NULL)" 'two credit-balance refund requests for one reservation'

echo 'onlyTheForwardStepsAndTheUndoAreAccepted (AC-D16.11)'
engine "$(ra_row refund_authorization_id "'$rg_r1'" reservation_id "'$rg_res1'" financial_decision_id "'$rg_d1'"); $(ra_row refund_authorization_id "'$rg_r2'" reservation_id "'$rg_res1'" financial_decision_id "'$rg_d1'"); $(ra_row refund_authorization_id "'$rg_r3'" reservation_id "'$rg_res1'" financial_decision_id "'$rg_d1'"); $(ra_row refund_authorization_id "'$rg_r_b'" tenant_id "'$rg_tenant_b'" reservation_id "'$rg_res_b'" financial_decision_id "'$rg_d_b'");" >/dev/null || true
check 'the four probe refunds exist in the state AUTHORIZED' "$([ "$(rg_sql "select count(*) from $rg_t_ra where refund_authorization_id in ('$rg_r1','$rg_r2','$rg_r3','$rg_r_b') and execution_state = 'AUTHORIZED'")" = 4 ]; echo $?)"
rg_exec="execution_state = 'EXECUTING', executing_at = now(), executed_by = '$actor', outflow_method = 'TRANSFER'"
rg_done="execution_state = 'EXECUTED', executed_at = now(), cash_movement_id = '$rg_mv'"
rg_refusal "$(rg_set_ra "$rg_r1" "execution_state = 'EXECUTED', executing_at = now(), executed_by = '$actor', outflow_method = 'TRANSFER', executed_at = now(), cash_movement_id = '$rg_mv'");" trg_refund_authorization_guard 'AUTHORIZED straight to EXECUTED'
rg_refusal "$(rg_set_ra "$rg_r1" "authorized_amount_cents = 90000");" trg_refund_authorization_guard 'the change of the authorized amount'
rg_refusal "$(rg_set_ra "$rg_r1" "reason = 'Another reason'");" trg_refund_authorization_guard 'the change of the reason'
rg_refusal "$(rg_set_ra "$rg_r1" "execution_due_at = now() + interval '30 days'");" trg_refund_authorization_guard 'the change of the due instant'
rg_accepted "$(rg_set_ra "$rg_r1" "$rg_exec")" 'AUTHORIZED to EXECUTING'
rg_accepted "$(rg_set_ra "$rg_r1" "execution_state = 'AUTHORIZED', executing_at = NULL, executed_by = NULL, outflow_method = NULL")" 'the undo EXECUTING to AUTHORIZED'
rg_accepted "$(rg_set_ra "$rg_r1" "$rg_exec")" 'EXECUTING again after the undo'
rg_accepted "$(rg_set_ra "$rg_r1" "$rg_done")" 'EXECUTING to EXECUTED with the cash movement'
rg_refusal "$(rg_set_ra "$rg_r1" "execution_state = 'AUTHORIZED', executing_at = NULL, executed_by = NULL, outflow_method = NULL, executed_at = NULL, cash_movement_id = NULL");" trg_refund_authorization_guard 'the reopening of an executed refund'
rg_refusal "$(rg_set_ra "$rg_r1" "cash_movement_id = '$(aid 5541)'");" trg_refund_authorization_guard 'another movement on an executed refund'
rg_accepted "$(rg_set_ra "$rg_r2" "overdue_marked_at = now()")" 'the overdue mark on an authorized refund'
rg_refusal "$(rg_set_ra "$rg_r2" "overdue_marked_at = now() + interval '1 hour'");" trg_refund_authorization_guard 'a second overdue mark'
rg_refusal "$(rg_set_ra "$rg_r2" "overdue_marked_at = NULL");" trg_refund_authorization_guard 'the removal of the overdue mark'
rg_accepted "$(rg_set_ra "$rg_r3" "$rg_exec")" 'a third refund executing'
rg_refusal "$(rg_set_ra "$rg_r3" "$rg_done, overdue_marked_at = now()");" trg_refund_authorization_guard 'the overdue mark written on the step that executes the refund'

echo 'aReservationWithADecisionOrARefundCannotBeDeleted and anExecutedRefundCannotChangeAndNothingIsDeleted (AC-D16.12)'
rg_refusal "delete from $rg_t_fd where financial_decision_id = '$rg_d1';" 'permission denied for table financial_decision' 'the delete of a decision by the application user'
rg_refusal "delete from $rg_t_ra where refund_authorization_id = '$rg_r1';" 'permission denied for table refund_authorization' 'the delete of a refund by the application user'
rg_refusal "delete from $SCHEMA.reservation where reservation_id = '$rg_res1';" 'permission denied for table reservation' 'the delete of a reservation by the application user'
rg_fk="$(engine "delete from $SCHEMA.reservation where reservation_id = '$rg_res1';" postgres 2>&1 || true)"; printf '%s\n' "$rg_fk"
check 'HU-COM-016 db: the owner cannot delete a reservation that has a decision or a refund (a RESTRICT key)' "$(printf '%s\n' "$rg_fk" | grep -q 'violates foreign key constraint'; echo $?)"
check 'neither the decision nor the refund tables grant DELETE to the writer or the application user' "$([ "$(rg_sql "select count(*) from information_schema.role_table_grants where table_schema='$SCHEMA' and table_name in ('financial_decision','refund_authorization') and privilege_type = 'DELETE'")" = 0 ]; echo $?)"

echo 'decisionsAndRefundsNeverCrossTenants, theReadsUseTheirIndexes, theSameKeyTwiceIsRefusedPerTenant (AC-D16.13, AC-D16.14)'
check 'a read scoped to the first tenant returns no decision or refund of the second' "$([ "$(rg_sql "select count(*) from $rg_t_fd where tenant_id = '$tenant' and financial_decision_id = '$rg_d_b'")" = 0 ] && [ "$(rg_sql "select count(*) from $rg_t_ra where tenant_id = '$tenant' and refund_authorization_id = '$rg_r_b'")" = 0 ] && [ "$(rg_sql "select count(*) from $rg_t_ra where tenant_id = '$rg_tenant_b'")" -ge 1 ]; echo $?)"
rg_p1="$(rg_explain "select 1 from $rg_t_fd where tenant_id = '$tenant' and outcome is null and frozen_at is null and recognized_at < now()")"; printf '%s\n' "$rg_p1"
check 'the due decisions use idx_financial_decision_tenant_due' "$(printf '%s\n' "$rg_p1" | grep -q 'idx_financial_decision_tenant_due'; echo $?)"
rg_p2="$(rg_explain "select 1 from $rg_t_ra where tenant_id = '$tenant' and reservation_id = '$rg_res1'")"; printf '%s\n' "$rg_p2"
check 'the refunds of one reservation use idx_refund_authorization_tenant_reservation' "$(printf '%s\n' "$rg_p2" | grep -q 'idx_refund_authorization_tenant_reservation'; echo $?)"
rg_p3="$(rg_explain "select 1 from $rg_t_ra where tenant_id = '$tenant' and execution_state <> 'EXECUTED' and overdue_marked_at is null and execution_due_at < now()")"; printf '%s\n' "$rg_p3"
check 'the open refunds use idx_refund_authorization_tenant_due' "$(printf '%s\n' "$rg_p3" | grep -q 'idx_refund_authorization_tenant_due'; echo $?)"
rg_key="insert into $SCHEMA.idempotency_key (key, tenant_id, resource_type, resource_id) values ('refund-authorization-key-1', '$tenant', 'refund_authorization', '$rg_r1')"
rg_accepted "$rg_key" 'the first registration of an authorization key'
rg_refusal "$rg_key;" pk_idempotency_key 'the same key of the same tenant twice'
rg_accepted "insert into $SCHEMA.idempotency_key (key, tenant_id, resource_type, resource_id) values ('refund-authorization-key-1', '$rg_tenant_b', 'refund_authorization', '$rg_r_b')" 'the same key in another tenant'

echo 'theOutboxAcceptsRefundAuthorizedWithItsSixKeysOnly (AC-D16.15)'
rg_pay='{"refundAuthorizationId":"x","reservationId":"y","amountCents":80000,"origin":"CUSTOMER_CANCELLATION","authorizationMode":"TENANT_ADMINISTRATOR","authorizedBy":"z"}'
rg_accepted "$(rg_event "'$rg_pay'::jsonb")" 'RefundAuthorized with exactly its six keys'
rg_accepted "$(rg_event "'{\"refundAuthorizationId\":\"x\",\"reservationId\":\"y\",\"amountCents\":80000,\"origin\":\"NOT_ATTRIBUTABLE_TO_CUSTOMER\",\"authorizationMode\":\"AUTOMATIC_DETERMINATION\",\"authorizedBy\":null}'::jsonb" actor_id NULL)" 'RefundAuthorized of an automatic determination with no author and no actor'
rg_refusal "$(rg_event "'{\"refundAuthorizationId\":\"x\",\"reservationId\":\"y\",\"amountCents\":80000,\"origin\":\"CUSTOMER_CANCELLATION\",\"authorizationMode\":\"TENANT_ADMINISTRATOR\",\"authorizedBy\":\"z\",\"reason\":\"free text\"}'::jsonb");" chk_outbox_event_payload_keys_refund_authorized 'RefundAuthorized with a seventh key'
rg_refusal "$(rg_event "'{\"refundAuthorizationId\":\"x\",\"reservationId\":\"y\",\"amountCents\":80000,\"origin\":\"CUSTOMER_CANCELLATION\",\"authorizationMode\":\"TENANT_ADMINISTRATOR\"}'::jsonb");" chk_outbox_event_payload_keys_refund_authorized 'RefundAuthorized with a missing key'
rg_refusal "$(rg_event NULL);" chk_outbox_event_payload 'RefundAuthorized without payload'
rg_refusal "$(rg_event "'$rg_pay'::jsonb" reservation_id NULL);" chk_outbox_event_exactly_one_aggregate 'RefundAuthorized without a reservation'
rg_refusal "$(rg_event "'$rg_pay'::jsonb" actor_id NULL event_type "'CapacityReleased'");" chk_outbox_event_actor_required 'an event of an earlier story without actor'
rg_accepted "$(rg_event "'{\"reservationId\":\"x\",\"cause\":\"PAYMENT_EXPIRY\",\"releasedSeats\":2}'::jsonb" event_type "'ReservationCancelled'")" 'ReservationCancelled of an earlier story keeps its key list'
rg_refusal "$(rg_event "'{\"reservationId\":\"x\",\"cause\":\"PAYMENT_EXPIRY\"}'::jsonb" event_type "'ReservationCancelled'");" chk_outbox_event_payload_keys_reservation_cancelled 'ReservationCancelled with a missing key'
rg_accepted "$(rg_event "'{\"customerId\":\"c\",\"notificationType\":\"PROOF_APPROVED\",\"triggeringEventType\":\"PaymentValidated\",\"triggeringEventId\":\"$(aid 5560)\"}'::jsonb" event_type "'ClientNotified'")" 'ClientNotified of an earlier story is still accepted'

echo 'structure of slice 2'
check 'AC-D16.1 the two guards and their two BEFORE UPDATE row triggers exist' "$([ "$(rg_sql "select count(*) from pg_proc where pronamespace='$SCHEMA'::regnamespace and proname in ('fn_financial_decision_guard','fn_refund_authorization_guard')")" = 2 ] && [ "$(rg_sql "select count(*) from pg_trigger where not tgisinternal and tgname in ('trg_financial_decision_guard','trg_refund_authorization_guard') and (tgtype & 1) = 1 and (tgtype & 2) = 2 and (tgtype & 16) = 16")" = 2 ]; echo $?)"
check 'AC-D16.1 the unique key and the three indexes exist and lead with tenant_id' "$([ "$(rg_sql "select count(*) from pg_indexes where schemaname='$SCHEMA' and indexname in ('uq_financial_decision_treatment_reservation','idx_financial_decision_tenant_due','idx_refund_authorization_tenant_reservation','idx_refund_authorization_tenant_due') and indexdef like '%(tenant_id,%'")" = 4 ]; echo $?)"

sql "delete from $rg_ob where reservation_id in ('$rg_res3') or payload ->> 'refundAuthorizationId' = 'x'; delete from $SCHEMA.idempotency_key where key = 'refund-authorization-key-1'; delete from $rg_t_ra where reservation_id in ('$rg_res1','$rg_res2','$rg_res3','$rg_res_b'); delete from $rg_t_fd where reservation_id in ('$rg_res1','$rg_res2','$rg_res3','$rg_res_b'); delete from $SCHEMA.reservation where reservation_id in ('$rg_res1','$rg_res2','$rg_res3','$rg_res_b'); delete from $SCHEMA.catalog_service where service_id = '$rg_svc'; delete from $SCHEMA.customer where customer_id in ('$rg_cust','$rg_cust_b')" >/dev/null 2>&1 || true
check 'the rows of the probes are gone' "$([ "$(sql "select (select count(*) from $rg_t_ra) + (select count(*) from $rg_t_fd) + (select count(*) from $SCHEMA.reservation where reservation_id in ('$rg_res1','$rg_res2','$rg_res3','$rg_res_b'))")" = 0 ]; echo $?)"
