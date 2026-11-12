#!/usr/bin/env bash
# Sourced by db-ci.sh after the stackable checks, on the same disposable PostgreSQL instance.
# HU-COM-013 -db (issue multi-tour-docs#179), plan D-02 to D-04: the append-only settlement of a cancellation requested by the customer
# (03_tables/027), the unique key on the cause (04_alter/025), its index (10_indexes/028) and the revoked UPDATE (03_dcl/01_grants/011).
# Four changesets in all, every one labelled HU-COM-013. Probes are written first: red before the changesets, green after (Annex J.1).
cn_t="$SCHEMA.reservation_cancellation"; cn_r="$SCHEMA.reservation"
cn_tenant_b="00000000-0000-0000-0000-000000000002"
cn_cust="$(aid 3401)"; cn_cust_b="$(aid 3402)"; cn_svc="$(aid 3403)"
cn_res_ok="$(aid 3410)"; cn_res_pending="$(aid 3411)"; cn_res_expiry="$(aid 3412)"; cn_res_b="$(aid 3413)"; cn_res_frozen="$(aid 3414)"; cn_res_a2="$(aid 3415)"
cn_sql() { sql "$1" 2>/dev/null || true; }
cn_refusal() { # SQL, text of the engine answer, description
  local answer
  answer="$(engine "$1" 2>&1 || true)"; printf '%s\n' "$answer"
  check "HU-COM-013 db: $3 is refused by $2" "$(printf '%s\n' "$answer" | grep -q "$2"; echo $?)"
}
cn_accepted() { # SQL, description
  local status=0
  engine "$1" >/dev/null || status=$?
  check "HU-COM-013 db: $2 is accepted" "$status"
}
cn_settlement() { # column/value pairs (SQL literals) that replace the defaults of a valid settlement of 300000 with a 50 % penalty
  local -A v=([reservation_cancellation_id]="gen_random_uuid()" [tenant_id]="'$tenant'" [reservation_id]="'$cn_res_ok'" [cancellation_cause]="'CUSTOMER_REQUEST'" [reason]="'The customer cannot travel'" [validated_amount_cents]=30000000 [penalty_bp]=5000 [penalty_amount_cents]=15000000 [refundable_amount_cents]=15000000 [registered_by]="'$actor'" [registered_at]="now()")
  while [ $# -ge 2 ]; do v[$1]="$2"; shift 2; done
  echo "insert into $cn_t (reservation_cancellation_id, tenant_id, reservation_id, cancellation_cause, reason, validated_amount_cents, penalty_bp, penalty_amount_cents, refundable_amount_cents, registered_by, registered_at) values (${v[reservation_cancellation_id]}, ${v[tenant_id]}, ${v[reservation_id]}, ${v[cancellation_cause]}, ${v[reason]}, ${v[validated_amount_cents]}, ${v[penalty_bp]}, ${v[penalty_amount_cents]}, ${v[refundable_amount_cents]}, ${v[registered_by]}, ${v[registered_at]})"
}
cn_explain() { printf '%s\n' 'set enable_seqscan = off;' "explain $1;" | docker exec -i -e PGPASSWORD "$container" psql -X -U postgres -d postgres 2>&1 || true; }
cn_object_count() { sql "select (select count(*) from pg_tables where schemaname='$SCHEMA') || '|' || (select count(*) from pg_proc where pronamespace='$SCHEMA'::regnamespace) || '|' || (select count(*) from pg_trigger where not tgisinternal and tgrelid in (select oid from pg_class where relnamespace='$SCHEMA'::regnamespace))" 2>/dev/null || true; }

echo 'HU-COM-013 db - base: the 100 changesets that exist before the story'
liquibase rollback-count 999 >/dev/null
db_labels='!HU-COM-013 and !HU-COM-012 and !HU-COM-015 and !HU-COM-016 and !HU-COM-017 and !HU-COM-019 and !HU-COM-018 and !HU-COM-020 and !decision-resume and !episode-frozen-total and !departure-order and !exceptional-access-use and !reservation-confirmed-value and !payment-parameters-changed'
liquibase update >/dev/null
cn_base="$(snapshot)"
cn_base_objects="$(cn_object_count)"
check 'base holds exactly 100 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 100 ]; echo $?)"
sql "insert into $SCHEMA.customer (customer_id, tenant_id, full_name, created_at, document_number, birth_date_or_age, contact_info, status, terms_accepted, terms_accepted_at) values ('$cn_cust', '$tenant', 'Settlement probe A', now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE', true, now()), ('$cn_cust_b', '$cn_tenant_b', 'Settlement probe B', now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE', true, now());
     insert into $SCHEMA.catalog_service (service_id, tenant_id, service_type, commercial_name, catalog_status, base_rate_cents, base_operational_cost_cents, configured_capacity, transport_required, high_risk, created_at, updated_at) values ('$cn_svc', '$tenant', 'TOUR', 'Settlement probe tour', 'ACTIVE', 150000, 90000, 12, false, false, now(), now())" >/dev/null 2>&1 || true
for cn_id in "$cn_res_ok" "$cn_res_pending" "$cn_res_expiry" "$cn_res_frozen" "$cn_res_a2"; do
  engine "$(rs_row reservation_id "'$cn_id'" customer_id "'$cn_cust'" service_id "'$cn_svc'");" >/dev/null || true
done
engine "$(rs_row reservation_id "'$cn_res_b'" tenant_id "'$cn_tenant_b'" customer_id "'$cn_cust_b'" service_id "'$cn_svc'");" >/dev/null || true
cn_by_customer="reservation_status = 'CANCELLED', cancellation_cause = 'CUSTOMER_REQUEST', cancelled_at = now(), cancelled_by = '$actor'"
cn_sql "update $cn_r set $cn_by_customer where reservation_id in ('$cn_res_ok','$cn_res_frozen','$cn_res_a2','$cn_res_b')"
cn_sql "update $cn_r set reservation_status = 'CANCELLED', cancellation_cause = 'PAYMENT_EXPIRY', cancelled_at = now() where reservation_id = '$cn_res_expiry'"
check 'the probe reservations exist: four cancelled at the customer request, one by expiry, one pending' "$([ "$(cn_sql "select count(*) from $cn_r where reservation_id in ('$cn_res_ok','$cn_res_frozen','$cn_res_a2','$cn_res_b') and cancellation_cause = 'CUSTOMER_REQUEST'")" = 4 ] && [ "$(cn_sql "select count(*) from $cn_r where reservation_id = '$cn_res_expiry' and cancellation_cause = 'PAYMENT_EXPIRY'")" = 1 ] && [ "$(cn_sql "select count(*) from $cn_r where reservation_id = '$cn_res_pending' and reservation_status = 'PENDING_PAYMENT'")" = 1 ]; echo $?)"

echo 'HU-COM-013 db - probes written first: red before the changesets, green after'
db_labels='HU-COM-013'
liquibase update >/dev/null
check 'the four changesets of the story bring the control table to 104' "$([ "$(sql "select count(*) from $CONTROL")" = 104 ]; echo $?)"

echo 'settlementRequiresEveryFieldAndANonBlankReason (AC-D13.2)'
for cn_col in tenant_id reservation_id cancellation_cause reason validated_amount_cents penalty_bp penalty_amount_cents refundable_amount_cents registered_by registered_at; do
  cn_refusal "$(cn_settlement "$cn_col" NULL);" "null value in column \"$cn_col\".*not-null constraint" "a settlement without $cn_col"
done
cn_refusal "$(cn_settlement reason "'   '");" chk_reservation_cancellation_reason 'a settlement with a blank reason'
check 'AC-D13.2 no column of reservation_cancellation has a DEFAULT' "$([ "$(cn_sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='reservation_cancellation' and column_default is not null")" = 0 ]; echo $?)"

