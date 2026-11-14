#!/usr/bin/env bash
# Sourced by db-ci.sh after rescheduling-proposed-notice-checks.sh, on the same disposable PostgreSQL instance, with every changeset that exists before the slice (counted at run time);
# the slice is two changesets, ddl-tables-041 and ddl-indexes-059, labelled cancellation-penalty-policy.
# HU-COM-013 DP-02a -db (docs pull request 1002): the table that holds the penalty a tenant, or one of its services, applies when the customer cancels (PDR RF-021, RN-RES-008).
# The probes run as the superuser with the foreign keys switched off where a catalog row would be needed (session_replication_role = replica); the CHECK constraints and unique
# indexes under test still apply. Probes are written first: red before the changesets, green after (Annex J.1).
cp_t="$SCHEMA.cancellation_penalty_policy"; cp_svc1="$(aid 9401)"; cp_svc2="$(aid 9402)"
cp_row() { # id, service id SQL expression, penalty, reason SQL expression, tenant SQL expression (optional)
  echo "set session_replication_role = replica; insert into $cp_t (cancellation_penalty_policy_id, tenant_id, service_id, penalty_bp, changed_by, change_reason, changed_at) values ('$(aid "$1")', ${5:-'$tenant'}, $2, $3, '$actor', $4, now())"
}
cp_refusal() { # SQL, text of the engine answer, description
  local answer
  answer="$(engine "begin; $1; rollback" postgres 2>&1 || true)"; printf '%s\n' "$answer"
  check "DP-02a db: $3 is refused by $2" "$(printf '%s\n' "$answer" | grep -q "$2"; echo $?)"
}
cp_not_null_refusal() { # SQL, NOT NULL constraint name, column, description (the engine names the column; the constraint is read from the catalog)
  local answer
  answer="$(engine "begin; $1; rollback" postgres 2>&1 || true)"; printf '%s\n' "$answer"
  check "DP-02a db: $4 is refused (SQLSTATE 23502 on $3)" "$(printf '%s\n' "$answer" | grep -q "ERROR:  23502.*column \"$3\""; echo $?)"
  check "$2 exists in the catalog as a NOT NULL constraint" "$([ "$(sql "select count(*) from pg_constraint where conrelid='$cp_t'::regclass and contype='n' and conname='$2'")" = 1 ]; echo $?)"
}
cp_accepted() { # SQL, description
  local status=0
  engine "begin; $1; rollback;" postgres >/dev/null || status=$?
  check "DP-02a db: $2 is accepted" "$status"
}

echo 'DP-02a db cancellation penalty policy - base: every changeset that exists before the slice'
liquibase rollback-count 999 >/dev/null
db_labels='!cancellation-penalty-policy and !fk-tenant-composite and !vehicle-total-capacity'
liquibase update >/dev/null
cp_base="$(snapshot)"
cp_n0="$(sql "select count(*) from $CONTROL")"
check "the base holds every changeset except the two of the slice ($cp_n0)" "$([ "$cp_n0" -gt 0 ] && [ "$(sql "select count(*) from $CONTROL where labels ilike '%cancellation-penalty-policy%'")" = 0 ]; echo $?)"
check 'on that base the table does not exist' "$([ "$(sql "select count(*) from pg_tables where schemaname='$SCHEMA' and tablename='cancellation_penalty_policy'")" = 0 ]; echo $?)"

echo 'DP-02a db cancellation penalty policy - probes written first: red before the changesets, green after'
db_labels='cancellation-penalty-policy'
liquibase update >/dev/null
check 'the slice adds two changesets to the control table' "$([ "$(sql "select count(*) from $CONTROL")" = "$((cp_n0 + 2))" ]; echo $?)"

echo 'thePenaltyPolicyTableHoldsTheLastChangeOfATenantOrOfAService'
check 'the table has the seven planned columns, service_id nullable, no DEFAULT anywhere' "$([ "$(sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='cancellation_penalty_policy' and column_default is null and column_name in ('cancellation_penalty_policy_id','tenant_id','service_id','penalty_bp','changed_by','change_reason','changed_at')")" = 7 ] && [ "$(sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='cancellation_penalty_policy'")" = 7 ] && [ "$(sql "select is_nullable from information_schema.columns where table_schema='$SCHEMA' and table_name='cancellation_penalty_policy' and column_name='service_id'")" = YES ]; echo $?)"
check 'the only foreign key is fk_cancellation_penalty_policy_service, to catalog_service, ON DELETE RESTRICT' "$([ "$(sql "select string_agg(conname || '->' || confrelid::regclass::text || '(' || confdeltype::text || ')', ',') from pg_constraint where conrelid='$cp_t'::regclass and contype='f'")" = "fk_cancellation_penalty_policy_service->$SCHEMA.catalog_service(r)" ]; echo $?)"
cp_accepted "$(cp_row 1 'null' 5000 "'Seasonal commercial policy'")" 'a tenant-level row of 50 %'
cp_accepted "$(cp_row 2 "'$cp_svc1'" 0 "'No penalty for this tour'")" 'a service row of 0 (no penalty)'
cp_accepted "$(cp_row 3 "'$cp_svc1'" 10000 "'Non refundable'")" 'a service row of 10 000 (the whole validated value)'
cp_accepted "$(cp_row 4 'null' 5000 "'Seasonal commercial policy'"); $(cp_row 5 "'$cp_svc1'" 2000 "'This tour is softer'"); $(cp_row 6 "'$cp_svc2'" 3000 "'Another tour'")" 'a tenant row beside two service rows'

