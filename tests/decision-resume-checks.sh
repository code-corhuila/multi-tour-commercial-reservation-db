#!/usr/bin/env bash
# Sourced by db-ci.sh after tenant-suspension-checks.sh, on the same disposable PostgreSQL instance, with the 177 changesets that exist before the slice.
# HU-COM-020 -db (issue code-corhuila/multi-tour-docs#186), the resume of the 24-hour financial decisions (AC-20.5, AC-20.7): a decision that was frozen by the inactivation of its tenant resumes with the
# time it had left, and the db keeps the shifted due instant in financial_decision.resumed_due_at (recognized_at is immutable). Every changeset of the slice is labelled decision-resume. Probes are written
# first: red before the changesets, green after (Annex J.1). The rows of the probes are removed by the owner at the end.
dr_t="$SCHEMA.financial_decision"
dr_cust="$(aid 8301)"; dr_svc="$(aid 8303)"; dr_res="$(aid 8310)"; dr_d1="$(aid 8320)"; dr_d2="$(aid 8321)"
dr_sql() { sql "$1" 2>/dev/null || true; }
dr_refusal() { # SQL, text of the engine answer, description
  local answer
  answer="$(engine "$1" 2>&1 || true)"; printf '%s\n' "$answer"
  check "HU-COM-020 db: $3 is refused by $2" "$(printf '%s\n' "$answer" | grep -q "$2"; echo $?)"
}
dr_accepted() { # SQL, description
  local status=0
  engine "$1" >/dev/null || status=$?
  check "HU-COM-020 db: $2 is accepted" "$status"
}
dr_explain() { printf '%s\n' 'set enable_seqscan = off;' "explain $1;" | docker exec -i -e PGPASSWORD "$container" psql -X -U postgres -d postgres 2>&1 || true; }
dr_decision() { # decision id, reservation id, kind
  echo "insert into $dr_t (financial_decision_id, tenant_id, reservation_id, credit_balance_id, decision_kind, base_amount_cents, penalty_amount_cents, recognized_at) values ('$1', '$tenant', '$2', NULL, '$3', 100000, $4, now() - interval '3 hours')"
}

echo 'HU-COM-020 db decision resume - base: the 177 changesets that exist before the slice, with the probe rows'
liquibase rollback-count 999 >/dev/null
db_labels='!decision-resume and !episode-frozen-total and !departure-order and !exceptional-access-use and !reservation-confirmed-value and !payment-parameters-changed and !account-session-cutoff and !restricted-access-reason and !rescheduling-proposed-notice and !fk-tenant-composite'
liquibase update >/dev/null
dr_base="$(snapshot)"
check 'base holds exactly 177 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 177 ]; echo $?)"
sql "insert into $SCHEMA.customer (customer_id, tenant_id, full_name, created_at, document_number, birth_date_or_age, contact_info, status, terms_accepted, terms_accepted_at) values ('$dr_cust', '$tenant', 'Resume probe', now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE', true, now());
     insert into $SCHEMA.catalog_service (service_id, tenant_id, service_type, commercial_name, catalog_status, base_rate_cents, base_operational_cost_cents, configured_capacity, transport_required, high_risk, created_at, updated_at) values ('$dr_svc', '$tenant', 'TOUR', 'Resume probe tour', 'ACTIVE', 150000, 90000, 12, false, false, now(), now())" >/dev/null 2>&1 || true
engine "$(rs_row reservation_id "'$dr_res'" customer_id "'$dr_cust'" service_id "'$dr_svc'");" >/dev/null || true
check 'the probe reservation exists on the base' "$([ "$(dr_sql "select count(*) from $SCHEMA.reservation where reservation_id = '$dr_res'")" = 1 ]; echo $?)"

echo 'HU-COM-020 db decision resume - probes written first: red before the changesets, green after'
db_labels='decision-resume'
liquibase update >/dev/null
check 'the changesets of the slice bring the control table to 179' "$([ "$(sql "select count(*) from $CONTROL")" = 179 ]; echo $?)"