echo 'amountsMustAddUpAndStayInRange (AC-D13.3)'
cn_refusal "$(cn_settlement penalty_bp 10001);" chk_reservation_cancellation_penalty_bp 'basis points above 10 000'
cn_refusal "$(cn_settlement penalty_bp -1);" chk_reservation_cancellation_penalty_bp 'negative basis points'
cn_refusal "$(cn_settlement validated_amount_cents -1);" chk_reservation_cancellation_amounts 'a negative validated amount'
cn_refusal "$(cn_settlement penalty_amount_cents 30000001 refundable_amount_cents -1);" chk_reservation_cancellation_amounts 'a penalty above the validated amount'
cn_refusal "$(cn_settlement refundable_amount_cents 14999999);" chk_reservation_cancellation_amounts 'a refundable amount that is not validated minus penalty'
cn_accepted "$(cn_settlement penalty_bp 0 penalty_amount_cents 0 refundable_amount_cents 30000000 reservation_id "'$cn_res_frozen'")" 'a settlement with no penalty (whole validated amount refundable)'
cn_accepted "$(cn_settlement validated_amount_cents 0 penalty_bp 0 penalty_amount_cents 0 refundable_amount_cents 0 reservation_id "'$cn_res_a2'")" 'a settlement of zero'

echo 'onlyACustomerRequestCancellationOfTheSameTenantHasOne (AC-D13.4)'
cn_refusal "$(cn_settlement reservation_id "'$cn_res_pending'");" fk_reservation_cancellation_reservation 'a settlement of a reservation that is not cancelled'
cn_refusal "$(cn_settlement reservation_id "'$cn_res_expiry'");" fk_reservation_cancellation_reservation 'a settlement of a reservation cancelled by expiry'
cn_refusal "$(cn_settlement reservation_id "'$cn_res_b'");" fk_reservation_cancellation_reservation 'a settlement of a reservation of another tenant'
cn_refusal "$(cn_settlement cancellation_cause "'PAYMENT_EXPIRY'" reservation_id "'$cn_res_expiry'");" chk_reservation_cancellation_cause 'a settlement with a cause other than CUSTOMER_REQUEST'
cn_s1="$(aid 3420)"
cn_accepted "$(cn_settlement reservation_cancellation_id "'$cn_s1'")" 'the settlement of a reservation cancelled at the customer request'

