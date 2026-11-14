#!/usr/bin/env bash
# Sourced by db-ci.sh after client-notice-relay-checks.sh, on the same disposable PostgreSQL instance, with the 130 changesets that exist before the story.
# HU-COM-017 -db (issue multi-tour-docs#183), plan D-02, D-03 and D-05, slice 1: the credit_balance table, the append-only credit_balance_application table,
# the two partial unique keys of the single recording, the revoke of UPDATE and the key from a credit-balance refund request. Every changeset of the slice is
# labelled HU-COM-017. Probes are written first: red before the changesets, green after (Annex J.1).
cb_t="$SCHEMA.credit_balance"; cb_ap="$SCHEMA.credit_balance_application"; cb_fd="$SCHEMA.financial_decision"; cb_pa="$SCHEMA.payment_attempt"
cb_cust="$(aid 6001)"; cb_cust2="$(aid 6002)"; cb_svc="$(aid 6003)"
cb_res1="$(aid 6010)"; cb_res2="$(aid 6011)"; cb_res3="$(aid 6012)"
cb_dec1="$(aid 6020)"; cb_dec2="$(aid 6021)"; cb_dec_rq="$(aid 6022)"
cb_att1="$(aid 6030)"; cb_att2="$(aid 6031)"
cb_ok="$(aid 6040)"; cb_ok2="$(aid 6041)"; cb_ok3="$(aid 6042)"; cb_app="$(aid 6050)"
cb_sql() { sql "$1" 2>/dev/null || true; }
cb_refusal() { # SQL, text of the engine answer, description
  local answer
  answer="$(engine "$1" 2>&1 || true)"; printf '%s\n' "$answer"
  check "HU-COM-017 db: $3 is refused by $2" "$(printf '%s\n' "$answer" | grep -q "$2"; echo $?)"
}
cb_accepted() { # SQL, description
  local status=0
  engine "$1" >/dev/null || status=$?
  check "HU-COM-017 db: $2 is accepted" "$status"
}
cb_row() { # column/value pairs (SQL literals) that replace the defaults of a valid credit recorded from a decision of the first reservation
  local -A v=([credit_balance_id]="gen_random_uuid()" [tenant_id]="'$tenant'" [source_reservation_id]="'$cb_res1'" [credit_origin]="'CUSTOMER_CANCELLATION'"
    [amount_cents]=80000 [source_financial_decision_id]="'$cb_dec1'" [source_payment_attempt_id]="NULL" [recorded_at]="now()" [recorded_by]="'$actor'")
  while [ $# -ge 2 ]; do v[$1]="$2"; shift 2; done
  echo "insert into $cb_t (credit_balance_id, tenant_id, source_reservation_id, credit_origin, amount_cents, source_financial_decision_id, source_payment_attempt_id, recorded_at, recorded_by) values (${v[credit_balance_id]}, ${v[tenant_id]}, ${v[source_reservation_id]}, ${v[credit_origin]}, ${v[amount_cents]}, ${v[source_financial_decision_id]}, ${v[source_payment_attempt_id]}, ${v[recorded_at]}, ${v[recorded_by]})"
}
cb_apply() { # column/value pairs (SQL literals) that replace the defaults of a valid application of the first credit to the second reservation
  local -A v=([credit_balance_application_id]="gen_random_uuid()" [credit_balance_id]="'$cb_ok'" [tenant_id]="'$tenant'" [target_reservation_id]="'$cb_res2'"
    [applied_amount_cents]=30000 [applied_at]="now()" [applied_by]="'$actor'" [applied_by_kind]="'STAFF'")
  while [ $# -ge 2 ]; do v[$1]="$2"; shift 2; done
  echo "insert into $cb_ap (credit_balance_application_id, credit_balance_id, tenant_id, target_reservation_id, applied_amount_cents, applied_at, applied_by, applied_by_kind) values (${v[credit_balance_application_id]}, ${v[credit_balance_id]}, ${v[tenant_id]}, ${v[target_reservation_id]}, ${v[applied_amount_cents]}, ${v[applied_at]}, ${v[applied_by]}, ${v[applied_by_kind]})"
}

echo 'HU-COM-017 db - base: the 130 changesets that exist before the story, with the probe rows'
liquibase rollback-count 999 >/dev/null
db_labels='!HU-COM-017 and !HU-COM-019 and !HU-COM-018 and !HU-COM-020 and !decision-resume and !episode-frozen-total and !departure-order and !exceptional-access-use and !reservation-confirmed-value and !payment-parameters-changed and !account-session-cutoff and !restricted-access-reason and !establishment-contact-log and !rescheduling-proposed-notice and !fk-tenant-composite and !cancellation-penalty-policy and !vehicle-total-capacity'
liquibase update >/dev/null
cb_base="$(snapshot)"
cb_base_objects="$(sql "select (select count(*) from pg_tables where schemaname='$SCHEMA') || '|' || (select count(*) from pg_proc where pronamespace='$SCHEMA'::regnamespace) || '|' || (select count(*) from pg_trigger where not tgisinternal and tgrelid in (select oid from pg_class where relnamespace='$SCHEMA'::regnamespace))" 2>/dev/null || true)"
check 'base holds exactly 130 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 130 ]; echo $?)"
sql "insert into $SCHEMA.customer (customer_id, tenant_id, full_name, created_at, document_number, birth_date_or_age, contact_info, status, terms_accepted, terms_accepted_at) values ('$cb_cust', '$tenant', 'Credit probe A', now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE', true, now()), ('$cb_cust2', '$tenant', 'Credit probe B', now(), 'enc:v1:x2', 'enc:v1:y2', '{}'::jsonb, 'ACTIVE', true, now());
     insert into $SCHEMA.catalog_service (service_id, tenant_id, service_type, commercial_name, catalog_status, base_rate_cents, base_operational_cost_cents, configured_capacity, transport_required, high_risk, created_at, updated_at) values ('$cb_svc', '$tenant', 'TOUR', 'Credit probe tour', 'ACTIVE', 150000, 90000, 12, false, false, now(), now())" >/dev/null 2>&1 || true
engine "$(rs_row reservation_id "'$cb_res1'" customer_id "'$cb_cust'" service_id "'$cb_svc'"); $(rs_row reservation_id "'$cb_res2'" customer_id "'$cb_cust'" service_id "'$cb_svc'"); $(rs_row reservation_id "'$cb_res3'" customer_id "'$cb_cust2'" service_id "'$cb_svc'");" >/dev/null || true
engine "$(fd_row financial_decision_id "'$cb_dec1'" reservation_id "'$cb_res1'"); $(fd_row financial_decision_id "'$cb_dec2'" reservation_id "'$cb_res1'" decision_kind "'MODIFICATION_EXCESS'" penalty_amount_cents NULL);" >/dev/null || true
engine "$(pa_attempt payment_attempt_id "'$cb_att1'" reservation_id "'$cb_res1'"); $(pa_attempt payment_attempt_id "'$cb_att2'" reservation_id "'$cb_res1'");" >/dev/null || true
check 'the probe reservations, decisions and attempts exist on the base' "$([ "$(cb_sql "select (select count(*) from $SCHEMA.reservation where reservation_id in ('$cb_res1','$cb_res2','$cb_res3')) || '|' || (select count(*) from $cb_fd where financial_decision_id in ('$cb_dec1','$cb_dec2')) || '|' || (select count(*) from $cb_pa where payment_attempt_id in ('$cb_att1','$cb_att2'))")" = '3|2|2' ]; echo $?)"

echo 'HU-COM-017 db - probes written first: red before the changesets, green after'
db_labels='HU-COM-017 and !credit-balance-guards'
liquibase update >/dev/null
check 'the changesets of the story bring the control table to 136' "$([ "$(sql "select count(*) from $CONTROL")" = 136 ]; echo $?)"

echo 'aCreditRequiresEveryFieldAClosedOriginAndTheRightSource (AC-D17.2, AC-D17.3)'
cb_accepted "$(cb_row credit_balance_id "'$cb_ok'")" 'a credit from a cancellation decision'
cb_refusal "$(cb_row source_reservation_id NULL);" 'null value in column "source_reservation_id".*not-null constraint' 'a credit without reservation'
cb_refusal "$(cb_row tenant_id NULL);" 'null value in column "tenant_id".*not-null constraint' 'a credit without tenant'
cb_refusal "$(cb_row credit_origin NULL);" 'null value in column "credit_origin".*not-null constraint' 'a credit without origin'
cb_refusal "$(cb_row amount_cents NULL);" 'null value in column "amount_cents".*not-null constraint' 'a credit without amount'
cb_refusal "$(cb_row recorded_at NULL);" 'null value in column "recorded_at".*not-null constraint' 'a credit without instant'
cb_refusal "$(cb_row recorded_by NULL);" 'null value in column "recorded_by".*not-null constraint' 'a credit without author'
cb_refusal "$(cb_row credit_origin "'GIFT'");" chk_credit_balance_origin 'an origin outside the four codes'
cb_refusal "$(cb_row amount_cents 0);" chk_credit_balance_amount_positive 'a credit of zero'
cb_refusal "$(cb_row amount_cents -5);" chk_credit_balance_amount_positive 'a negative credit'
cb_refusal "$(cb_row source_reservation_id "'$(aid 6099)'" source_financial_decision_id "'$cb_dec2'");" fk_credit_balance_reservation 'a credit for a reservation that does not exist'
cb_refusal "$(cb_row source_financial_decision_id "'$(aid 6098)'");" fk_credit_balance_decision 'a credit for a decision that does not exist'
cb_refusal "$(cb_row credit_origin "'PAYMENT_EXCESS'" source_financial_decision_id "'$cb_dec2'" source_payment_attempt_id "'$cb_att1'");" chk_credit_balance_source 'an excess credit that carries a decision'
cb_refusal "$(cb_row credit_origin "'PAYMENT_EXCESS'" source_financial_decision_id NULL);" chk_credit_balance_source 'an excess credit without an attempt'
cb_refusal "$(cb_row source_financial_decision_id NULL source_payment_attempt_id "'$cb_att1'");" chk_credit_balance_source 'a decision credit that carries an attempt instead of a decision'
cb_refusal "$(cb_row source_payment_attempt_id "'$(aid 6097)'" credit_origin "'PAYMENT_EXCESS'" source_financial_decision_id NULL);" fk_credit_balance_payment_attempt 'an excess credit for an attempt that does not exist'
cb_accepted "$(cb_row credit_balance_id "'$cb_ok2'" credit_origin "'PAYMENT_EXCESS'" source_financial_decision_id NULL source_payment_attempt_id "'$cb_att1'" amount_cents 15000)" 'an excess credit from a validated attempt'
check 'no column of the credit table has a DEFAULT' "$([ "$(cb_sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='credit_balance' and column_default is not null")" = 0 ]; echo $?)"

echo 'oneCreditPerDecisionAndOnePerAttempt (AC-D17.4)'
cb_refusal "$(cb_row);" uq_credit_balance_decision 'a second credit for the same decision'
cb_refusal "$(cb_row credit_origin "'PAYMENT_EXCESS'" source_financial_decision_id NULL source_payment_attempt_id "'$cb_att1'");" uq_credit_balance_payment_attempt 'a second credit for the same attempt'
cb_accepted "$(cb_row credit_balance_id "'$cb_ok3'" source_financial_decision_id "'$cb_dec2'" credit_origin "'MODIFICATION_EXCESS'" amount_cents 5000)" 'a credit for another decision'

echo 'anApplicationRequiresEveryFieldAndAPositiveAmount (AC-D17.5)'
cb_accepted "$(cb_apply credit_balance_application_id "'$cb_app'")" 'an application of part of the credit to another reservation'
cb_refusal "$(cb_apply credit_balance_id NULL);" 'null value in column "credit_balance_id".*not-null constraint' 'an application without credit'
cb_refusal "$(cb_apply tenant_id NULL);" 'null value in column "tenant_id".*not-null constraint' 'an application without tenant'
cb_refusal "$(cb_apply target_reservation_id NULL);" 'null value in column "target_reservation_id".*not-null constraint' 'an application without target'
cb_refusal "$(cb_apply applied_amount_cents NULL);" 'null value in column "applied_amount_cents".*not-null constraint' 'an application without amount'
cb_refusal "$(cb_apply applied_at NULL);" 'null value in column "applied_at".*not-null constraint' 'an application without instant'
cb_refusal "$(cb_apply applied_by NULL);" 'null value in column "applied_by".*not-null constraint' 'an application without author'
cb_refusal "$(cb_apply applied_by_kind NULL);" 'null value in column "applied_by_kind".*not-null constraint' 'an application without kind'
cb_refusal "$(cb_apply applied_amount_cents 0);" chk_credit_balance_application_amount_positive 'an application of zero'
cb_refusal "$(cb_apply applied_by_kind "'ROBOT'");" chk_credit_balance_application_kind 'a kind outside CUSTOMER and STAFF'
cb_refusal "$(cb_apply credit_balance_id "'$(aid 6096)'");" fk_credit_balance_application_credit 'an application of a credit that does not exist'
cb_refusal "$(cb_apply target_reservation_id "'$(aid 6095)'");" fk_credit_balance_application_reservation 'an application to a reservation that does not exist'
cb_accepted "$(cb_apply applied_by_kind "'CUSTOMER'")" 'an application made by the customer'
check 'no column of the application table has a DEFAULT' "$([ "$(cb_sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='credit_balance_application' and column_default is not null")" = 0 ]; echo $?)"

