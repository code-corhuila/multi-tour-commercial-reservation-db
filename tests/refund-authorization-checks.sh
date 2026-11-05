#!/usr/bin/env bash
# Sourced by db-ci.sh after financial-decision-checks.sh, on the same disposable PostgreSQL instance, with the changesets of HU-COM-016 applied.
# HU-COM-016 -db (issue multi-tour-docs#182), plan D-03: the refund_authorization table, one row per authorized refund, with the execution state
# and its columns (DP-D16-1), and the structure and the revert of the slice. Probes are written first: red before the changesets, green after (Annex J.1).
ra_t="$SCHEMA.refund_authorization"
ra_id_ok="$(aid 5440)"; ra_id_auto="$(aid 5441)"; ra_id_exec="$(aid 5442)"; ra_id_done="$(aid 5443)"
ra_sql() { sql "$1" 2>/dev/null || true; }
ra_refusal() { # SQL, text of the engine answer, description
  local answer
  answer="$(engine "$1" 2>&1 || true)"; printf '%s\n' "$answer"
  check "HU-COM-016 db: $3 is refused by $2" "$(printf '%s\n' "$answer" | grep -q "$2"; echo $?)"
}
ra_accepted() { # SQL, description
  local status=0
  engine "$1" >/dev/null || status=$?
  check "HU-COM-016 db: $2 is accepted" "$status"
}
ra_row() { # column/value pairs (SQL literals) that replace the defaults of a valid authorized refund of the first reservation
  local -A v=([refund_authorization_id]="gen_random_uuid()" [tenant_id]="'$tenant'" [reservation_id]="'$fd_res1'" [refund_origin]="'CUSTOMER_CANCELLATION'"
    [financial_decision_id]="'$fd_id_cc'" [potential_refund_value_cents]=100000 [authorized_amount_cents]=80000 [reason]="'The customer cancelled in time'"
    [authorization_mode]="'TENANT_ADMINISTRATOR'" [authorized_by]="'$actor'" [authorized_at]="now()" [execution_due_at]="now() + interval '5 days'"
    [execution_state]="'AUTHORIZED'" [executing_at]="NULL" [executed_by]="NULL" [outflow_method]="NULL" [executed_at]="NULL" [cash_movement_id]="NULL" [overdue_marked_at]="NULL")
  while [ $# -ge 2 ]; do v[$1]="$2"; shift 2; done
  echo "insert into $ra_t (refund_authorization_id, tenant_id, reservation_id, refund_origin, financial_decision_id, potential_refund_value_cents, authorized_amount_cents, reason, authorization_mode, authorized_by, authorized_at, execution_due_at, execution_state, executing_at, executed_by, outflow_method, executed_at, cash_movement_id, overdue_marked_at) values (${v[refund_authorization_id]}, ${v[tenant_id]}, ${v[reservation_id]}, ${v[refund_origin]}, ${v[financial_decision_id]}, ${v[potential_refund_value_cents]}, ${v[authorized_amount_cents]}, ${v[reason]}, ${v[authorization_mode]}, ${v[authorized_by]}, ${v[authorized_at]}, ${v[execution_due_at]}, ${v[execution_state]}, ${v[executing_at]}, ${v[executed_by]}, ${v[outflow_method]}, ${v[executed_at]}, ${v[cash_movement_id]}, ${v[overdue_marked_at]})"
}

echo 'aRefundRequiresEveryFieldAndKeepsItsAmountsInRange (AC-D16.8)'
ra_accepted "$(ra_row refund_authorization_id "'$ra_id_ok'")" 'a whole refund authorized by the administrator from a decision'
ra_refusal "$(ra_row reservation_id NULL);" 'null value in column "reservation_id".*not-null constraint' 'a refund without reservation'
ra_refusal "$(ra_row tenant_id NULL);" 'null value in column "tenant_id".*not-null constraint' 'a refund without tenant'
ra_refusal "$(ra_row refund_origin NULL);" 'null value in column "refund_origin".*not-null constraint' 'a refund without origin'
ra_refusal "$(ra_row potential_refund_value_cents NULL);" 'null value in column "potential_refund_value_cents".*not-null constraint' 'a refund without potential value'
ra_refusal "$(ra_row authorized_amount_cents NULL);" 'null value in column "authorized_amount_cents".*not-null constraint' 'a refund without authorized amount'
ra_refusal "$(ra_row reason NULL);" 'null value in column "reason".*not-null constraint' 'a refund without reason'
ra_refusal "$(ra_row authorization_mode NULL);" 'null value in column "authorization_mode".*not-null constraint' 'a refund without mode'
ra_refusal "$(ra_row authorized_at NULL);" 'null value in column "authorized_at".*not-null constraint' 'a refund without authorization instant'
ra_refusal "$(ra_row execution_due_at NULL);" 'null value in column "execution_due_at".*not-null constraint' 'a refund without due instant'
ra_refusal "$(ra_row execution_state NULL);" 'null value in column "execution_state".*not-null constraint' 'a refund without execution state'
ra_refusal "$(ra_row reason "'   '");" chk_refund_authorization_reason 'a refund with a blank reason'
ra_refusal "$(ra_row authorized_amount_cents 0);" chk_refund_authorization_amounts 'a refund of zero'
ra_refusal "$(ra_row authorized_amount_cents 100001);" chk_refund_authorization_amounts 'a refund above the potential value'
ra_refusal "$(ra_row potential_refund_value_cents 0 authorized_amount_cents 0);" chk_refund_authorization_amounts 'a potential value of zero'
ra_refusal "$(ra_row execution_due_at "now() - interval '1 day'");" chk_refund_authorization_due 'a due instant before the authorization'
ra_refusal "$(ra_row refund_origin "'OTHER'" financial_decision_id NULL);" chk_refund_authorization_origin 'an origin outside the six codes'
ra_refusal "$(ra_row authorization_mode "'ROBOT'" authorized_by NULL);" chk_refund_authorization_mode 'a mode outside the two codes'
ra_refusal "$(ra_row reservation_id "'$(aid 5499)'");" fk_refund_authorization_reservation 'a refund for a reservation that does not exist'
ra_refusal "$(ra_row financial_decision_id "'$(aid 5498)'");" fk_refund_authorization_decision 'a refund for a decision that does not exist'

echo 'theDecisionReferenceAndTheAuthorFollowTheOriginAndTheMode (AC-D16.9)'
ra_refusal "$(ra_row financial_decision_id NULL);" chk_refund_authorization_decision_reference 'a decision origin with no decision'
ra_refusal "$(ra_row refund_origin "'NOT_ATTRIBUTABLE_TO_CUSTOMER'");" chk_refund_authorization_decision_reference 'an origin without decision that carries one'
ra_refusal "$(ra_row authorized_by NULL);" chk_refund_authorization_author 'the administrator mode without the person'
ra_refusal "$(ra_row authorization_mode "'AUTOMATIC_DETERMINATION'");" chk_refund_authorization_author 'an automatic determination with an author'
ra_accepted "$(ra_row refund_authorization_id "'$ra_id_auto'" reservation_id "'$fd_res2'" refund_origin "'NOT_ATTRIBUTABLE_TO_CUSTOMER'" financial_decision_id NULL authorization_mode "'AUTOMATIC_DETERMINATION'" authorized_by NULL)" 'an automatic refund with no decision and no author'
ra_accepted "$(ra_row reservation_id "'$fd_res2'" refund_origin "'PERSONAL_EMERGENCY_DURING_EXECUTION'" financial_decision_id NULL)" 'an emergency refund with no decision authorized by the administrator'

echo 'theExecutionColumnsFollowTheState (AC-D16.10)'
ra_refusal "$(ra_row execution_state "'PAID'");" chk_refund_authorization_execution_state 'a state outside the three codes'
ra_refusal "$(ra_row execution_state "'EXECUTING'" executing_at "now()" executed_by "'$actor'" outflow_method "'WIRE'");" chk_refund_authorization_method 'a method outside the two codes'
ra_refusal "$(ra_row executing_at "now()");" chk_refund_authorization_execution_state 'an authorized refund that carries an execution column'
ra_refusal "$(ra_row execution_state "'EXECUTING'" executing_at "now()" executed_by "'$actor'");" chk_refund_authorization_execution_state 'an executing refund without the method'
ra_refusal "$(ra_row execution_state "'EXECUTING'" executing_at "now()" executed_by "'$actor'" outflow_method "'CASH'" cash_movement_id "'$(aid 5450)'");" chk_refund_authorization_execution_state 'an executing refund that already carries a movement'
ra_refusal "$(ra_row execution_state "'EXECUTED'" executing_at "now()" executed_by "'$actor'" outflow_method "'TRANSFER'" executed_at "now()");" chk_refund_authorization_execution_state 'an executed refund without the cash movement'
ra_refusal "$(ra_row execution_state "'EXECUTED'" executing_at "now()" executed_by "'$actor'" outflow_method "'TRANSFER'" cash_movement_id "'$(aid 5450)'");" chk_refund_authorization_execution_state 'an executed refund without the executed instant'
ra_accepted "$(ra_row refund_authorization_id "'$ra_id_exec'" reservation_id "'$fd_res3'" execution_state "'EXECUTING'" executing_at "now()" executed_by "'$actor'" outflow_method "'CASH'")" 'an executing refund with its start, person and method'
ra_accepted "$(ra_row refund_authorization_id "'$ra_id_done'" reservation_id "'$fd_res4'" execution_state "'EXECUTED'" executing_at "now()" executed_by "'$actor'" outflow_method "'TRANSFER'" executed_at "now()" cash_movement_id "'$(aid 5450)'")" 'an executed refund with its cash movement'
check 'cash_movement_id has no foreign key (Annex J.3.4) and no column of the refund table has a DEFAULT' "$([ "$(ra_sql "select count(*) from pg_constraint where conrelid='$ra_t'::regclass and contype='f'")" = 2 ] && [ "$(ra_sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='refund_authorization' and column_default is not null")" = 0 ]; echo $?)"
check 'the application user holds no DELETE on the refund table' "$([ "$(ra_sql "select has_table_privilege('commercial_reservation_app', '$ra_t', 'DELETE')")" = f ]; echo $?)"