echo 'thePenaltyPolicyRefusesWhatTheEngineCanRefuse'
cp_refusal "$(cp_row 7 'null' -1 "'x'")" 'chk_cancellation_penalty_policy_penalty' 'a penalty below 0'
cp_refusal "$(cp_row 8 'null' 10001 "'x'")" 'chk_cancellation_penalty_policy_penalty' 'a penalty above 10 000'
cp_not_null_refusal "$(cp_row 9 'null' null "'x'")" chk_cancellation_penalty_policy_penalty_required penalty_bp 'a row with no penalty'
cp_refusal "$(cp_row 10 'null' 5000 "'   '")" 'chk_cancellation_penalty_policy_change_reason' 'a blank reason'
cp_not_null_refusal "$(cp_row 11 'null' 5000 'null')" chk_cancellation_penalty_policy_change_reason_required change_reason 'a row with no reason'
cp_not_null_refusal "$(cp_row 12 'null' 5000 "'x'" 'null')" chk_cancellation_penalty_policy_tenant_required tenant_id 'a row with no tenant'
cp_refusal "$(cp_row 13 'null' 5000 "'x'"); $(cp_row 14 'null' 3000 "'y'")" 'uq_cancellation_penalty_policy_tenant' 'a second tenant-level row of the same tenant'
cp_refusal "$(cp_row 15 "'$cp_svc1'" 5000 "'x'"); $(cp_row 16 "'$cp_svc1'" 3000 "'y'")" 'uq_cancellation_penalty_policy_tenant_service' 'a second row for the same service'
cp_accepted "$(cp_row 17 'null' 5000 "'x'"); $(cp_row 18 'null' 3000 "'y'" "'$(aid 2)'")" 'a tenant-level row for each of two tenants'
check 'a row of a service that does not exist is refused when the foreign keys are on' "$([ "$(engine "insert into $cp_t (cancellation_penalty_policy_id, tenant_id, service_id, penalty_bp, changed_by, change_reason, changed_at) values ('$(aid 19)', '$tenant', '$(aid 9499)', 5000, '$actor', 'x', now())" postgres 2>&1 | grep -c 'fk_cancellation_penalty_policy_service')" -ge 1 ]; echo $?)"

echo 'theApplicationUserWritesAndReadsButNeverDeletes'
cp_app_ok=0; engine "begin; $(cp_row 20 'null' 5000 "'x'"); set role $app; update $cp_t set penalty_bp = 2500 where cancellation_penalty_policy_id = '$(aid 20)'; select count(*) from $cp_t; rollback" postgres >/dev/null || cp_app_ok=$?
check 'the application user updates and reads the table' "$cp_app_ok"
cp_del="$(engine "begin; $(cp_row 21 'null' 5000 "'x'"); set role $app; delete from $cp_t where cancellation_penalty_policy_id = '$(aid 21)'; rollback" postgres 2>&1 || true)"
check 'the application user cannot DELETE a row (the engine says permission denied)' "$(printf '%s\n' "$cp_del" | grep -q 'permission denied'; echo $?)"

echo 'secondRunAppliesZeroAndRevertLeavesNoTrace'
check 'nothing new appears in public' "$([ "$(sql "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p','v','m','S','f') and c.relname not like 'databasecha%'")" = 0 ]; echo $?)"
cp_second="$(liquibase update 2>&1)"; printf '%s\n' "$cp_second"
check 'a second update applies zero changesets' "$(printf '%s\n' "$cp_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
liquibase rollback-count 2
cp_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$cp_base" "$cp_reverted"
check 'the revert restores columns, constraints, indexes and privileges exactly and leaves the base changesets' "$([ -n "$cp_base" ] && [ "$cp_reverted" = "$cp_base" ] && [ "$(sql "select count(*) from $CONTROL")" = "$cp_n0" ]; echo $?)"
db_labels='cancellation-penalty-policy'
liquibase update >/dev/null
check 'the two changesets of the slice reapply' "$([ "$(sql "select count(*) from $CONTROL")" = "$((cp_n0 + 2))" ]; echo $?)"
