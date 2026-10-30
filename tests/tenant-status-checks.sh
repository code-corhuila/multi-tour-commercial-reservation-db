#!/usr/bin/env bash
# Sourced by db-ci.sh after the offer checks, on the same disposable PostgreSQL instance.
# HU-WRK-007 -db (issue multi-tour-docs#173), spec 021: the tenant_status table (03_tables/024), the function that
# guards the identifier (07_functions/003) and its trigger (09_triggers/003), all with label HU-WRK-007.
# Probes are written first: red before the changesets, green after (Annex J.1).
ts_t="$SCHEMA.tenant_status"
ts_pe="$SCHEMA.processed_event"
ts_sql() { sql "$1" 2>/dev/null || true; }
ts_refusal() { # SQL, text of the engine answer, description
  local answer
  answer="$(engine "$1" 2>&1 || true)"; printf '%s\n' "$answer"
  check "HU-WRK-007 tenant status: $3 is refused by $2" "$(printf '%s\n' "$answer" | grep -q "$2"; echo $?)"
}
ts_accepted() { # SQL, description
  local status=0
  engine "begin; $1; rollback;" || status=$?
  check "HU-WRK-007 tenant status: $2 is accepted" "$status"
}
ts_row() { # tenant id, identifier, status, time zone, country
  echo "insert into $ts_t (tenant_id, identifier, status, time_zone, country, last_event_occurred_at, created_at, updated_at) values (${1:-gen_random_uuid()}, '${2:-coffee-route}', '${3:-ACTIVE}', '${4:-America/Bogota}', '${5:-CO}', now(), now(), now())"
}
ts_repeat() { # character, count
  printf "%$2s" '' | tr ' ' "$1"
}

echo 'HU-WRK-007 tenant status - base: the 50 changesets before the table, the function and the trigger'
db_labels='!HU-WRK-007 and !HU-COM-007 and !HU-COM-008'
liquibase rollback-count 999 >/dev/null
liquibase update >/dev/null
ts_base="$(snapshot)"
check 'base holds exactly 50 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 50 ]; echo $?)"
check 'T-01 precondition: processed_event of HU-COM-006 exists and this piece does not create it' "$([ "$(sql "select to_regclass('$ts_pe') is not null")" = t ]; echo $?)"
check 'on that base tenant_status and its guard do not exist' "$([ "$(sql "select to_regclass('$ts_t') is null")" = t ] && [ "$(ts_sql "select count(*) from pg_proc where proname='fn_tenant_status_guard'")" = 0 ]; echo $?)"

echo 'HU-WRK-007 tenant status - probes written first: red before the changesets, green after'
db_labels='HU-WRK-007'
liquibase update >/dev/null
check 'the table, the function and the trigger bring the control table to 53 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 53 ]; echo $?)"

echo 'the table (AC-D21.1)'
ts_cols='tenant_id uuid NO,identifier text NO,status text NO,time_zone text NO,country text NO,last_event_occurred_at timestamp with time zone NO,created_at timestamp with time zone NO,updated_at timestamp with time zone NO'
check 'AC-D21.1 tenant_status holds its eight columns, all required' "$([ "$(cols_of tenant_status)" = "$ts_cols" ]; echo $?)"
check 'AC-D21.1 nothing new appears in public and no column has a DEFAULT' "$([ "$(sql "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p','v','m','S','f') and c.relname not like 'databasechangelog%'")" = 0 ] && [ "$(ts_sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='tenant_status' and column_default is not null")" = 0 ]; echo $?)"
check 'AC-D21.1 the primary key is tenant_id and there is no foreign key' "$([ "$(ts_sql "select pg_get_constraintdef(oid) from pg_constraint where conname='pk_tenant_status' and conrelid='$ts_t'::regclass")" = 'PRIMARY KEY (tenant_id)' ] && [ "$(ts_sql "select count(*) from pg_constraint where conrelid='$ts_t'::regclass and contype='f'")" = 0 ]; echo $?)"
ts_names='chk_tenant_status_country_format,chk_tenant_status_country_required,chk_tenant_status_created_at_required,chk_tenant_status_identifier_format,chk_tenant_status_identifier_required,chk_tenant_status_last_event_occurred_at_required,chk_tenant_status_status,chk_tenant_status_status_required,chk_tenant_status_tenant_id_required,chk_tenant_status_time_zone_length,chk_tenant_status_time_zone_required,chk_tenant_status_updated_at_required,pk_tenant_status,uq_tenant_status_identifier'
check 'AC-D21.1 the named constraints are exactly the planned ones' "$([ "$(ts_sql "select string_agg(conname, ',' order by conname collate \"C\") from pg_constraint where conrelid='$ts_t'::regclass and contype <> 'n'")" = "$ts_names" ]; echo $?)"
ts_accepted "$(ts_row)" 'a valid ACTIVE tenant'
ts_accepted "$(ts_row '' 'abc' INACTIVE 'UTC' US)" 'an INACTIVE tenant with a three-character identifier'
ts_accepted "$(ts_row '' 'a-1-b2-c3' ACTIVE 'America/Argentina/Buenos_Aires' AR)" 'a kebab-case identifier with digits'
ts_accepted "$(ts_row '' "$(ts_repeat a 40)")" 'an identifier of 40 characters'