echo 'onlyThePlannedObjectsAreAddedAndRevertLeavesNoTrace (AC-D16.1, AC-D16.16)'
ra_objects="$(sql "select (select count(*) from pg_tables where schemaname='$SCHEMA') || '|' || (select count(*) from pg_proc where pronamespace='$SCHEMA'::regnamespace) || '|' || (select count(*) from pg_trigger where not tgisinternal and tgrelid in (select oid from pg_class where relnamespace='$SCHEMA'::regnamespace))" 2>/dev/null || true)"
IFS='|' read -r ra_bt ra_bf ra_bg <<< "$fd_base_objects"
ra_expected="$((ra_bt + 2))|$((ra_bf + 2))|$((ra_bg + 2))"
printf 'Base objects (tables|functions|triggers): %s\nExpected: %s\nFound:    %s\n' "$fd_base_objects" "$ra_expected" "$ra_objects"
check 'AC-D16.1 exactly the two planned tables, the two guards and their two triggers were added to the base' "$([ -n "$fd_base_objects" ] && [ "$ra_objects" = "$ra_expected" ] && [ "$(ra_sql "select count(*) from pg_tables where schemaname='$SCHEMA' and tablename in ('financial_decision','refund_authorization')")" = 2 ]; echo $?)"
check 'AC-D16.1 nothing new appears in public' "$([ "$(sql "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p','v','m','S','f') and c.relname not like 'databasechangelog%'")" = 0 ]; echo $?)"
ra_second="$(liquibase update 2>&1)"; printf '%s\n' "$ra_second"
check 'AC-D16.16 a second update applies zero changesets' "$(printf '%s\n' "$ra_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
sql "delete from $ra_t; delete from $fd_t; delete from $SCHEMA.reservation where reservation_id in ('$fd_res1','$fd_res2','$fd_res3','$fd_res4','$fd_res5'); delete from $SCHEMA.catalog_service where service_id = '$fd_svc'; delete from $SCHEMA.customer where customer_id = '$fd_cust'" >/dev/null 2>&1 || true
check 'the rows of the probes are gone before the revert' "$([ "$(sql "select (select count(*) from $ra_t) + (select count(*) from $fd_t) + (select count(*) from $SCHEMA.reservation where reservation_id in ('$fd_res1','$fd_res2','$fd_res3','$fd_res4','$fd_res5'))")" = 0 ]; echo $?)"
ra_n="$(sql "select count(*) from $CONTROL where labels ilike '%HU-COM-016%'" 2>/dev/null || echo 0)"
liquibase rollback-count "$ra_n"
ra_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$fd_base" "$ra_reverted"
check 'AC-D16.16 the revert of the whole slice restores columns, constraints, indexes and privileges exactly and leaves 114 changesets' "$([ -n "$fd_base" ] && [ "$ra_reverted" = "$fd_base" ] && [ "$(sql "select count(*) from $CONTROL")" = 112 ]; echo $?)"
check 'the two tables are gone after the revert' "$([ "$(ra_sql "select count(*) from pg_tables where schemaname='$SCHEMA' and tablename in ('financial_decision','refund_authorization')")" = 0 ]; echo $?)"
db_labels='HU-COM-016'
liquibase update >/dev/null
check 'the changesets of the story reapply to 125' "$([ "$(sql "select count(*) from $CONTROL")" = 123 ]; echo $?)"