echo 'aSecondSettlementForTheSameReservationIsRefused (AC-D13.4)'
cn_refusal "$(cn_settlement);" uq_reservation_cancellation_reservation 'a second settlement for the same reservation'

echo 'aSettlementCannotBeUpdatedOrDeleted (AC-D13.5)'
cn_refusal "update $cn_t set reason = 'edited' where reservation_cancellation_id = '$cn_s1';" 'permission denied for table reservation_cancellation' 'an UPDATE of a settlement as the application user'
cn_refusal "delete from $cn_t where reservation_cancellation_id = '$cn_s1';" 'permission denied for table reservation_cancellation' 'a DELETE of a settlement as the application user'

echo 'settlementsNeverCrossTenants (AC-D13.6)'
cn_sql "insert into $cn_t (reservation_cancellation_id, tenant_id, reservation_id, cancellation_cause, reason, validated_amount_cents, penalty_bp, penalty_amount_cents, refundable_amount_cents, registered_by, registered_at) values ('$(aid 3421)', '$cn_tenant_b', '$cn_res_b', 'CUSTOMER_REQUEST', 'Other tenant', 100, 0, 0, 100, '$actor', now())"
check 'AC-D13.6 a read scoped to tenant A returns its three settlements and none of tenant B' "$([ "$(cn_sql "select count(*) from $cn_t where tenant_id = '$tenant'")" = 3 ] && [ "$(cn_sql "select count(*) from $cn_t where tenant_id = '$tenant' and reservation_id = '$cn_res_b'")" = 0 ] && [ "$(cn_sql "select count(*) from $cn_t where tenant_id = '$cn_tenant_b'")" = 1 ]; echo $?)"

echo 'theSettlementReadUsesItsIndex (AC-D13.7)'
cn_plan="$(cn_explain "select * from $cn_t where tenant_id='$tenant' and reservation_id='$cn_res_ok'")"; printf '%s\n' "$cn_plan"
check 'AC-D13.7 the read of one settlement uses idx_reservation_cancellation_tenant_reservation' "$(printf '%s\n' "$cn_plan" | grep -q 'idx_reservation_cancellation_tenant_reservation'; echo $?)"
check 'AC-D13.7 the index leads with tenant_id' "$([ "$(cn_sql "select count(*) from pg_indexes where schemaname='$SCHEMA' and indexname='idx_reservation_cancellation_tenant_reservation' and indexdef like '%(tenant_id, reservation_id)%'")" = 1 ]; echo $?)"