echo 'aResumedDecisionKeepsItsShiftedDueInstant (AC-20.5, AC-20.7)'
dr_accepted "$(dr_decision "$dr_d1" "$dr_res" CUSTOMER_CANCELLATION 20000)" 'an open decision with no shifted due instant'
dr_accepted "update $dr_t set frozen_at = now() - interval '1 hour', remaining_at_freeze_minutes = 1260 where financial_decision_id = '$dr_d1'" 'the freeze of the open decision'
dr_accepted "update $dr_t set frozen_at = NULL, remaining_at_freeze_minutes = NULL, resumed_due_at = now() + interval '21 hours' where financial_decision_id = '$dr_d1'" 'the resume that keeps the shifted due instant'
dr_refusal "update $dr_t set resumed_due_at = now() - interval '4 hours' where financial_decision_id = '$dr_d1';" chk_financial_decision_resumed_due 'a shifted due instant before the recognition'
dr_refusal "update $dr_t set recognized_at = now() where financial_decision_id = '$dr_d1';" trg_financial_decision_guard 'a change of the recognition instant'
check 'no column of the decision table gained a DEFAULT' "$([ "$(dr_sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='financial_decision' and column_name='resumed_due_at' and column_default is not null")" = 0 ]; echo $?)"
dr_accepted "$(dr_decision "$dr_d2" "$dr_res" PENDING_TREATMENT NULL)" 'another open decision of the reservation'
dr_accepted "update $dr_t set outcome = 'REFUND_FULL', decided_by_system = true, decided_at = now() where financial_decision_id = '$dr_d2'" 'the decision of the second row'
dr_refusal "update $dr_t set resumed_due_at = now() + interval '1 hour' where financial_decision_id = '$dr_d2';" trg_financial_decision_guard 'a shifted due instant written on a decided decision'

echo 'theDueReadOfAResumedDecisionUsesItsIndex (AC-D16.13 for the resumed ones)'
dr_p="$(dr_explain "select 1 from $dr_t where tenant_id = '$tenant' and outcome is null and frozen_at is null and resumed_due_at is not null and resumed_due_at <= now()")"; printf '%s\n' "$dr_p"
check 'the resumed decisions that are due are read by an index led by the tenant' "$(printf '%s\n' "$dr_p" | grep -Eq 'idx_financial_decision_tenant_resumed_due|idx_financial_decision_tenant_due'; echo $?)"

echo 'onlyThePlannedColumnIsAddedSecondRunAppliesZeroAndRevertLeavesNoTrace (AC-D16.1)'
check 'nothing new appears in public' "$([ "$(sql "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p','v','m','S','f') and c.relname not like 'databasechangelog%'")" = 0 ]; echo $?)"
dr_second="$(liquibase update 2>&1)"; printf '%s\n' "$dr_second"
check 'a second update applies zero changesets' "$(printf '%s\n' "$dr_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
sql "delete from $dr_t where reservation_id = '$dr_res'; delete from $SCHEMA.reservation where reservation_id = '$dr_res'; delete from $SCHEMA.catalog_service where service_id = '$dr_svc'; delete from $SCHEMA.customer where customer_id = '$dr_cust'" >/dev/null 2>&1 || true
dr_n="$(sql "select count(*) from $CONTROL where labels ilike '%decision-resume%'" 2>/dev/null || echo 0)"
liquibase rollback-count "$dr_n"
dr_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$dr_base" "$dr_reverted"
check 'the revert restores columns, constraints, indexes and privileges exactly and leaves 177 changesets' "$([ -n "$dr_base" ] && [ "$dr_reverted" = "$dr_base" ] && [ "$(sql "select count(*) from $CONTROL")" = 177 ]; echo $?)"
db_labels='decision-resume'
liquibase update >/dev/null
check 'the changesets of the slice reapply to 179' "$([ "$(sql "select count(*) from $CONTROL")" = 179 ]; echo $?)"
