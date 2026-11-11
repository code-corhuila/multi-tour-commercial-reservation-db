#!/usr/bin/env bash
# Sourced by db-ci.sh after rescheduling-record-checks.sh, on the same disposable PostgreSQL instance, with the 170 changesets that exist before the story.
# HU-COM-020 -db (issue code-corhuila/multi-tour-docs#186), plan D-02 to D-05: the append-only tenant_suspension history (one open period per tenant, closed once, never deleted), the cause
# of a frozen payment deadline and their indexes. Every changeset of the story is labelled HU-COM-020. Probes are written first: red before the changesets, green after (Annex J.1).
ts2_t="$SCHEMA.tenant_suspension"; ts2_pd="$SCHEMA.payment_deadline"; ts2_st="$SCHEMA.tenant_status"
ts2_tenant_b="00000000-0000-0000-0000-000000000002"; ts2_tenant_c="00000000-0000-0000-0000-000000000003"
ts2_cust="$(aid 8201)"; ts2_svc="$(aid 8203)"; ts2_res="$(aid 8210)"; ts2_res_b="$(aid 8211)"
ts2_s1="$(aid 8220)"; ts2_s2="$(aid 8221)"; ts2_s3="$(aid 8222)"; ts2_d1="$(aid 8230)"; ts2_d2="$(aid 8231)"; ts2_d3="$(aid 8232)"
ts2_sql() { sql "$1" 2>/dev/null || true; }
ts2_refusal() { # SQL, text of the engine answer, description
  local answer
  answer="$(engine "$1" 2>&1 || true)"; printf '%s\n' "$answer"
  check "HU-COM-020 db: $3 is refused by $2" "$(printf '%s\n' "$answer" | grep -q "$2"; echo $?)"
}
ts2_accepted() { # SQL, description
  local status=0
  engine "$1" >/dev/null || status=$?
  check "HU-COM-020 db: $2 is accepted" "$status"
}
ts2_explain() { printf '%s\n' 'set enable_seqscan = off;' "explain $1;" | docker exec -i -e PGPASSWORD "$container" psql -X -U postgres -d postgres 2>&1 || true; }
ts2_open() { # column/value pairs (SQL literals) that replace the defaults of a valid open suspension of the first tenant
  local -A v=([tenant_suspension_id]="gen_random_uuid()" [tenant_id]="'$tenant'" [suspended_at]="now() - interval '2 hours'" [resumed_at]="NULL"
    [suspended_by_event_id]="gen_random_uuid()" [resumed_by_event_id]="NULL")
  while [ $# -ge 2 ]; do v[$1]="$2"; shift 2; done
  echo "insert into $ts2_t (tenant_suspension_id, tenant_id, suspended_at, resumed_at, suspended_by_event_id, resumed_by_event_id) values (${v[tenant_suspension_id]}, ${v[tenant_id]}, ${v[suspended_at]}, ${v[resumed_at]}, ${v[suspended_by_event_id]}, ${v[resumed_by_event_id]})"
}
ts2_def() { sql "select string_agg(x, E'
' order by x) from (
    select 'c:' || column_name || ' ' || data_type || ' ' || is_nullable as x from information_schema.columns where table_schema = '$SCHEMA' and table_name = 'tenant_status'
    union all select 'k:' || conname || ' ' || pg_get_constraintdef(oid) from pg_constraint where conrelid = '$ts2_st'::regclass
    union all select 'i:' || indexdef from pg_indexes where schemaname = '$SCHEMA' and tablename = 'tenant_status') s" 2>/dev/null || true; }

echo 'HU-COM-020 db - base: the 170 changesets that exist before the story, with the probe rows'
liquibase rollback-count 999 >/dev/null
db_labels='!HU-COM-020 and !decision-resume and !departure-order'
liquibase update >/dev/null
ts2_base="$(snapshot)"; ts2_base_def="$(ts2_def)"
ts2_base_objects="$(sql "select (select count(*) from pg_tables where schemaname='$SCHEMA') || '|' || (select count(*) from pg_proc where pronamespace='$SCHEMA'::regnamespace) || '|' || (select count(*) from pg_trigger where not tgisinternal and tgrelid in (select oid from pg_class where relnamespace='$SCHEMA'::regnamespace))" 2>/dev/null || true)"
check 'base holds exactly 170 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 170 ]; echo $?)"
sql "insert into $SCHEMA.customer (customer_id, tenant_id, full_name, created_at, document_number, birth_date_or_age, contact_info, status, terms_accepted, terms_accepted_at) values ('$ts2_cust', '$tenant', 'Suspension probe', now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE', true, now());
     insert into $SCHEMA.catalog_service (service_id, tenant_id, service_type, commercial_name, catalog_status, base_rate_cents, base_operational_cost_cents, configured_capacity, transport_required, high_risk, created_at, updated_at) values ('$ts2_svc', '$tenant', 'TOUR', 'Suspension probe tour', 'ACTIVE', 150000, 90000, 12, false, false, now(), now());
     insert into $ts2_st (tenant_id, identifier, status, time_zone, country, last_event_occurred_at, created_at, updated_at) values ('$tenant', 'ts2-a', 'ACTIVE', 'America/Bogota', 'CO', now(), now(), now()), ('$ts2_tenant_b', 'ts2-b', 'ACTIVE', 'America/Bogota', 'CO', now(), now(), now())" >/dev/null 2>&1 || true
engine "$(rs_row reservation_id "'$ts2_res'" customer_id "'$ts2_cust'" service_id "'$ts2_svc'");" >/dev/null || true
sql "insert into $ts2_pd (payment_deadline_id, tenant_id, reservation_id, deadline_kind, due_at) values ('$ts2_d1', '$tenant', '$ts2_res', 'INITIAL_PAYMENT', now() + interval '1 day'), ('$ts2_d2', '$tenant', '$ts2_res', 'BALANCE', now() + interval '5 days'), ('$ts2_d3', '$tenant', '$ts2_res', 'PENDING_DIFFERENCE', now() + interval '6 days')" >/dev/null 2>&1 || true
check 'the probe tenants, the reservation and the three deadlines exist on the base' "$([ "$(ts2_sql "select (select count(*) from $ts2_st where tenant_id in ('$tenant','$ts2_tenant_b')) || '|' || (select count(*) from $ts2_pd where reservation_id = '$ts2_res')")" = '2|3' ]; echo $?)"

echo 'HU-COM-020 db - probes written first: red before the changesets, green after'
db_labels='HU-COM-020'
liquibase update >/dev/null
check 'the changesets of the story bring the control table to 177' "$([ "$(sql "select count(*) from $CONTROL")" = 177 ]; echo $?)"

echo 'suspensionRequiresTenantStartAndOpeningEvent, onlyOneOpenSuspensionPerTenant (AC-D20.2, AC-D20.3)'
ts2_accepted "$(ts2_open tenant_suspension_id "'$ts2_s1'")" 'a whole open suspension'
for column in tenant_suspension_id tenant_id suspended_at suspended_by_event_id; do
  ts2_refusal "$(ts2_open tenant_id "'$ts2_tenant_b'" "$column" NULL);" "null value in column \"$column\".*not-null constraint" "a suspension without $column"
done
ts2_refusal "$(ts2_open tenant_id "'$ts2_tenant_c'");" fk_tenant_suspension_tenant_status 'a suspension of a tenant that has no copy in tenant_status'
ts2_refusal "$(ts2_open);" uq_tenant_suspension_open_tenant 'a second open suspension for the same tenant'
ts2_refusal "$(ts2_open tenant_id "'$ts2_tenant_b'" resumed_at now\(\));" chk_tenant_suspension_close_complete 'a closed suspension without its closing event'
ts2_refusal "$(ts2_open tenant_id "'$ts2_tenant_b'" resumed_at "now() - interval '3 hours'" resumed_by_event_id "gen_random_uuid()");" chk_tenant_suspension_period 'a suspension that ends before it starts'
check 'no column of the suspension table has a DEFAULT' "$([ "$(ts2_sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='tenant_suspension' and column_default is not null")" = 0 ]; echo $?)"

