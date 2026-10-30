#!/usr/bin/env bash
# Sourced by db-ci.sh after the payment checks, on the same disposable PostgreSQL instance.
# HU-COM-010 -db (issue multi-tour-docs#176), plan D-02 to D-10: the review of a payment proof is columns, constraints, a guard and indexes on
# payment_attempt (HU-COM-009). 04_alter/016 (review columns and constraints), 07_functions/002 (fn_payment_attempt_guard), 09_triggers/002
# (trg_payment_attempt_guard), 10_indexes/024 (the pending list) and 04_alter/017 (key lists of four outbox payloads), all with label payment-review.
# Every changeset also carries HU-COM-010. Probes are written first: red before the changesets, green after (Annex J.1).
pr_att="$SCHEMA.payment_attempt"; pr_proof="$SCHEMA.payment_proof_file"; pr_ob="$SCHEMA.outbox_event"; pr_cap="$SCHEMA.salida_capacity"
pr_tenant_b="00000000-0000-0000-0000-000000000002"
pr_cust="$(aid 2601)"; pr_cust_b="$(aid 2602)"; pr_svc="$(aid 2603)"; pr_res="$(aid 2610)"; pr_res_b="$(aid 2611)"; pr_sal="$(aid 2612)"
pr_hash="$(printf 'b%.0s' $(seq 1 64))"
pr_sql() { sql "$1" 2>/dev/null || true; }
pr_attempt() { # attempt id, then column/value pairs (SQL literals) that replace the defaults of a transfer under validation of the first reservation
  local id="$1"; shift
  local -A v=([tenant_id]="'$tenant'" [reservation_id]="'$pr_res'" [payment_method]="'TRANSFER'" [received_amount_cents]=100000 [validation_status]="'IN_VALIDATION'" [payment_status_snapshot]="'NO_PAYMENT'" [registered_at]="now()")
  while [ $# -ge 2 ]; do v[$1]="$2"; shift 2; done
  echo "insert into $pr_att (payment_attempt_id, tenant_id, reservation_id, payment_method, received_amount_cents, validation_status, payment_status_snapshot, registered_by, registered_at) values ('$id', ${v[tenant_id]}, ${v[reservation_id]}, ${v[payment_method]}, ${v[received_amount_cents]}, ${v[validation_status]}, ${v[payment_status_snapshot]}, '$actor', ${v[registered_at]})"
}
pr_approve() { # attempt id, then column/value pairs (SQL literals) that replace the defaults of a complete approval of 100000
  local id="$1"; shift
  local -A v=([validation_status]="'APPROVED'" [decided_by]="'$actor'" [decided_at]="now()" [decision_reason]=NULL [verified_amount_cents]=100000 [applied_amount_cents]=100000 [excess_amount_cents]=0 [treatment_amount_cents]=0)
  while [ $# -ge 2 ]; do v[$1]="$2"; shift 2; done
  echo "update $pr_att set validation_status = ${v[validation_status]}, decided_by = ${v[decided_by]}, decided_at = ${v[decided_at]}, decision_reason = ${v[decision_reason]}, verified_amount_cents = ${v[verified_amount_cents]}, applied_amount_cents = ${v[applied_amount_cents]}, excess_amount_cents = ${v[excess_amount_cents]}, treatment_amount_cents = ${v[treatment_amount_cents]} where payment_attempt_id = '$id'"
}
pr_reject() { # attempt id, then column/value pairs (SQL literals) that replace the defaults of a complete rejection
  local id="$1"; shift
  local -A v=([decided_by]="'$actor'" [decided_at]="now()" [decision_reason]="'The amount does not match the transfer'" [verified_amount_cents]=NULL [applied_amount_cents]=NULL [excess_amount_cents]=NULL [treatment_amount_cents]=NULL)
  while [ $# -ge 2 ]; do v[$1]="$2"; shift 2; done
  echo "update $pr_att set validation_status = 'REJECTED', decided_by = ${v[decided_by]}, decided_at = ${v[decided_at]}, decision_reason = ${v[decision_reason]}, verified_amount_cents = ${v[verified_amount_cents]}, applied_amount_cents = ${v[applied_amount_cents]}, excess_amount_cents = ${v[excess_amount_cents]}, treatment_amount_cents = ${v[treatment_amount_cents]} where payment_attempt_id = '$id'"
}
pr_explain() { printf '%s\n' 'set enable_seqscan = off;' "explain $1;" | docker exec -i -e PGPASSWORD "$container" psql -X -U postgres -d postgres 2>&1 || true; }
pr_event() { # event type, payload (SQL literal)
  echo "insert into $pr_ob (tenant_id, event_type, reservation_id, actor_id, occurred_at, payload) values ('$tenant', '$1', '$pr_res', '$actor', now(), $2)"
}

echo 'HU-COM-010 payment review - base: the 79 changesets of HU-COM-001 to HU-COM-009'
liquibase rollback-count 999 >/dev/null
db_labels='!HU-COM-010 and !collaborator-editing-flag'
liquibase update >/dev/null
pr_base="$(snapshot)"
check 'base holds exactly 79 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 79 ]; echo $?)"
check 'T-01 precondition: payment_attempt, payment_proof_file, capacity_allocation, salida_capacity, reservation and the outbox exist' "$([ "$(sql "select count(*) from pg_tables where schemaname='$SCHEMA' and tablename in ('payment_attempt','payment_proof_file','capacity_allocation','salida_capacity','reservation','outbox_event','idempotency_key')")" = 7 ]; echo $?)"
check 'on that base the attempt has no review column and no guard exists' "$([ "$(pr_sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='payment_attempt' and column_name in ('decided_by','decided_at','decision_reason','verified_amount_cents','applied_amount_cents','excess_amount_cents','treatment_amount_cents')")" = 0 ] && [ "$(pr_sql "select count(*) from pg_proc where pronamespace='$SCHEMA'::regnamespace and proname='fn_payment_attempt_guard'")" = 0 ]; echo $?)"
sql "insert into $SCHEMA.customer (customer_id, tenant_id, full_name, created_at, document_number, birth_date_or_age, contact_info, status, terms_accepted, terms_accepted_at) values ('$pr_cust', '$tenant', 'Review probe A', now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE', true, now()), ('$pr_cust_b', '$pr_tenant_b', 'Review probe B', now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE', true, now());
     insert into $SCHEMA.catalog_service (service_id, tenant_id, service_type, commercial_name, catalog_status, base_rate_cents, base_operational_cost_cents, configured_capacity, transport_required, high_risk, created_at, updated_at) values ('$pr_svc', '$tenant', 'TOUR', 'Review probe tour', 'ACTIVE', 150000, 90000, 12, false, false, now(), now());
     insert into $pr_cap (salida_capacity_id, tenant_id, salida_id, service_id, effective_capacity, held_seats, hora_inicio, status) values (gen_random_uuid(), '$tenant', '$pr_sal', '$pr_svc', 10, 3, now() + interval '30 days', 'SCHEDULED')" >/dev/null 2>&1 || true
engine "$(rs_row reservation_id "'$pr_res'" customer_id "'$pr_cust'" service_id "'$pr_svc'"); $(rs_row reservation_id "'$pr_res_b'" tenant_id "'$pr_tenant_b'" customer_id "'$pr_cust_b'" service_id "'$pr_svc'");" >/dev/null || true
check 'the probe reservations, customers and departure exist' "$([ "$(pr_sql "select count(*) from $SCHEMA.reservation where reservation_id in ('$pr_res','$pr_res_b')")" = 2 ]; echo $?)"

echo 'HU-COM-010 payment review - probes written first: red before the changesets, green after'
db_labels='payment-review'
liquibase update >/dev/null
check 'the review columns, the guard, the index and the key lists bring the control table to 84 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 84 ]; echo $?)"

echo 'attemptHasTheReviewColumnsNullable (AC-D10.1, AC-D10.2)'
pr_review_cols="$(pr_sql "select string_agg(column_name || ' ' || data_type || ' ' || is_nullable, ',' order by column_name) from information_schema.columns where table_schema='$SCHEMA' and table_name='payment_attempt' and column_name in ('decided_by','decided_at','decision_reason','verified_amount_cents','applied_amount_cents','excess_amount_cents','treatment_amount_cents')")"
check 'AC-D10.2 the seven review columns exist, all nullable, with money in bigint cents' "$([ "$pr_review_cols" = 'applied_amount_cents bigint YES,decided_at timestamp with time zone YES,decided_by uuid YES,decision_reason text YES,excess_amount_cents bigint YES,treatment_amount_cents bigint YES,verified_amount_cents bigint YES' ]; echo $?)"
check 'AC-D10.1 nothing new appears in public, the guard lives in the domain schema' "$([ "$(sql "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p','v','m','S','f') and c.relname not like 'databasechangelog%'")" = 0 ] && [ "$(pr_sql "select count(*) from pg_proc where pronamespace='public'::regnamespace and proname like '%payment%'")" = 0 ] && [ "$(pr_sql "select count(*) from pg_proc where pronamespace='$SCHEMA'::regnamespace and proname='fn_payment_attempt_guard'")" = 1 ]; echo $?)"
pr_a1="$(aid 2620)"; pr_a2="$(aid 2621)"; pr_a3="$(aid 2622)"; pr_a4="$(aid 2623)"; pr_a5="$(aid 2624)"; pr_cash="$(aid 2625)"
engine "$(pr_attempt "$pr_a1"); $(pr_attempt "$pr_a2"); $(pr_attempt "$pr_a3"); $(pr_attempt "$pr_a4"); $(pr_attempt "$pr_a5" tenant_id "'$pr_tenant_b'" reservation_id "'$pr_res_b'"); $(pr_attempt "$pr_cash" payment_method "'CASH'" validation_status NULL);" >/dev/null || true
check 'six attempts are stored: five transfers under validation and one cash' "$([ "$(pr_sql "select count(*) from $pr_att where payment_attempt_id in ('$pr_a1','$pr_a2','$pr_a3','$pr_a4','$pr_a5','$pr_cash')")" = 6 ]; echo $?)"

echo 'approvedNeedsAmountsAuthorTimeAndBalancedSums (AC-D10.3)'
rs_refusal "$(pr_approve "$pr_a1" verified_amount_cents NULL);" chk_payment_attempt_approved_complete 'an approval without verified amount'
rs_refusal "$(pr_approve "$pr_a1" applied_amount_cents NULL);" chk_payment_attempt_approved_complete 'an approval without applied amount'
rs_refusal "$(pr_approve "$pr_a1" excess_amount_cents NULL);" chk_payment_attempt_approved_complete 'an approval without excess amount'
rs_refusal "$(pr_approve "$pr_a1" treatment_amount_cents NULL);" chk_payment_attempt_approved_complete 'an approval without treatment amount'
rs_refusal "$(pr_approve "$pr_a1" decided_by NULL);" chk_payment_attempt_approved_complete 'an approval without author'
rs_refusal "$(pr_approve "$pr_a1" decided_at NULL);" chk_payment_attempt_approved_complete 'an approval without time'
rs_refusal "$(pr_approve "$pr_a1" applied_amount_cents 90000);" chk_payment_attempt_approved_complete 'an approval whose parts do not add up to the verified amount'
rs_refusal "$(pr_approve "$pr_a1" applied_amount_cents 100001 excess_amount_cents -1);" chk_payment_attempt_approved_complete 'an approval with a negative excess'
rs_refusal "$(pr_approve "$pr_a1" verified_amount_cents 0 applied_amount_cents 0);" chk_payment_attempt_approved_complete 'an approval of zero'
rs_refusal "$(pr_approve "$pr_a1" verified_amount_cents -100 applied_amount_cents -100);" chk_payment_attempt_approved_complete 'an approval of a negative amount'
rs_refusal "$(pr_approve "$pr_a1" applied_amount_cents -10 excess_amount_cents 100010);" chk_payment_attempt_approved_complete 'an approval with a negative applied amount'
rs_refusal "$(pr_approve "$pr_a1" applied_amount_cents 0 excess_amount_cents 0 treatment_amount_cents 100001);" chk_payment_attempt_approved_complete 'an approval whose treatment passes the verified amount'
rs_refusal "$(pr_approve "$pr_a1" applied_amount_cents 50000 excess_amount_cents 25000 treatment_amount_cents 25000);" chk_payment_attempt_approved_complete 'an approval carrying an excess and a treatment amount together'
rs_accepted "$(pr_approve "$pr_a1")" 'a complete approval, everything applied'
rs_accepted "$(pr_approve "$pr_a1" applied_amount_cents 60000 excess_amount_cents 40000)" 'an approval with an excess'
rs_accepted "$(pr_approve "$pr_a1" applied_amount_cents 0 excess_amount_cents 0 treatment_amount_cents 100000)" 'an approval on a cancelled reservation, all to treatment'

echo 'rejectedNeedsAuthorTimeReasonAndCarriesNoAmounts and aDifferingAmountNeedsAReason (AC-D10.4, AC-D10.5)'
rs_refusal "$(pr_reject "$pr_a1" decided_by NULL);" chk_payment_attempt_rejected_complete 'a rejection without author'
rs_refusal "$(pr_reject "$pr_a1" decided_at NULL);" chk_payment_attempt_rejected_complete 'a rejection without time'
rs_refusal "$(pr_reject "$pr_a1" decision_reason NULL);" chk_payment_attempt_rejected_complete 'a rejection without reason'
rs_refusal "$(pr_reject "$pr_a1" decision_reason "'   '");" chk_payment_attempt_rejected_complete 'a rejection with a blank reason'
rs_refusal "$(pr_reject "$pr_a1" verified_amount_cents 100000);" chk_payment_attempt_rejected_complete 'a rejection carrying a verified amount'
rs_refusal "$(pr_reject "$pr_a1" treatment_amount_cents 0);" chk_payment_attempt_rejected_complete 'a rejection carrying a treatment amount'
rs_accepted "$(pr_reject "$pr_a1")" 'a complete rejection'
rs_refusal "$(pr_approve "$pr_a1" verified_amount_cents 80000 applied_amount_cents 80000);" chk_payment_attempt_difference_has_reason 'an approval of a differing amount without reason'
rs_refusal "$(pr_approve "$pr_a1" verified_amount_cents 80000 applied_amount_cents 80000 decision_reason "' '");" chk_payment_attempt_difference_has_reason 'an approval of a differing amount with a blank reason'
rs_accepted "$(pr_approve "$pr_a1" verified_amount_cents 80000 applied_amount_cents 80000 decision_reason "'Transfer fee deducted'")" 'an approval of a differing amount with its reason'
rs_refusal "update $pr_att set decision_reason = 'stray' where payment_attempt_id = '$pr_a2';" chk_payment_attempt_undecided_empty 'a reason on a proof still under validation'
rs_refusal "update $pr_att set verified_amount_cents = 5 where payment_attempt_id = '$pr_cash';" chk_payment_attempt_undecided_empty 'an amount on a cash attempt'

echo 'aDecidedProofCannotChangeItsDecisionOrAmounts and aNoopUpdateIsAccepted (AC-D10.6)'
engine "$(pr_approve "$pr_a3" verified_amount_cents 100000 applied_amount_cents 70000 excess_amount_cents 30000);" >/dev/null || true
engine "$(pr_reject "$pr_a4");" >/dev/null || true
check 'one proof is APPROVED and one is REJECTED, decided once each' "$([ "$(pr_sql "select validation_status from $pr_att where payment_attempt_id='$pr_a3'")" = APPROVED ] && [ "$(pr_sql "select validation_status from $pr_att where payment_attempt_id='$pr_a4'")" = REJECTED ]; echo $?)"
rs_refusal "update $pr_att set validation_status = 'REJECTED', applied_amount_cents = NULL, excess_amount_cents = NULL, treatment_amount_cents = NULL, verified_amount_cents = NULL, decision_reason = 'changed my mind' where payment_attempt_id = '$pr_a3';" trg_payment_attempt_guard 'turning an approval into a rejection'
rs_refusal "update $pr_att set validation_status = 'APPROVED', verified_amount_cents = 100000, applied_amount_cents = 100000, excess_amount_cents = 0, treatment_amount_cents = 0, decision_reason = NULL where payment_attempt_id = '$pr_a4';" trg_payment_attempt_guard 'turning a rejection into an approval'
rs_refusal "update $pr_att set validation_status = 'IN_VALIDATION' where payment_attempt_id = '$pr_a4';" 'trg_payment_attempt_guard\|chk_payment_attempt_undecided_empty' 'sending a decided proof back to validation'
rs_refusal "update $pr_att set applied_amount_cents = 100000, excess_amount_cents = 0 where payment_attempt_id = '$pr_a3';" trg_payment_attempt_guard 'editing the amounts of a decided proof'
rs_refusal "update $pr_att set decision_reason = 'edited later' where payment_attempt_id = '$pr_a4';" trg_payment_attempt_guard 'editing the reason of a decided proof'
rs_refusal "update $pr_att set decided_by = '$(aid 2699)' where payment_attempt_id = '$pr_a3';" trg_payment_attempt_guard 'editing the author of a decision'
rs_refusal "update $pr_att set decided_at = now() + interval '1 day' where payment_attempt_id = '$pr_a3';" trg_payment_attempt_guard 'editing the time of a decision'
rs_refusal "update $pr_att set received_amount_cents = 1 where payment_attempt_id = '$pr_a3';" trg_payment_attempt_guard 'editing the declared amount of a decided proof'
rs_refusal "update $pr_att set received_amount_cents = 1 where payment_attempt_id = '$pr_a2';" trg_payment_attempt_guard 'editing the declared amount of a proof still under validation'
rs_refusal "update $pr_att set registered_by = '$(aid 2699)' where payment_attempt_id = '$pr_a2';" trg_payment_attempt_guard 'editing the registering user'
rs_refusal "update $pr_att set registered_at = now() + interval '1 day' where payment_attempt_id = '$pr_a2';" trg_payment_attempt_guard 'editing the registered time'
rs_refusal "update $pr_att set reservation_id = '$pr_res_b' where payment_attempt_id = '$pr_a2';" trg_payment_attempt_guard 'moving an attempt to another reservation'
rs_refusal "update $pr_att set tenant_id = '$pr_tenant_b' where payment_attempt_id = '$pr_a2';" trg_payment_attempt_guard 'moving an attempt to another tenant'
rs_refusal "update $pr_att set payment_method = 'CASH', validation_status = NULL where payment_attempt_id = '$pr_a2';" trg_payment_attempt_guard 'turning a transfer into cash'
rs_refusal "update $pr_att set payment_status_snapshot = 'FULLY_PAID' where payment_attempt_id = '$pr_a3';" trg_payment_attempt_guard 'refreshing the snapshot after the decision (write-once, X-2)'
rs_refusal "update $pr_att set validation_status = 'IN_VALIDATION', decision_reason = NULL where payment_attempt_id = '$pr_cash';" 'trg_payment_attempt_guard\|chk_payment_attempt_status_matches_method' 'giving a status to a cash attempt'
rs_accepted "update $pr_att set decision_reason = decision_reason, applied_amount_cents = applied_amount_cents where payment_attempt_id = '$pr_a3'" 'a no-op update of a decided proof'
rs_accepted "update $pr_att set validation_status = validation_status where payment_attempt_id = '$pr_a2'" 'a no-op update of a proof under validation'
check 'AC-D10.6 the guard is a BEFORE UPDATE row trigger on the attempt' "$([ "$(pr_sql "select count(*) from pg_trigger where tgrelid='$pr_att'::regclass and not tgisinternal and tgname='trg_payment_attempt_guard' and (tgtype & 1) = 1 and (tgtype & 2) = 2 and (tgtype & 16) = 16 and (tgtype & 4) = 0")" = 1 ]; echo $?)"
check 'AC-D10.6 the decided rows kept their decision after every refused change' "$([ "$(pr_sql "select verified_amount_cents || '/' || applied_amount_cents || '/' || excess_amount_cents from $pr_att where payment_attempt_id='$pr_a3'")" = '100000/70000/30000' ] && [ "$(pr_sql "select validation_status || '/' || decision_reason from $pr_att where payment_attempt_id='$pr_a4'")" = 'REJECTED/The amount does not match the transfer' ]; echo $?)"

echo 'noAttemptCanBeDeleted and proofsUnderValidationNeverCrossTenants (AC-D10.7, AC-D10.8, AC-D10.9)'
rs_refusal "delete from $pr_att where payment_attempt_id = '$pr_a2';" 'permission denied for table payment_attempt' 'DELETE of an attempt by the application user'
check 'AC-D10.7 no DELETE on payment_attempt for the writer, the application user or the reader, and the over-granted count stays 0' "$([ "$(sql "select has_table_privilege('$writer','$pr_att','DELETE') or has_table_privilege('$app','$pr_att','DELETE') or has_table_privilege('$reader','$pr_att','DELETE')")" = f ] && [ "$(sql "select count(*) from information_schema.tables t where t.table_schema='$SCHEMA' and t.table_name not in ('idempotency_key', 'outbox_event', 'processed_event') and (has_table_privilege('$writer', format('%I.%I', t.table_schema, t.table_name), 'DELETE') or has_table_privilege('$app', format('%I.%I', t.table_schema, t.table_name), 'DELETE'))")" = 0 ]; echo $?)"
check 'AC-D10.8 the proofs under validation of tenant A are exactly its two, none belongs to tenant B and tenant B keeps its own' "$([ "$(pr_sql "select count(*) from $pr_att where tenant_id='$tenant' and validation_status='IN_VALIDATION'")" = 2 ] && [ "$(pr_sql "select count(*) from $pr_att where tenant_id='$tenant' and reservation_id='$pr_res_b'")" = 0 ] && [ "$(pr_sql "select count(*) from $pr_att where tenant_id='$pr_tenant_b' and validation_status='IN_VALIDATION'")" = 1 ]; echo $?)"
sql "insert into $pr_att (payment_attempt_id, tenant_id, reservation_id, payment_method, received_amount_cents, validation_status, payment_status_snapshot, registered_by, registered_at)
     select gen_random_uuid(), case when n % 2 = 0 then '$tenant'::uuid else '$pr_tenant_b'::uuid end, case when n % 2 = 0 then '$pr_res'::uuid else '$pr_res_b'::uuid end, 'TRANSFER', 1000,
            case when n % 10 = 0 then 'IN_VALIDATION' else 'REJECTED' end, 'NO_PAYMENT', '$actor', now() - n * interval '1 minute' from generate_series(1, 400) n" >/dev/null 2>&1 || true
sql "update $pr_att set decided_by='$actor', decided_at=now(), decision_reason='Bulk' where validation_status='REJECTED' and decided_at is null; analyze $pr_att" >/dev/null 2>&1 || true
pr_plan="$(pr_explain "select payment_attempt_id from $pr_att where tenant_id='$tenant' and validation_status='IN_VALIDATION' order by registered_at limit 20")"; printf '%s\n' "$pr_plan"
check 'AC-D10.9 idx_payment_attempt_tenant_under_validation is partial on (tenant_id, registered_at) where the proof is under validation' "$([ "$(pr_sql "select count(*) from pg_indexes where schemaname='$SCHEMA' and indexname='idx_payment_attempt_tenant_under_validation' and indexdef like '%(tenant_id, registered_at) WHERE (validation_status = ''IN_VALIDATION''::text)'")" = 1 ]; echo $?)"
check 'AC-D10.9 the list of proofs under validation of a tenant, oldest first, uses that index' "$(printf '%s\n' "$pr_plan" | grep -q 'idx_payment_attempt_tenant_under_validation'; echo $?)"
pr_plan="$(pr_explain "select payment_attempt_id from $pr_att where tenant_id='$tenant' and reservation_id='$pr_res' order by registered_at desc")"; printf '%s\n' "$pr_plan"
check 'AC-D10.9 the history of one reservation uses the index of HU-COM-009 and this story creates no second one' "$(printf '%s\n' "$pr_plan" | grep -q 'idx_payment_attempt_tenant_reservation_registered_at'; echo $?)"
check 'AC-D10.9 the index of the pending list is built in its own changeset outside a transaction' "$([ "$(awk '/id: ddl-indexes-024/{f=1} f&&/runInTransaction: false/{n++;f=0} END{print n+0}' 01_ddl/10_indexes/changelog.yaml)" = 1 ] && [ "$(grep -cE '^CREATE INDEX CONCURRENTLY' 01_ddl/10_indexes/024_create_payment_attempt_under_validation_index.sql)" = 1 ]; echo $?)"

echo 'theFourEventsFitTheOutboxWithoutPersonalColumns (AC-D10.10)'
pr_validated="'{\"reservationId\":\"$pr_res\",\"amountCents\":100000,\"paymentStatus\":\"DEPOSIT_RECEIVED\",\"pendingBalanceCents\":200000,\"validatorId\":\"$actor\"}'::jsonb"
pr_rejected="'{\"reservationId\":\"$pr_res\",\"reason\":\"Amount mismatch\",\"pendingBalanceCents\":300000,\"validatorId\":\"$actor\"}'::jsonb"
pr_confirmed="'{\"reservationId\":\"$pr_res\",\"paymentStatus\":\"DEPOSIT_RECEIVED\"}'::jsonb"
pr_confirmed_alloc="'{\"reservationId\":\"$pr_res\",\"paymentStatus\":\"DEPOSIT_RECEIVED\",\"allocatedCapacity\":2}'::jsonb"
pr_released="'{\"serviceId\":\"$pr_svc\",\"salidaId\":\"$pr_sal\",\"reservationId\":\"$pr_res\",\"reason\":\"Rejected first payment\"}'::jsonb"
rs_accepted "$(pr_event PaymentValidated "$pr_validated"); $(pr_event PaymentRejected "$pr_rejected"); $(pr_event ReservationConfirmed "$pr_confirmed"); $(pr_event CapacityReleased "$pr_released")" 'the four events in one transaction with a decision'
rs_accepted "$(pr_event ReservationConfirmed "$pr_confirmed_alloc")" 'ReservationConfirmed with the allocated capacity when applicable'
rs_refusal "$(pr_event PaymentValidated "'{\"reservationId\":\"x\",\"amountCents\":1,\"paymentStatus\":\"FULLY_PAID\",\"pendingBalanceCents\":0,\"validatorId\":\"x\",\"fileName\":\"p.pdf\"}'::jsonb");" chk_outbox_event_payload_keys_payment_validated 'PaymentValidated carrying a file name'
rs_refusal "$(pr_event PaymentValidated "'{\"reservationId\":\"x\"}'::jsonb");" chk_outbox_event_payload_keys_payment_validated 'PaymentValidated with missing keys'
rs_refusal "$(pr_event PaymentRejected "'{\"reservationId\":\"x\",\"reason\":\"r\",\"pendingBalanceCents\":0,\"validatorId\":\"x\",\"customerName\":\"Ana\"}'::jsonb");" chk_outbox_event_payload_keys_payment_rejected 'PaymentRejected carrying a customer name'
rs_refusal "$(pr_event PaymentRejected "'{\"reason\":\"r\"}'::jsonb");" chk_outbox_event_payload_keys_payment_rejected 'PaymentRejected with missing keys'
rs_refusal "$(pr_event ReservationConfirmed "'{\"reservationId\":\"x\",\"paymentStatus\":\"FULLY_PAID\",\"email\":\"a@b.c\"}'::jsonb");" 'chk_outbox_event_payload_keys_reservation_confirmed\|chk_outbox_event_payload_no_sensitive_keys' 'ReservationConfirmed carrying an e-mail'
rs_refusal "$(pr_event ReservationConfirmed "'{\"reservationId\":\"x\"}'::jsonb");" chk_outbox_event_payload_keys_reservation_confirmed 'ReservationConfirmed without the payment status'
rs_refusal "$(pr_event CapacityReleased "'{\"serviceId\":\"x\",\"salidaId\":\"x\",\"reservationId\":\"x\",\"reason\":\"r\",\"contact\":\"x\"}'::jsonb");" 'chk_outbox_event_payload_keys_capacity_released\|chk_outbox_event_payload_no_sensitive_keys' 'CapacityReleased carrying a contact'
rs_refusal "$(pr_event CapacityReleased "'{\"salidaId\":\"x\"}'::jsonb");" chk_outbox_event_payload_keys_capacity_released 'CapacityReleased with missing keys'
check 'AC-D10.10 no column of the outbox carries a name, a document, a contact or a file' "$([ "$(pr_sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='outbox_event' and column_name ~* '(document|email|phone|contact|medical|birth|full_name|file|proof|bank|account)'")" = 0 ]; echo $?)"

echo 'releasingMoreSeatsThanHeldIsRefused, aDecisionKeyIsUniquePerTenant and theReaderCannotSelectTheProofContent (AC-D10.11, AC-D10.12, AC-D10.13)'
rs_refusal "update $pr_cap set held_seats = held_seats - 5 where salida_id = '$pr_sal';" chk_salida_capacity_held_seats 'a release of 5 seats when 3 are held'
rs_accepted "update $pr_cap set held_seats = held_seats - 3 where salida_id = '$pr_sal'" 'a release of exactly the held seats'
check 'AC-D10.11 held_seats stayed at 3 after the refused release' "$([ "$(pr_sql "select held_seats from $pr_cap where salida_id='$pr_sal'")" = 3 ]; echo $?)"
pr_key() { echo "insert into $SCHEMA.idempotency_key (key, tenant_id, resource_type, resource_id) values ('$1', '$2', 'payment_proof_decision', '$3')"; }
rs_accepted "$(pr_key 'decision-key-0001' "$tenant" "$pr_a1")" 'a decision key'
engine "$(pr_key 'decision-key-0001' "$tenant" "$pr_a1");" >/dev/null || true
rs_refusal "$(pr_key 'decision-key-0001' "$tenant" "$pr_a2");" pk_idempotency_key 'the same decision key of the same tenant written again'
rs_accepted "$(pr_key 'decision-key-0001' "$pr_tenant_b" "$pr_a5")" 'the same decision key in another tenant'
engine "insert into $pr_proof (payment_proof_file_id, tenant_id, payment_attempt_id, content, content_type, size_bytes, sha256) values (gen_random_uuid(), '$tenant', '$pr_a2', '\\x616263'::bytea, 'application/pdf', 3, '$pr_hash');" >/dev/null || true
pr_reader_out="$(engine "select content from $pr_proof;" "$reader" 2>&1 || true)"; printf '%s
' "$pr_reader_out"
check 'AC-D10.13 the reader selecting the content of the proof is refused for lack of privilege' "$(printf '%s
' "$pr_reader_out" | grep -q 'permission denied for table payment_proof_file'; echo $?)"
check 'AC-D10.13 the writer still reads the proof' "$([ "$(sql "select has_table_privilege('$writer','$pr_proof','SELECT')")" = t ] && [ "$(pr_sql "select count(*) from $pr_proof where payment_attempt_id='$pr_a2'")" = 1 ]; echo $?)"

echo 'Idempotence, exact revert and reapply of the whole story (AC-D10.14, AC-D10.15)'
pr_second="$(liquibase update 2>&1)"; printf '%s\n' "$pr_second"
check 'AC-D10.14 a second update applies zero changesets' "$(printf '%s\n' "$pr_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
sql "delete from $pr_ob where reservation_id in ('$pr_res','$pr_res_b'); delete from $SCHEMA.idempotency_key where key like 'decision-key-%'; delete from $pr_proof; delete from $pr_att; delete from $SCHEMA.reservation where reservation_id in ('$pr_res','$pr_res_b')" >/dev/null 2>&1 || true
check 'the rows of the probes are gone before the revert' "$([ "$(sql "select (select count(*) from $pr_att) + (select count(*) from $pr_proof)")" = 0 ]; echo $?)"
liquibase rollback-count 5
pr_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$pr_base" "$pr_reverted"
check 'AC-D10.15 the five-change revert restores columns, constraints, indexes and privileges exactly' "$([ -n "$pr_base" ] && [ "$pr_reverted" = "$pr_base" ] && [ "$(sql "select count(*) from $CONTROL")" = 79 ]; echo $?)"
check 'the review columns, the guard function, the trigger and the four key lists are gone after the revert' "$([ "$(pr_sql "select count(*) from pg_proc where pronamespace='$SCHEMA'::regnamespace and proname='fn_payment_attempt_guard'")" = 0 ] && [ "$(pr_sql "select count(*) from pg_constraint where conname like 'chk_outbox_event_payload_keys_payment_validated' or conname like 'chk_outbox_event_payload_keys_payment_rejected' or conname like 'chk_payment_attempt_approved_complete'")" = 0 ]; echo $?)"
db_labels=''
liquibase update >/dev/null
liquibase rollback-count 999 >/dev/null
liquibase update >/dev/null
liquibase validate >/dev/null
check 'a full build from empty without any label filter applies exactly 85 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 85 ]; echo $?)"