echo 'the refusals (AC-D21.2 to AC-D21.4)'
ts_id1="$(aid 3001)"; ts_id2="$(aid 3002)"
engine "$(ts_row "'$ts_id1'" 'tenant-one')" >/dev/null || true
ts_refusal "$(ts_row "'$ts_id2'" 'tenant-one');" uq_tenant_status_identifier 'AC-D21.2 a second tenant with the same identifier'
ts_refusal "$(ts_row "'$ts_id1'" 'tenant-other');" pk_tenant_status 'the same tenant id twice'
ts_refusal "$(ts_row '' 'Tenant-Two');" chk_tenant_status_identifier_format 'AC-D21.3 an identifier with capitals'
ts_refusal "$(ts_row '' 'tenant_two');" chk_tenant_status_identifier_format 'an identifier with an underscore'
ts_refusal "$(ts_row '' '-tenant');" chk_tenant_status_identifier_format 'an identifier that starts with a hyphen'
ts_refusal "$(ts_row '' 'tenant-');" chk_tenant_status_identifier_format 'an identifier that ends with a hyphen'
ts_refusal "$(ts_row '' 'ten--ant');" chk_tenant_status_identifier_format 'an identifier with a double hyphen'
ts_refusal "$(ts_row '' 'ab');" chk_tenant_status_identifier_format 'an identifier of 2 characters'
ts_refusal "$(ts_row '' "$(ts_repeat a 41)");" chk_tenant_status_identifier_format 'an identifier of 41 characters'
ts_refusal "$(ts_row '' 'tenant-three' PENDING);" chk_tenant_status_status 'AC-D21.4 the status PENDING'
ts_refusal "$(ts_row '' 'tenant-three' FAILED);" chk_tenant_status_status 'the status FAILED'
ts_refusal "$(ts_row '' 'tenant-three' active);" chk_tenant_status_status 'a lower-case status'
ts_refusal "$(ts_row '' 'tenant-three' ACTIVE 'UTC' co);" chk_tenant_status_country_format 'a lower-case country'
ts_refusal "$(ts_row '' 'tenant-three' ACTIVE 'UTC' COL);" chk_tenant_status_country_format 'a three-letter country'
ts_refusal "$(ts_row '' 'tenant-three' ACTIVE "$(ts_repeat z 65)" CO);" chk_tenant_status_time_zone_length 'a time zone of 65 characters'
ts_refusal "$(ts_row '' 'tenant-three' ACTIVE ' ' CO | sed "s/' ', 'CO'/'', 'CO'/");" chk_tenant_status_time_zone_length 'an empty time zone'
ts_refusal "insert into $ts_t (tenant_id, identifier, status, time_zone, country, created_at, updated_at) values (gen_random_uuid(), 'tenant-four', 'ACTIVE', 'UTC', 'CO', now(), now());" 'ERROR:  23502.*column "last_event_occurred_at"' 'a tenant without the instant of the last event'