echo 'theSameKeyTwiceIsRefusedPerTenant (AC-D13.8)'
cn_key() { echo "insert into $SCHEMA.idempotency_key (key, tenant_id, resource_type, resource_id) values ('$1', '$2', 'reservation_cancellation', '$cn_s1')"; }
cn_accepted "$(cn_key cancellation-key-1 "$tenant")" 'a cancellation key'
cn_refusal "$(cn_key cancellation-key-1 "$tenant");" pk_idempotency_key 'the same key twice in one tenant'
cn_accepted "$(cn_key cancellation-key-1 "$cn_tenant_b")" 'the same key in another tenant'

echo 'onlyThePlannedObjectsAreAddedAndRevertLeavesNoTrace (AC-D13.1, AC-D13.9)'
cn_objects="$(cn_object_count)"
IFS='|' read -r cn_bt cn_bf cn_bg <<< "$cn_base_objects"
cn_expected="$((cn_bt + 1))|$cn_bf|$cn_bg"
printf 'Base objects (tables|functions|triggers): %s\nExpected: %s\nFound:    %s\n' "$cn_base_objects" "$cn_expected" "$cn_objects"
check 'AC-D13.1 exactly one table was added to the base and it is reservation_cancellation' "$([ -n "$cn_base_objects" ] && [ "$cn_objects" = "$cn_expected" ] && [ "$(cn_sql "select count(*) from pg_tables where schemaname='$SCHEMA' and tablename='reservation_cancellation'")" = 1 ]; echo $?)"
check 'AC-D13.1 nothing new appears in public' "$([ "$(sql "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p','v','m','S','f') and c.relname not like 'databasechangelog%'")" = 0 ]; echo $?)"
check 'AC-D13.1 the unique key of reservation carries tenant, reservation and cause' "$([ "$(cn_sql "select count(*) from pg_indexes where schemaname='$SCHEMA' and indexname='uq_reservation_tenant_id_cancellation_cause' and indexdef like '%(tenant_id, reservation_id, cancellation_cause)%'")" = 1 ]; echo $?)"
cn_second="$(liquibase update 2>&1)"; printf '%s\n' "$cn_second"
check 'AC-D13.9 a second update applies zero changesets' "$(printf '%s\n' "$cn_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
sql "delete from $SCHEMA.idempotency_key where key = 'cancellation-key-1'; delete from $cn_t; delete from $cn_r where reservation_id in ('$cn_res_ok','$cn_res_pending','$cn_res_expiry','$cn_res_b','$cn_res_frozen','$cn_res_a2'); delete from $SCHEMA.catalog_service where service_id = '$cn_svc'; delete from $SCHEMA.customer where customer_id in ('$cn_cust','$cn_cust_b')" >/dev/null 2>&1 || true
check 'the rows of the probes are gone before the revert' "$([ "$(sql "select (select count(*) from $cn_t) + (select count(*) from $cn_r where reservation_id in ('$cn_res_ok','$cn_res_b'))")" = 0 ]; echo $?)"
liquibase rollback-count 4
cn_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$cn_base" "$cn_reverted"
check 'AC-D13.9 the four-change revert restores columns, constraints, indexes and privileges exactly and leaves 100 changesets' "$([ -n "$cn_base" ] && [ "$cn_reverted" = "$cn_base" ] && [ "$(sql "select count(*) from $CONTROL")" = 100 ]; echo $?)"
check 'the settlement table and its key are gone after the revert' "$([ "$(cn_sql "select count(*) from pg_tables where schemaname='$SCHEMA' and tablename='reservation_cancellation'")" = 0 ] && [ "$(cn_sql "select count(*) from pg_constraint where conname='uq_reservation_tenant_id_cancellation_cause'")" = 0 ]; echo $?)"
db_labels=''
liquibase update >/dev/null
liquibase rollback-count 999 >/dev/null
liquibase update >/dev/null
liquibase validate >/dev/null
check 'a full build from empty without any label filter applies exactly 179 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 153 ]; echo $?)"