echo 'aCreditAndAnApplicationCannotBeUpdatedOrDeleted (AC-D17.6)'
cb_refusal "update $cb_t set amount_cents = 1 where credit_balance_id = '$cb_ok';" 'permission denied for table credit_balance' 'an update of a credit'
cb_refusal "delete from $cb_t where credit_balance_id = '$cb_ok';" 'permission denied for table credit_balance' 'a delete of a credit'
cb_refusal "update $cb_ap set applied_amount_cents = 1 where credit_balance_application_id = '$cb_app';" 'permission denied for table credit_balance_application' 'an update of an application'
cb_refusal "delete from $cb_ap where credit_balance_application_id = '$cb_app';" 'permission denied for table credit_balance_application' 'a delete of an application'

echo 'aCreditRequestReferencesAnExistingCredit (AC-D17.9)'
cb_refusal "$(fd_row reservation_id "'$cb_res1'" decision_kind "'CREDIT_BALANCE_REFUND_REQUEST'" credit_balance_id "'$(aid 6094)'" base_amount_cents 10000 penalty_amount_cents NULL);" fk_financial_decision_credit_balance 'a refund request for a credit that does not exist'
cb_accepted "$(fd_row financial_decision_id "'$cb_dec_rq'" reservation_id "'$cb_res1'" decision_kind "'CREDIT_BALANCE_REFUND_REQUEST'" credit_balance_id "'$cb_ok'" base_amount_cents 10000 penalty_amount_cents NULL)" 'a refund request for an existing credit'

