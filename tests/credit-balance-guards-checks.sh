#!/usr/bin/env bash
# Sourced by db-ci.sh after credit-balance-checks.sh, on the same disposable PostgreSQL instance, with the 136 changesets that exist before this slice.
# HU-COM-017 -db (issue multi-tour-docs#183), plan D-04 to D-07, slice 2: the two guards (holder, tenant and ceiling of an application; ceiling of a credit-balance refund
# request), the three indexes of the reads, the tenant isolation, the idempotency key and the outbox keys of the two credit events. Every changeset of the slice is labelled
# HU-COM-017 and credit-balance-guards. Probes are written first: red before the changesets, green after (Annex J.1). The rows of the probes are removed by the owner at the end.
cg_cr="$SCHEMA.credit_balance"; cg_ap="$SCHEMA.credit_balance_application"; cg_fd="$SCHEMA.financial_decision"; cg_ob="$SCHEMA.outbox_event"
cg_tenant_b="00000000-0000-0000-0000-000000000002"
cg_cust="$(aid 6101)"; cg_cust2="$(aid 6102)"; cg_cust_b="$(aid 6103)"; cg_svc="$(aid 6104)"
cg_res1="$(aid 6110)"; cg_res2="$(aid 6111)"; cg_res3="$(aid 6112)"; cg_res_b="$(aid 6113)"
cg_dec1="$(aid 6120)"; cg_dec2="$(aid 6121)"; cg_dec_b="$(aid 6122)"; cg_rq1="$(aid 6123)"; cg_rq2="$(aid 6124)"
cg_ca="$(aid 6130)"; cg_cb="$(aid 6131)"; cg_cc="$(aid 6132)"
cg_sql() { sql "$1" 2>/dev/null || true; }
cg_refusal() { # SQL, text of the engine answer, description
  local answer
  answer="$(engine "$1" 2>&1 || true)"; printf '%s\n' "$answer"
  check "HU-COM-017 db: $3 is refused by $2" "$(printf '%s\n' "$answer" | grep -q "$2"; echo $?)"
}
cg_accepted() { # SQL, description
  local status=0
  engine "$1" >/dev/null || status=$?
  check "HU-COM-017 db: $2 is accepted" "$status"
}
cg_explain() { printf '%s\n' 'set enable_seqscan = off;' "explain $1;" | docker exec -i -e PGPASSWORD "$container" psql -X -U postgres -d postgres 2>&1 || true; }
cg_credit() { # credit id, reservation, decision, tenant: a credit of 80000 recorded by the owner of the table
  echo "insert into $cg_cr (credit_balance_id, tenant_id, source_reservation_id, credit_origin, amount_cents, source_financial_decision_id, source_payment_attempt_id, recorded_at, recorded_by) values ('$1', '${4:-$tenant}', '$2', 'CUSTOMER_CANCELLATION', 80000, '$3', NULL, now(), '$actor')"
}
cg_apply() { # credit, target reservation, amount, then column/value pairs (SQL literals) that replace the defaults
  local credit="$1" target="$2" amount="$3"; shift 3
  local -A v=([credit_balance_application_id]="gen_random_uuid()" [tenant_id]="'$tenant'" [applied_by_kind]="'STAFF'")
  while [ $# -ge 2 ]; do v[$1]="$2"; shift 2; done
  echo "insert into $cg_ap (credit_balance_application_id, credit_balance_id, tenant_id, target_reservation_id, applied_amount_cents, applied_at, applied_by, applied_by_kind) values (${v[credit_balance_application_id]}, '$credit', ${v[tenant_id]}, '$target', $amount, now(), '$actor', ${v[applied_by_kind]})"
}
cg_request() { # request id, credit, amount: a refund request of the credit, as the api opens it
  echo "insert into $cg_fd (financial_decision_id, tenant_id, reservation_id, credit_balance_id, decision_kind, base_amount_cents, recognized_at) values ('$1', '$tenant', '$cg_res1', '$2', 'CREDIT_BALANCE_REFUND_REQUEST', $3, now())"
}
cg_event() { # payload (SQL literal), then column/value pairs that replace the defaults
  local payload="$1"; shift
  local -A v=([reservation_id]="'$cg_res1'" [event_type]="'CreditBalanceRecorded'" [actor_id]="'$actor'")
  while [ $# -ge 2 ]; do v[$1]="$2"; shift 2; done
  echo "insert into $cg_ob (tenant_id, event_type, reservation_id, actor_id, occurred_at, payload) values ('$tenant', ${v[event_type]}, ${v[reservation_id]}, ${v[actor_id]}, now(), $payload)"
}

echo 'HU-COM-017 db slice 2 - base: the 136 changesets that exist before the slice, with the probe rows'
liquibase rollback-count 999 >/dev/null
db_labels='!credit-balance-guards and !HU-COM-019 and !HU-COM-018 and !HU-COM-020 and !decision-resume and !episode-frozen-total and !departure-order and !exceptional-access-use and !reservation-confirmed-value'
liquibase update >/dev/null
cg_base="$(snapshot)"
cg_base_objects="$(sql "select (select count(*) from pg_tables where schemaname='$SCHEMA') || '|' || (select count(*) from pg_proc where pronamespace='$SCHEMA'::regnamespace) || '|' || (select count(*) from pg_trigger where not tgisinternal and tgrelid in (select oid from pg_class where relnamespace='$SCHEMA'::regnamespace))" 2>/dev/null || true)"
check 'base holds exactly 136 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 136 ]; echo $?)"
sql "insert into $SCHEMA.customer (customer_id, tenant_id, full_name, created_at, document_number, birth_date_or_age, contact_info, status, terms_accepted, terms_accepted_at) values ('$cg_cust', '$tenant', 'Guard probe A', now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE', true, now()), ('$cg_cust2', '$tenant', 'Guard probe B', now(), 'enc:v1:x2', 'enc:v1:y2', '{}'::jsonb, 'ACTIVE', true, now()), ('$cg_cust_b', '$cg_tenant_b', 'Guard probe C', now(), 'enc:v1:x3', 'enc:v1:y3', '{}'::jsonb, 'ACTIVE', true, now());
     insert into $SCHEMA.catalog_service (service_id, tenant_id, service_type, commercial_name, catalog_status, base_rate_cents, base_operational_cost_cents, configured_capacity, transport_required, high_risk, created_at, updated_at) values ('$cg_svc', '$tenant', 'TOUR', 'Guard probe tour', 'ACTIVE', 150000, 90000, 12, false, false, now(), now())" >/dev/null 2>&1 || true
engine "$(rs_row reservation_id "'$cg_res1'" customer_id "'$cg_cust'" service_id "'$cg_svc'"); $(rs_row reservation_id "'$cg_res2'" customer_id "'$cg_cust'" service_id "'$cg_svc'"); $(rs_row reservation_id "'$cg_res3'" customer_id "'$cg_cust2'" service_id "'$cg_svc'"); $(rs_row reservation_id "'$cg_res_b'" tenant_id "'$cg_tenant_b'" customer_id "'$cg_cust_b'" service_id "'$cg_svc'");" >/dev/null || true
engine "$(fd_row financial_decision_id "'$cg_dec1'" reservation_id "'$cg_res1'"); $(fd_row financial_decision_id "'$cg_dec2'" reservation_id "'$cg_res1'" decision_kind "'MODIFICATION_EXCESS'" penalty_amount_cents NULL); $(fd_row financial_decision_id "'$cg_dec_b'" tenant_id "'$cg_tenant_b'" reservation_id "'$cg_res_b'");" >/dev/null || true
engine "$(cg_credit "$cg_ca" "$cg_res1" "$cg_dec1"); $(cg_credit "$cg_cb" "$cg_res1" "$cg_dec2"); $(cg_credit "$cg_cc" "$cg_res_b" "$cg_dec_b" "$cg_tenant_b");" >/dev/null || true
check 'the probe reservations, decisions and credits exist on the base' "$([ "$(cg_sql "select (select count(*) from $SCHEMA.reservation where reservation_id in ('$cg_res1','$cg_res2','$cg_res3','$cg_res_b')) || '|' || (select count(*) from $cg_cr where credit_balance_id in ('$cg_ca','$cg_cb','$cg_cc'))")" = '4|3' ]; echo $?)"

echo 'HU-COM-017 db slice 2 - probes written first: red before the changesets, green after'
db_labels='credit-balance-guards'
liquibase update >/dev/null
check 'the changesets of the slice bring the control table to 144' "$([ "$(sql "select count(*) from $CONTROL")" = 144 ]; echo $?)"

echo 'anApplicationNeverCrossesATenantOrACustomer (AC-D17.7)'
cg_refusal "$(cg_apply "$cg_ca" "$cg_res3" 10000);" trg_credit_balance_application_guard 'an application to a reservation of another customer of the same tenant'
cg_refusal "$(cg_apply "$cg_ca" "$cg_res_b" 10000);" trg_credit_balance_application_guard 'an application to a reservation of another tenant'
cg_refusal "$(cg_apply "$cg_ca" "$cg_res_b" 10000 tenant_id "'$cg_tenant_b'");" trg_credit_balance_application_guard 'an application of a credit of another tenant'
cg_accepted "$(cg_apply "$cg_ca" "$cg_res2" 30000)" 'an application of part of the credit to another reservation of the same customer'

echo 'appliedAndSetAsideNeverExceedTheRecordedAmount (AC-D17.8)'
cg_refusal "$(cg_apply "$cg_ca" "$cg_res2" 60000);" trg_credit_balance_application_guard 'an application above what is left of the credit'
cg_accepted "$(cg_request "$cg_rq1" "$cg_ca" 40000)" 'a refund request within what is left'
cg_refusal "$(cg_request "$cg_rq2" "$cg_ca" 20000);" trg_credit_request_guard 'a second refund request that would pass the recorded amount'
cg_refusal "$(cg_apply "$cg_ca" "$cg_res2" 20000);" trg_credit_balance_application_guard 'an application that would pass the amount once the request is set aside'
sql "update $cg_fd set outcome = 'REJECTED', decided_by_system = false, decided_by = '$actor', decided_at = now(), rejection_justification = 'Not applicable' where financial_decision_id = '$cg_rq1'" >/dev/null 2>&1 || true
cg_accepted "$(cg_apply "$cg_ca" "$cg_res2" 50000)" 'an application of what the rejected request had set aside'
cg_refusal "$(cg_apply "$cg_ca" "$cg_res2" 1);" trg_credit_balance_application_guard 'one cent more than the credit holds'

echo 'twoApplicationsAtOnceCannotConsumeTheSameCreditTwice (AC-D17.8)'
cg_first="$(cg_apply "$cg_cb" "$cg_res2" 50000)"; cg_second="$(cg_apply "$cg_cb" "$cg_res2" 50000)"
( printf '%s\n' "set role $app;" "begin;" "$cg_first;" "select pg_sleep(4);" "commit;" | docker exec -i -e PGPASSWORD "$container" psql -X -U postgres -d postgres > /tmp/cg-s1.$$ 2>&1 ) &
cg_p1=$!
sleep 1
( printf '%s\n' "set role $app;" "$cg_second;" | docker exec -i -e PGPASSWORD "$container" psql -X -U postgres -d postgres > /tmp/cg-s2.$$ 2>&1 ) &
cg_p2=$!
wait "$cg_p1" "$cg_p2"
cat /tmp/cg-s1.$$ /tmp/cg-s2.$$
check 'exactly one of the two concurrent applications committed' "$([ "$(cg_sql "select count(*) from $cg_ap where credit_balance_id = '$cg_cb'")" = 1 ]; echo $?)"
check 'the loser was refused by the guard, after waiting for the lock' "$(cat /tmp/cg-s1.$$ /tmp/cg-s2.$$ | grep -q trg_credit_balance_application_guard; echo $?)"
rm -f /tmp/cg-s1.$$ /tmp/cg-s2.$$

echo 'creditsAndApplicationsNeverCrossTenants (AC-D17.10)'
check 'a read scoped to the first tenant returns none of the second tenant credits, and the other way round' "$([ "$(cg_sql "select (select count(*) from $cg_cr where tenant_id = '$tenant' and credit_balance_id = '$cg_cc') || '|' || (select count(*) from $cg_cr where tenant_id = '$cg_tenant_b' and credit_balance_id in ('$cg_ca','$cg_cb')) || '|' || (select count(*) from $cg_ap where tenant_id = '$cg_tenant_b')")" = '0|0|0' ]; echo $?)"

echo 'theReadsUseTheirIndexes (AC-D17.10)'
cg_p1="$(cg_explain "select 1 from $cg_cr where tenant_id = '$tenant' and source_reservation_id = '$cg_res1'")"; printf '%s\n' "$cg_p1"
check 'the credits of a reservation use idx_credit_balance_tenant_source_reservation' "$(printf '%s\n' "$cg_p1" | grep -q 'idx_credit_balance_tenant_source_reservation'; echo $?)"
cg_p2="$(cg_explain "select 1 from $cg_ap where tenant_id = '$tenant' and credit_balance_id = '$cg_ca'")"; printf '%s\n' "$cg_p2"
check 'the applications of a credit use idx_credit_balance_application_tenant_credit' "$(printf '%s\n' "$cg_p2" | grep -q 'idx_credit_balance_application_tenant_credit'; echo $?)"
cg_p3="$(cg_explain "select 1 from $cg_ap where tenant_id = '$tenant' and target_reservation_id = '$cg_res2'")"; printf '%s\n' "$cg_p3"
check 'the applications to a reservation use idx_credit_balance_application_tenant_target' "$(printf '%s\n' "$cg_p3" | grep -q 'idx_credit_balance_application_tenant_target'; echo $?)"

echo 'theSameKeyTwiceIsRefusedPerTenant (AC-D17.11)'
cg_key="insert into $SCHEMA.idempotency_key (key, tenant_id, resource_type, resource_id) values ('credit-application-key-1', '$tenant', 'credit_balance_application', '$cg_ca')"
cg_accepted "$cg_key" 'the first registration of an application key'
cg_refusal "$cg_key;" pk_idempotency_key 'the same key of the same tenant twice'
cg_accepted "insert into $SCHEMA.idempotency_key (key, tenant_id, resource_type, resource_id) values ('credit-application-key-1', '$cg_tenant_b', 'credit_balance_application', '$cg_cc')" 'the same key in another tenant'

echo 'theOutboxAcceptsTheTwoCreditEventsWithTheirKeysOnly (AC-D17.12)'
cg_rec='{"creditBalanceId":"c","reservationId":"r","customerId":"u","amountCents":80000,"origin":"CUSTOMER_CANCELLATION"}'
cg_app='{"creditBalanceId":"c","sourceReservationId":"r","targetReservationId":"t","appliedAmountCents":30000,"appliedByKind":"STAFF"}'
cg_accepted "$(cg_event "'$cg_rec'::jsonb")" 'CreditBalanceRecorded with exactly its five keys'
cg_accepted "$(cg_event "'$cg_app'::jsonb" event_type "'CreditBalanceApplied'")" 'CreditBalanceApplied with exactly its five keys'
cg_refusal "$(cg_event "'{\"creditBalanceId\":\"c\",\"reservationId\":\"r\",\"customerId\":\"u\",\"amountCents\":80000,\"origin\":\"CUSTOMER_CANCELLATION\",\"reason\":\"free text\"}'::jsonb");" chk_outbox_event_payload_keys_credit_balance_recorded 'CreditBalanceRecorded with a sixth key'
cg_refusal "$(cg_event "'{\"creditBalanceId\":\"c\",\"sourceReservationId\":\"r\",\"targetReservationId\":\"t\",\"appliedAmountCents\":30000}'::jsonb" event_type "'CreditBalanceApplied'");" chk_outbox_event_payload_keys_credit_balance_applied 'CreditBalanceApplied with a missing key'
cg_refusal "$(cg_event NULL);" chk_outbox_event_payload 'CreditBalanceRecorded without payload'
cg_refusal "$(cg_event "'$cg_rec'::jsonb" reservation_id NULL);" chk_outbox_event_exactly_one_aggregate 'CreditBalanceRecorded without a reservation'
cg_refusal "$(cg_event "'$cg_rec'::jsonb" actor_id NULL);" chk_outbox_event_actor_required 'CreditBalanceRecorded without actor'
cg_accepted "$(cg_event "'{\"reservationId\":\"x\",\"cause\":\"PAYMENT_EXPIRY\",\"releasedSeats\":2}'::jsonb" event_type "'ReservationCancelled'")" 'ReservationCancelled of an earlier story keeps its key list'
cg_accepted "$(cg_event "'{\"refundAuthorizationId\":\"x\",\"reservationId\":\"y\",\"amountCents\":80000,\"origin\":\"CUSTOMER_CANCELLATION\",\"authorizationMode\":\"TENANT_ADMINISTRATOR\",\"authorizedBy\":\"z\"}'::jsonb" event_type "'RefundAuthorized'")" 'RefundAuthorized of the earlier slice is still accepted'

echo 'onlyThePlannedObjectsAreAddedAndRevertLeavesNoTrace, slice 2 (AC-D17.1, AC-D17.13)'
cg_objects="$(sql "select (select count(*) from pg_tables where schemaname='$SCHEMA') || '|' || (select count(*) from pg_proc where pronamespace='$SCHEMA'::regnamespace) || '|' || (select count(*) from pg_trigger where not tgisinternal and tgrelid in (select oid from pg_class where relnamespace='$SCHEMA'::regnamespace))" 2>/dev/null || true)"
IFS='|' read -r cg_bt cg_bf cg_bg <<< "$cg_base_objects"
check 'AC-D17.1 exactly the two guards and their two triggers were added to the base, and no table' "$([ -n "$cg_base_objects" ] && [ "$cg_objects" = "$cg_bt|$((cg_bf + 2))|$((cg_bg + 2))" ]; echo $?)"
check 'AC-D17.1 the three indexes exist and lead with tenant_id' "$([ "$(cg_sql "select count(*) from pg_indexes where schemaname='$SCHEMA' and indexname in ('idx_credit_balance_tenant_source_reservation','idx_credit_balance_application_tenant_credit','idx_credit_balance_application_tenant_target') and indexdef like '%(tenant_id,%'")" = 3 ]; echo $?)"
check 'AC-D17.1 nothing new appears in public' "$([ "$(sql "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p','v','m','S','f') and c.relname not like 'databasechangelog%'")" = 0 ]; echo $?)"
cg_second_run="$(liquibase update 2>&1)"; printf '%s\n' "$cg_second_run"
check 'AC-D17.13 a second update applies zero changesets' "$(printf '%s\n' "$cg_second_run" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
sql "delete from $cg_ob where reservation_id in ('$cg_res1') or payload ->> 'refundAuthorizationId' = 'x'; delete from $SCHEMA.idempotency_key where key = 'credit-application-key-1'; delete from $cg_ap; delete from $cg_fd where credit_balance_id is not null; delete from $cg_cr; delete from $cg_fd where financial_decision_id in ('$cg_dec1','$cg_dec2','$cg_dec_b'); delete from $SCHEMA.reservation where reservation_id in ('$cg_res1','$cg_res2','$cg_res3','$cg_res_b'); delete from $SCHEMA.catalog_service where service_id = '$cg_svc'; delete from $SCHEMA.customer where customer_id in ('$cg_cust','$cg_cust2','$cg_cust_b')" >/dev/null 2>&1 || true
check 'the rows of the probes are gone before the revert' "$([ "$(sql "select (select count(*) from $cg_cr) + (select count(*) from $cg_ap) + (select count(*) from $SCHEMA.reservation where reservation_id in ('$cg_res1','$cg_res2','$cg_res3','$cg_res_b'))")" = 0 ]; echo $?)"
cg_n="$(sql "select count(*) from $CONTROL where labels ilike '%credit-balance-guards%'" 2>/dev/null || echo 0)"
liquibase rollback-count "$cg_n"
cg_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$cg_base" "$cg_reverted"
check 'AC-D17.13 the revert of the slice restores columns, constraints, indexes and privileges exactly and leaves 136 changesets' "$([ -n "$cg_base" ] && [ "$cg_reverted" = "$cg_base" ] && [ "$(sql "select count(*) from $CONTROL")" = 136 ]; echo $?)"
db_labels='credit-balance-guards'
liquibase update >/dev/null
check 'the changesets of the slice reapply to 144' "$([ "$(sql "select count(*) from $CONTROL")" = 144 ]; echo $?)"