echo 'aSuspensionIsClosedOnceAndNeverRewritten, aSuspensionCannotEndBeforeItStarted, aSuspensionCannotBeDeleted (AC-D20.4, AC-D20.5)'
ts2_refusal "update $ts2_t set suspended_at = now() where tenant_suspension_id = '$ts2_s1';" trg_tenant_suspension_guard 'a change of the start of an open suspension'
ts2_refusal "update $ts2_t set resumed_at = now() where tenant_suspension_id = '$ts2_s1';" trg_tenant_suspension_guard 'a closing instant without its event'
ts2_refusal "update $ts2_t set resumed_at = now() - interval '5 hours', resumed_by_event_id = gen_random_uuid() where tenant_suspension_id = '$ts2_s1';" chk_tenant_suspension_period 'a closing before the start'
ts2_accepted "update $ts2_t set resumed_at = now(), resumed_by_event_id = gen_random_uuid() where tenant_suspension_id = '$ts2_s1'" 'the closing of an open suspension'
ts2_refusal "update $ts2_t set resumed_at = now() + interval '1 hour' where tenant_suspension_id = '$ts2_s1';" trg_tenant_suspension_guard 'a second closing of the same suspension'
ts2_refusal "update $ts2_t set resumed_by_event_id = gen_random_uuid() where tenant_suspension_id = '$ts2_s1';" trg_tenant_suspension_guard 'any change of a closed suspension'
ts2_refusal "delete from $ts2_t where tenant_suspension_id = '$ts2_s1';" 'permission denied for table tenant_suspension' 'a delete of a suspension'
ts2_accepted "$(ts2_open tenant_suspension_id "'$ts2_s2'" suspended_at "now() + interval '1 hour'")" 'a new open suspension after the first one was closed'