echo 'onlyThePlannedObjectsAreAddedAndRevertLeavesNoTrace, slice 1 (AC-D17.1, AC-D17.13)'
cb_objects="$(sql "select (select count(*) from pg_tables where schemaname='$SCHEMA') || '|' || (select count(*) from pg_proc where pronamespace='$SCHEMA'::regnamespace) || '|' || (select count(*) from pg_trigger where not tgisinternal and tgrelid in (select oid from pg_class where relnamespace='$SCHEMA'::regnamespace))" 2>/dev/null || true)"
IFS='|' read -r cb_bt cb_bf cb_bg <<< "$cb_base_objects"
check 'AC-D17.1 exactly the two planned tables were added to the base, and no function or trigger yet' "$([ -n "$cb_base_objects" ] && [ "$cb_objects" = "$((cb_bt + 2))|$cb_bf|$cb_bg" ]; echo $?)"
check 'AC-D17.1 the two unique keys, the foreign key from the decision and the revokes exist' "$([ "$(cb_sql "select count(*) from pg_indexes where schemaname='$SCHEMA' and indexname in ('uq_credit_balance_decision','uq_credit_balance_payment_attempt')")" = 2 ] && [ "$(cb_sql "select count(*) from pg_constraint where conname='fk_financial_decision_credit_balance'")" = 1 ] && [ "$(cb_sql "select has_table_privilege('commercial_reservation_writer','$cb_t','UPDATE') or has_table_privilege('commercial_reservation_writer','$cb_ap','UPDATE')")" = f ]; echo $?)"
check 'AC-D17.1 nothing new appears in public' "$([ "$(sql "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p','v','m','S','f') and c.relname not like 'databasechangelog%'")" = 0 ]; echo $?)"
cb_second="$(liquibase update 2>&1)"; printf '%s\n' "$cb_second"
check 'AC-D17.13 a second update applies zero changesets' "$(printf '%s\n' "$cb_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
sql "delete from $cb_fd where financial_decision_id = '$cb_dec_rq'" >/dev/null 2>&1 || true
sql "delete from $cb_ap; delete from $cb_t" >/dev/null 2>&1 || true
sql "delete from $cb_fd where financial_decision_id in ('$cb_dec1','$cb_dec2'); delete from $cb_pa where payment_attempt_id in ('$cb_att1','$cb_att2'); delete from $SCHEMA.reservation where reservation_id in ('$cb_res1','$cb_res2','$cb_res3'); delete from $SCHEMA.catalog_service where service_id = '$cb_svc'; delete from $SCHEMA.customer where customer_id in ('$cb_cust','$cb_cust2')" >/dev/null 2>&1 || true
check 'the rows of the probes are gone before the revert' "$([ "$(sql "select (select count(*) from $cb_t) + (select count(*) from $cb_ap) + (select count(*) from $SCHEMA.reservation where reservation_id in ('$cb_res1','$cb_res2','$cb_res3'))")" = 0 ]; echo $?)"
cb_n="$(sql "select count(*) from $CONTROL where labels ilike '%HU-COM-017%'" 2>/dev/null || echo 0)"
liquibase rollback-count "$cb_n"
cb_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$cb_base" "$cb_reverted"
check 'AC-D17.13 the revert of the slice restores columns, constraints, indexes and privileges exactly and leaves 130 changesets' "$([ -n "$cb_base" ] && [ "$cb_reverted" = "$cb_base" ] && [ "$(sql "select count(*) from $CONTROL")" = 130 ]; echo $?)"
check 'the two tables are gone after the revert' "$([ "$(cb_sql "select count(*) from pg_tables where schemaname='$SCHEMA' and tablename in ('credit_balance','credit_balance_application')")" = 0 ]; echo $?)"
db_labels='HU-COM-017 and !credit-balance-guards'
liquibase update >/dev/null
check 'the changesets of the story reapply to 136' "$([ "$(sql "select count(*) from $CONTROL")" = 136 ]; echo $?)"