echo 'the identifier guard (AC-D21.5)'
check 'AC-D21.5 the trigger is BEFORE UPDATE on tenant_status and the function lives in the domain schema' "$([ "$(ts_sql "select count(*) from pg_trigger t join pg_proc p on p.oid=t.tgfoid where t.tgname='trg_tenant_status_identifier_guard' and t.tgrelid='$ts_t'::regclass and not t.tgisinternal and p.proname='fn_tenant_status_guard' and p.pronamespace='$SCHEMA'::regnamespace and (t.tgtype & 2) = 2 and (t.tgtype & 16) = 16")" = 1 ]; echo $?)"
ts_refusal "update $ts_t set identifier = 'tenant-renamed' where tenant_id = '$ts_id1';" 'tenant_status identifier cannot change' 'AC-D21.5 an update that changes the identifier'
check 'AC-D21.5 the identifier is still the original after the refusal' "$([ "$(sql "select identifier from $ts_t where tenant_id='$ts_id1'")" = tenant-one ]; echo $?)"
engine "update $ts_t set identifier = identifier, status = 'INACTIVE', last_event_occurred_at = now(), updated_at = now() where tenant_id = '$ts_id1';" >/dev/null || true
check 'AC-D21.5 an update that leaves the identifier equal and changes the status and the instant is allowed' "$([ "$(sql "select status from $ts_t where tenant_id='$ts_id1'")" = INACTIVE ]; echo $?)"

echo 'privileges and the lookup (AC-D21.6, AC-D21.7)'
check 'AC-D21.6 the application user selects, inserts and updates; neither it nor the writer deletes' "$([ "$(privileges_of "$ts_t")" = 'INSERT,SELECT,UPDATE' ] && [ "$(sql "select has_table_privilege('$writer','$ts_t','DELETE')")" = f ]; echo $?)"
check 'AC-D21.6 the reader reads and does not write' "$([ "$(sql "select has_table_privilege('$reader','$ts_t','SELECT') and not has_table_privilege('$reader','$ts_t','INSERT')")" = t ]; echo $?)"
ts_refusal "delete from $ts_t;" 'permission denied for table tenant_status' 'AC-D21.6 DELETE as the application user'
sql "insert into $ts_t (tenant_id, identifier, status, time_zone, country, last_event_occurred_at, created_at, updated_at)
     select gen_random_uuid(), 'bulk-' || n, 'ACTIVE', 'UTC', 'CO', now(), now(), now() from generate_series(1, 5000) n; analyze $ts_t" >/dev/null 2>&1 || true
ts_plan="$(printf '%s\n' "explain select tenant_id, status from $ts_t where identifier = 'bulk-2500';" | docker exec -i -e PGPASSWORD "$container" psql -X -U postgres -d postgres 2>&1 || true)"; printf '%s\n' "$ts_plan"
check 'AC-D21.7 the lookup by identifier uses uq_tenant_status_identifier, not a scan' "$(printf '%s\n' "$ts_plan" | grep -q 'uq_tenant_status_identifier'; echo $?)"
check 'AC-D21.7 no index besides the primary key and the unique one' "$([ "$(ts_sql "select count(*) from pg_indexes where schemaname='$SCHEMA' and tablename='tenant_status'")" = 2 ]; echo $?)"

echo 'Idempotence, exact revert and reapply (AC-D21.8)'
ts_second="$(liquibase update 2>&1)"; printf '%s\n' "$ts_second"
check 'AC-D21.8 a second update applies zero changesets' "$(printf '%s\n' "$ts_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
sql "delete from $ts_t" >/dev/null 2>&1 || true
liquibase rollback-count 3
ts_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$ts_base" "$ts_reverted"
check 'AC-D21.8 the three-change revert restores the schema exactly and leaves 50 changesets' "$([ -n "$ts_base" ] && [ "$ts_reverted" = "$ts_base" ] && [ "$(sql "select count(*) from $CONTROL")" = 50 ]; echo $?)"
check 'AC-D21.8 the table, the function and the trigger are gone and processed_event stays' "$([ "$(sql "select to_regclass('$ts_t') is null")" = t ] && [ "$(ts_sql "select count(*) from pg_proc where proname='fn_tenant_status_guard'")" = 0 ] && [ "$(sql "select to_regclass('$ts_pe') is not null")" = t ]; echo $?)"
db_labels='!HU-COM-007 and !HU-COM-008'
liquibase update >/dev/null
check 'AC-D21.8 the three changesets reapply to 53 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 53 ]; echo $?)"
liquibase rollback-count 999 >/dev/null
liquibase update >/dev/null
liquibase validate >/dev/null
check 'a full build from empty without the labels of the later HU-COM-007 applies exactly 53 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 53 ]; echo $?)"