echo 'theSameEventIdCannotOpenOrCloseTwice (AC-D20.6)'
ts2_ev="$(aid 8240)"; ts2_ev2="$(aid 8241)"
ts2_accepted "$(ts2_open tenant_suspension_id "'$ts2_s3'" tenant_id "'$ts2_tenant_b'" suspended_by_event_id "'$ts2_ev'" resumed_at now\(\) resumed_by_event_id "'$ts2_ev2'")" 'a closed suspension of the second tenant with its two events'
ts2_refusal "$(ts2_open tenant_id "'$ts2_tenant_b'" suspended_by_event_id "'$ts2_ev'");" uq_tenant_suspension_opening_event 'an opening event id used twice'
ts2_refusal "$(ts2_open tenant_id "'$ts2_tenant_b'" resumed_at now\(\) resumed_by_event_id "'$ts2_ev2'");" uq_tenant_suspension_closing_event 'a closing event id used twice'

echo 'freezeCauseIsPresentIffFrozenAndKnown, existingDeadlinesStayValidWithoutACause (AC-D20.7, AC-D20.8)'
check 'the three deadlines that existed before the slice are untouched and have no cause' "$([ "$(ts2_sql "select count(*) from $ts2_pd where reservation_id = '$ts2_res' and freeze_cause is null and frozen_at is null")" = 3 ]; echo $?)"
ts2_refusal "update $ts2_pd set frozen_at = now(), remaining_at_freeze_minutes = 100 where payment_deadline_id = '$ts2_d1';" chk_payment_deadline_freeze_cause_complete 'a freeze written without its cause'
ts2_refusal "update $ts2_pd set freeze_cause = 'TENANT_INACTIVE' where payment_deadline_id = '$ts2_d1';" chk_payment_deadline_freeze_cause_complete 'a cause written without the freeze'
ts2_refusal "update $ts2_pd set frozen_at = now(), remaining_at_freeze_minutes = 100, freeze_cause = 'HOLIDAY' where payment_deadline_id = '$ts2_d1';" chk_payment_deadline_freeze_cause 'a cause outside the two codes'
ts2_accepted "update $ts2_pd set frozen_at = now(), remaining_at_freeze_minutes = 100, freeze_cause = 'TENANT_INACTIVE' where payment_deadline_id = '$ts2_d1'" 'a freeze by the inactivation of the tenant'
ts2_accepted "update $ts2_pd set frozen_at = now(), remaining_at_freeze_minutes = 50, freeze_cause = 'DEPARTURE_CANCELLED_OR_INTERRUPTED' where payment_deadline_id = '$ts2_d2'" 'a freeze by the cancelled departure'
ts2_accepted "update $ts2_pd set frozen_at = NULL, remaining_at_freeze_minutes = NULL, freeze_cause = NULL where payment_deadline_id = '$ts2_d1'" 'the resume of a frozen deadline'

echo 'suspensionsAndFrozenDeadlinesNeverCrossTenants, openLookupWindowAndResumeScanUseTheirIndexes (AC-D20.9, AC-D20.10)'
check 'a read scoped to the second tenant returns none of the suspensions of the first' "$([ "$(ts2_sql "select count(*) from $ts2_t where tenant_id = '$ts2_tenant_b' and tenant_suspension_id = '$ts2_s2'")" = 0 ]; echo $?)"
ts2_p1="$(ts2_explain "select 1 from $ts2_t where tenant_id = '$tenant' and resumed_at is null")"; printf '%s\n' "$ts2_p1"
check 'the lookup of the open suspension uses uq_tenant_suspension_open_tenant' "$(printf '%s\n' "$ts2_p1" | grep -q 'uq_tenant_suspension_open_tenant'; echo $?)"
ts2_p2="$(ts2_explain "select 1 from $ts2_t where tenant_id = '$tenant' and suspended_at < now() order by suspended_at desc")"; printf '%s\n' "$ts2_p2"
check 'the window read uses idx_tenant_suspension_tenant_suspended_at' "$(printf '%s\n' "$ts2_p2" | grep -q 'idx_tenant_suspension_tenant_suspended_at'; echo $?)"
ts2_p3="$(ts2_explain "select 1 from $ts2_pd where tenant_id = '$tenant' and freeze_cause = 'TENANT_INACTIVE'")"; printf '%s\n' "$ts2_p3"
check 'the resume scan uses idx_payment_deadline_tenant_frozen_by_tenant' "$(printf '%s\n' "$ts2_p3" | grep -q 'idx_payment_deadline_tenant_frozen_by_tenant'; echo $?)"

echo 'onlyThePlannedObjectsAreAdded, theTenantStatusCopyIsNotAltered, secondRunAppliesZeroAndRevertLeavesNoTrace (AC-D20.1, AC-D20.11, AC-D20.12)'
ts2_objects="$(sql "select (select count(*) from pg_tables where schemaname='$SCHEMA') || '|' || (select count(*) from pg_proc where pronamespace='$SCHEMA'::regnamespace) || '|' || (select count(*) from pg_trigger where not tgisinternal and tgrelid in (select oid from pg_class where relnamespace='$SCHEMA'::regnamespace))" 2>/dev/null || true)"
IFS='|' read -r ts2_bt ts2_bf ts2_bg <<< "$ts2_base_objects"
check 'AC-D20.1 exactly one table, one function and one trigger were added to the base' "$([ -n "$ts2_base_objects" ] && [ "$ts2_objects" = "$((ts2_bt + 1))|$((ts2_bf + 1))|$((ts2_bg + 1))" ]; echo $?)"
check 'AC-D20.1 nothing new appears in public' "$([ "$(sql "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p','v','m','S','f') and c.relname not like 'databasechangelog%'")" = 0 ]; echo $?)"
check 'AC-D20.11 the definition of tenant_status is unchanged' "$([ -n "$ts2_base_def" ] && [ "$(ts2_def)" = "$ts2_base_def" ]; echo $?)"
ts2_second="$(liquibase update 2>&1)"; printf '%s\n' "$ts2_second"
check 'AC-D20.12 a second update applies zero changesets' "$(printf '%s\n' "$ts2_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
sql "delete from $ts2_t; delete from $ts2_pd where reservation_id = '$ts2_res'; delete from $SCHEMA.reservation where reservation_id = '$ts2_res'; delete from $ts2_st where tenant_id in ('$tenant','$ts2_tenant_b'); delete from $SCHEMA.catalog_service where service_id = '$ts2_svc'; delete from $SCHEMA.customer where customer_id = '$ts2_cust'" >/dev/null 2>&1 || true
check 'the rows of the probes are gone before the revert' "$([ "$(sql "select (select count(*) from $ts2_t) + (select count(*) from $ts2_pd where reservation_id = '$ts2_res') + (select count(*) from $ts2_st where tenant_id in ('$tenant','$ts2_tenant_b'))")" = 0 ]; echo $?)"
ts2_n="$(sql "select count(*) from $CONTROL where labels ilike '%HU-COM-020%'" 2>/dev/null || echo 0)"
liquibase rollback-count "$ts2_n"
ts2_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$ts2_base" "$ts2_reverted"
check 'AC-D20.12 the revert restores columns, constraints, indexes and privileges exactly and leaves 170 changesets' "$([ -n "$ts2_base" ] && [ "$ts2_reverted" = "$ts2_base" ] && [ "$(sql "select count(*) from $CONTROL")" = 170 ]; echo $?)"
db_labels='HU-COM-020'
liquibase update >/dev/null
check 'the changesets of the story reapply to 177' "$([ "$(sql "select count(*) from $CONTROL")" = 177 ]; echo $?)"
