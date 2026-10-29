#!/usr/bin/env bash
# Sourced by db-ci.sh after the authorizable-reason checks, on the same disposable PostgreSQL instance.
# HU-COM-006 -db (issue multi-tour-docs#172), plan D-03 to D-09: the departure columns of salida_capacity
# (04_alter/011, label salida-state), their index (10_indexes/012, label salida-state), the processed_event
# table (03_tables/015), its purge index (10_indexes/013) and the DELETE grant on it (03_dcl/01_grants/007),
# the last three with label processed-event. Every changeset also carries HU-COM-006.
# Probes are written first: red before the changesets, green after (Annex J.1).
of_t="$SCHEMA.salida_capacity"
of_pe="$SCHEMA.processed_event"
of_ce="$SCHEMA.catalog_service"
of_ae="$SCHEMA.associated_establishment"
of_tenant_b="00000000-0000-0000-0000-000000000002"
of_svc_a="$(aid 2001)"; of_svc_b="$(aid 2002)"; of_svc_pre="$(aid 2003)"
of_sql() { sql "$1" 2>/dev/null || true; }
of_refusal() { # SQL, text of the engine answer, description
  local answer
  answer="$(engine "$1" 2>&1 || true)"; printf '%s\n' "$answer"
  check "HU-COM-006 offer: $3 is refused by $2" "$(printf '%s\n' "$answer" | grep -q "$2"; echo $?)"
}
of_accepted() { # SQL, description
  local status=0
  engine "begin; $1; rollback;" || status=$?
  check "HU-COM-006 offer: $2 is accepted" "$status"
}
of_dep() { # departure id, tenant, service, start (SQL literal), status (SQL literal)
  echo "insert into $of_t (salida_capacity_id, tenant_id, salida_id, service_id, effective_capacity, held_seats, hora_inicio, status) values (gen_random_uuid(), ${2:-'$tenant'}, ${1:-gen_random_uuid()}, ${3:-'$of_svc_a'}, 20, 0, ${4:-now() + interval '1 day'}, ${5:-'SCHEDULED'})"
}
of_explain() { # a query; the plan is printed with sequential scans disabled (declared: the planner is judged on the index it can use)
  printf '%s\n' 'set enable_seqscan = off;' "explain $1;" | docker exec -i -e PGPASSWORD "$container" psql -X -U postgres -d postgres 2>&1 || true
}
of_app() { # a query run as the application user; the last line of the answer
  docker exec -e PGPASSWORD "$container" psql -X -U postgres -d postgres -tA -c "set role $app" -c "$1" 2>&1 | tail -1 || true
}
of_seed_offer() { # tours, establishments of two tenants with the same names (AC-D6.8)
  sql "insert into $of_ce (service_id, tenant_id, service_type, commercial_name, catalog_status, base_rate_cents, base_operational_cost_cents, configured_capacity, transport_required, high_risk, created_at, updated_at)
       select case when n = 0 then (case when t = '$tenant' then '$of_svc_a'::uuid else '$of_svc_b'::uuid end) else gen_random_uuid() end,
              t::uuid, 'TOUR', 'OFFER-Coffee route ' || n, 'ACTIVE', 150000, 90000, 12, false, false, now() - n * interval '1 minute', now()
       from unnest(array['$tenant', '$of_tenant_b']) t, generate_series(0, 59) n;
       insert into $of_ae (association_id, tenant_id, establishment_type, commercial_name, commercial_information, association_status, created_at, updated_at)
       select gen_random_uuid(), t::uuid, case when n % 2 = 0 then 'HOTEL' else 'RESTAURANT' end, 'OFFER-Hotel ' || n, 'open all year', 'ACTIVE', now() - n * interval '1 minute', now()
       from unnest(array['$tenant', '$of_tenant_b']) t, generate_series(0, 59) n" >/dev/null 2>&1 || true
}
of_seed_departures() { # 2000 departures per tenant on its own tour (enough for the planner to prefer the ordered index), every fifth cancelled
  sql "insert into $of_t (salida_capacity_id, tenant_id, salida_id, service_id, effective_capacity, held_seats, hora_inicio, status)
       select gen_random_uuid(), t, gen_random_uuid(), s, 20, 0, now() + n * interval '1 day', case when n % 5 = 0 then 'CANCELLED' else 'SCHEDULED' end
       from (values ('$tenant'::uuid, '$of_svc_a'::uuid), ('$of_tenant_b'::uuid, '$of_svc_b'::uuid)) v(t, s), generate_series(1, 2000) n;
       analyze $of_t; analyze $of_ce; analyze $of_ae" >/dev/null 2>&1 || true
}

echo 'HU-COM-006 offer - base: the 44 changesets before the departure columns, the processed-event table, their indexes and the grant'
liquibase rollback-count 999 >/dev/null
db_labels='!HU-COM-006 and !customer-terms and !HU-WRK-007'
liquibase update >/dev/null
of_base="$(snapshot)"
of_base_indexes="$(of_sql "select count(*) from pg_indexes where schemaname='$SCHEMA' and tablename in ('catalog_service','associated_establishment')")"
check 'base holds exactly 44 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 44 ]; echo $?)"
check 'T-01 precondition: the schema, the control table, both roles and the three offer tables exist' "$([ "$(sql "select count(*) from pg_namespace where nspname='$SCHEMA'")" = 1 ] && [ "$(sql "select count(*) from $CONTROL")" -gt 0 ] && [ "$(sql "select count(*) from pg_roles where rolname in ('$reader','$writer')")" = 2 ] && [ "$(sql "select count(*) from pg_tables where schemaname='$SCHEMA' and tablename in ('salida_capacity','catalog_service','associated_establishment')")" = 3 ]; echo $?)"
check 'T-01 precondition: fk_salida_capacity_service and the two list indexes exist' "$([ "$(sql "select count(*) from pg_constraint where conname='fk_salida_capacity_service'")" = 1 ] && [ "$(sql "select count(*) from pg_indexes where schemaname='$SCHEMA' and indexname in ('idx_catalog_service_tenant_status_created','idx_associated_establishment_tenant_status_created')")" = 2 ]; echo $?)"
check 'on that base salida_capacity has no start time and no status, and processed_event does not exist' "$([ "$(sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='salida_capacity' and column_name in ('hora_inicio','status')")" = 0 ] && [ "$(sql "select to_regclass('$of_pe') is null")" = t ]; echo $?)"

echo 'HU-COM-006 offer - the empty-table precondition (plan D-03): a populated salida_capacity stops the migration'
of_seed_offer
sql "insert into $of_ce (service_id, tenant_id, service_type, commercial_name, catalog_status, base_rate_cents, base_operational_cost_cents, configured_capacity, transport_required, high_risk, created_at, updated_at) values ('$of_svc_pre', '$tenant', 'TOUR', 'OFFER-precondition', 'ACTIVE', 1, 1, 1, false, false, now(), now()); insert into $of_t (salida_capacity_id, tenant_id, salida_id, service_id, effective_capacity, held_seats) values (gen_random_uuid(), '$tenant', gen_random_uuid(), '$of_svc_pre', 10, 0)" >/dev/null 2>&1 || true
db_labels='salida-state'
of_pre_rc=0; of_pre="$(liquibase update 2>&1)" || of_pre_rc=$?
printf '%s\n' "$of_pre" | tail -8
check 'the departure columns are refused on a table that holds a row, by the precondition' "$([ "$of_pre_rc" != 0 ] && printf '%s\n' "$of_pre" | grep -qi 'precondition'; echo $?)"
check 'the refusal leaves the control table at 44 and no column behind' "$([ "$(sql "select count(*) from $CONTROL")" = 44 ] && [ "$(sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='salida_capacity' and column_name in ('hora_inicio','status')")" = 0 ]; echo $?)"
sql "delete from $of_t" >/dev/null 2>&1 || true

echo 'HU-COM-006 offer - probes written first: red before the changesets, green after'
liquibase update >/dev/null
check 'the columns and their index bring the control table to 46 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 46 ]; echo $?)"

echo 'salida_capacity: the start time and the status (AC-D6.1 to AC-D6.3, AC-D6.10)'
of_cols='salida_capacity_id uuid NO,tenant_id uuid NO,salida_id uuid NO,effective_capacity integer NO,held_seats integer NO,service_id uuid NO,hora_inicio timestamp with time zone NO,status text NO'
check 'AC-D6.2 it holds its six columns plus hora_inicio timestamptz and status text, both required, and no end time, ceiling or marker' "$([ "$(cols_of salida_capacity)" = "$of_cols" ]; echo $?)"
check 'AC-D6.1 nothing new appears in public' "$([ "$(sql "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p','v','m','S','f') and c.relname not like 'databasechangelog%'")" = 0 ]; echo $?)"
check 'the new columns have no DEFAULT: the service states the departure' "$([ "$(of_sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='salida_capacity' and column_name in ('hora_inicio','status') and column_default is not null")" = 0 ] && [ "$(of_sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='salida_capacity' and column_name in ('hora_inicio','status')")" = 2 ]; echo $?)"
check 'chk_salida_capacity_status lists exactly the four codes' "$([ "$(of_sql "select count(*) from pg_constraint where conname='chk_salida_capacity_status' and conrelid='$of_t'::regclass and contype='c' and pg_get_constraintdef(oid) like '%SCHEDULED%' and pg_get_constraintdef(oid) like '%IN_EXECUTION%' and pg_get_constraintdef(oid) like '%FINALIZED%' and pg_get_constraintdef(oid) like '%CANCELLED%'")" = 1 ]; echo $?)"
for of_status in SCHEDULED IN_EXECUTION FINALIZED CANCELLED; do
  of_accepted "$(of_dep '' '' '' '' "'$of_status'")" "a departure with status $of_status"
done
of_refusal "$(of_dep '' '' '' '' "'Archivada'");" chk_salida_capacity_status 'a status outside the four (Archivada)'
of_refusal "$(of_dep '' '' '' '' "'Programada'");" chk_salida_capacity_status 'a Spanish display value (Programada): the column holds English codes'
of_refusal "$(of_dep '' '' '' '' "'scheduled'");" chk_salida_capacity_status 'a lower-case code'
of_refusal "insert into $of_t (salida_capacity_id, tenant_id, salida_id, service_id, effective_capacity, held_seats, status) values (gen_random_uuid(), '$tenant', gen_random_uuid(), '$of_svc_a', 20, 0, 'SCHEDULED');" 'ERROR:  23502.*column "hora_inicio"' 'a departure without start time'
of_refusal "insert into $of_t (salida_capacity_id, tenant_id, salida_id, service_id, effective_capacity, held_seats, hora_inicio) values (gen_random_uuid(), '$tenant', gen_random_uuid(), '$of_svc_a', 20, 0, now());" 'ERROR:  23502.*column "status"' 'a departure without status'
check 'AC-D6.10 the earlier constraints are untouched and only chk_salida_capacity_status is new' "$([ "$(of_sql "select string_agg(conname, ',' order by conname) from pg_constraint where conrelid='$of_t'::regclass and contype in ('p','u','c','f')")" = 'chk_salida_capacity_held_seats,chk_salida_capacity_status,fk_salida_capacity_service,pk_salida_capacity,uq_salida_capacity_tenant_id_salida_id' ]; echo $?)"
check 'AC-D6.10 fk_salida_capacity_service is still simple, on service_id, ON DELETE RESTRICT' "$([ "$(of_sql "select pg_get_constraintdef(oid) from pg_constraint where conname='fk_salida_capacity_service'")" = "FOREIGN KEY (service_id) REFERENCES $SCHEMA.catalog_service(service_id) ON DELETE RESTRICT" ]; echo $?)"

echo 'the index of the open departures and the plans of the other two lists (AC-D6.4 to AC-D6.6)'
check 'idx_salida_capacity_tenant_service_start is an index on (tenant_id, service_id, hora_inicio)' "$([ "$(of_sql "select count(*) from pg_indexes where schemaname='$SCHEMA' and tablename='salida_capacity' and indexname='idx_salida_capacity_tenant_service_start' and indexdef like '%(tenant_id, service_id, hora_inicio)%'")" = 1 ]; echo $?)"
of_seed_departures
of_plan_dep="$(of_explain "select salida_id, hora_inicio from $of_t where tenant_id='$tenant' and service_id='$of_svc_a' and status='SCHEDULED' and hora_inicio >= now() order by hora_inicio limit 20")"; printf '%s\n' "$of_plan_dep"
check 'AC-D6.4 the open departures of a tour of a tenant use idx_salida_capacity_tenant_service_start' "$(printf '%s\n' "$of_plan_dep" | grep -q 'idx_salida_capacity_tenant_service_start'; echo $?)"
of_plan_tours="$(of_explain "select service_id from $of_ce where tenant_id='$tenant' and catalog_status='ACTIVE' and service_type='TOUR' order by created_at desc limit 20")"; printf '%s\n' "$of_plan_tours"
check 'AC-D6.5 the active tours of a tenant use idx_catalog_service_tenant_status_created' "$(printf '%s\n' "$of_plan_tours" | grep -q 'idx_catalog_service_tenant_status_created'; echo $?)"
of_plan_est="$(of_explain "select association_id from $of_ae where tenant_id='$tenant' and association_status='ACTIVE' order by created_at desc limit 20")"; printf '%s\n' "$of_plan_est"
check 'AC-D6.6 the active establishments of a tenant use idx_associated_establishment_tenant_status_created' "$(printf '%s\n' "$of_plan_est" | grep -q 'idx_associated_establishment_tenant_status_created'; echo $?)"
check 'AC-D6.5 and AC-D6.6 no index was added to the tours or the establishments' "$([ "$(of_sql "select count(*) from pg_indexes where schemaname='$SCHEMA' and tablename in ('catalog_service','associated_establishment')")" = "$of_base_indexes" ]; echo $?)"

echo 'isolation: two tenants with the same names (AC-D6.8)'
check 'a tour name shared by two tenants returns one row of the tenant, scoped as the application user' "$([ "$(of_app "select count(*) || '|' || count(distinct tenant_id) || '|' || min(tenant_id::text) from $of_ce where tenant_id='$tenant' and commercial_name='OFFER-Coffee route 7'")" = "1|1|$tenant" ]; echo $?)"
check '...and the other tenant gets its own row for the same name' "$([ "$(of_app "select count(*) || '|' || count(distinct tenant_id) || '|' || min(tenant_id::text) from $of_ce where tenant_id='$of_tenant_b' and commercial_name='OFFER-Coffee route 7'")" = "1|1|$of_tenant_b" ]; echo $?)"
check 'an establishment name shared by two tenants returns one row of the tenant' "$([ "$(of_app "select count(*) || '|' || count(distinct tenant_id) from $of_ae where tenant_id='$tenant' and commercial_name='OFFER-Hotel 3'")" = '1|1' ]; echo $?)"
check 'the departures of the tour of tenant A are 2000 for tenant A and none for tenant B scoped to the same tour' "$([ "$(of_app "select count(*) from $of_t where tenant_id='$tenant' and service_id='$of_svc_a'")" = 2000 ] && [ "$(of_app "select count(*) from $of_t where tenant_id='$of_tenant_b' and service_id='$of_svc_a'")" = 0 ]; echo $?)"
check 'every scheduled departure of the open-departures query belongs to the tenant asked' "$([ "$(of_app "select count(*) from $of_t where tenant_id='$tenant' and status='SCHEDULED' and hora_inicio >= now() and (tenant_id <> '$tenant' or service_id <> '$of_svc_a')")" = 0 ] && [ "$(of_app "select count(*) from $of_t where tenant_id='$tenant' and status='SCHEDULED' and hora_inicio >= now()")" = 1600 ]; echo $?)"

echo 'processed_event and the purge grant (AC-D6.7, AC-D6.9)'
db_labels='processed-event'
liquibase update >/dev/null
check 'the table, its purge index and the grant bring the control table to 49 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 49 ]; echo $?)"
check 'processed_event exists only in the domain schema, with event_id uuid and processed_at timestamptz, both required' "$([ "$(of_sql "select count(*) from pg_tables where tablename='processed_event' and schemaname='$SCHEMA'")" = 1 ] && [ "$(of_sql "select count(*) from pg_tables where tablename='processed_event' and schemaname='public'")" = 0 ] && [ "$(cols_of processed_event)" = 'event_id uuid NO,processed_at timestamp with time zone NO' ]; echo $?)"
check 'pk_processed_event is the primary key and no column has a DEFAULT' "$([ "$(of_sql "select count(*) from pg_constraint where conrelid='$of_pe'::regclass and contype='p' and conname='pk_processed_event'")" = 1 ] && [ "$(of_sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='processed_event' and column_default is not null")" = 0 ]; echo $?)"
check 'idx_processed_event_processed_at serves the 30-day purge' "$([ "$(of_sql "select count(*) from pg_indexes where schemaname='$SCHEMA' and tablename='processed_event' and indexname='idx_processed_event_processed_at' and indexdef like '%(processed_at)%'")" = 1 ]; echo $?)"
of_event="$(aid 2101)"
of_accepted "insert into $of_pe (event_id, processed_at) values ('$of_event', now())" 'a first insert of an event id'
engine "insert into $of_pe (event_id, processed_at) values ('$of_event', now());" >/dev/null || true
of_refusal "insert into $of_pe (event_id, processed_at) values ('$of_event', now());" pk_processed_event 'the same event id twice'
of_refusal "insert into $of_pe (event_id, processed_at) values ('$(aid 2102)', NULL);" 'ERROR:  23502.*column "processed_at"' 'an event without its processing moment'
check 'AC-D6.9 the application user and the writer hold DELETE on processed_event, the reader does not' "$([ "$(sql "select has_table_privilege('$app','$of_pe','DELETE') and has_table_privilege('$writer','$of_pe','DELETE')")" = t ] && [ "$(sql "select has_table_privilege('$reader','$of_pe','DELETE')")" = f ]; echo $?)"
check 'the reader reads processed_event' "$([ "$(sql "select has_table_privilege('$reader','$of_pe','SELECT')")" = t ]; echo $?)"
engine "delete from $of_pe where event_id = '$of_event';" >/dev/null || true
check 'AC-D6.9 the application user deletes from processed_event (the purge)' "$([ "$(sql "select count(*) from $of_pe where event_id='$of_event'")" = 0 ]; echo $?)"
for of_business in salida_capacity catalog_service associated_establishment; do
  of_refusal "delete from $SCHEMA.$of_business;" "permission denied for table $of_business" "DELETE as the application user on $of_business"
  check "AC-D6.9 neither the writer nor the application user holds DELETE on $of_business" "$([ "$(sql "select has_table_privilege('$app','$SCHEMA.$of_business','DELETE') or has_table_privilege('$writer','$SCHEMA.$of_business','DELETE')")" = f ]; echo $?)"
done
check 'AC-D6.9 DELETE is held on the two technical tables and on processed_event, and on no other' "$([ "$(sql "select string_agg(t.table_name, ',' order by t.table_name) from information_schema.tables t where t.table_schema='$SCHEMA' and has_table_privilege('$app', format('%I.%I', t.table_schema, t.table_name), 'DELETE')")" = 'idempotency_key,outbox_event,processed_event' ]; echo $?)"

echo 'Idempotence, exact revert, reapply and a build from empty (AC-D6.11, AC-D6.12)'
of_second="$(liquibase update 2>&1)"; printf '%s\n' "$of_second"
check 'a second update applies zero changesets' "$(printf '%s\n' "$of_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
sql "delete from $of_t; delete from $of_pe; delete from $of_ae where commercial_name like 'OFFER-%'; delete from $of_ce where commercial_name like 'OFFER-%'" >/dev/null 2>&1 || true
liquibase rollback-count 5
of_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$of_base" "$of_reverted"
check 'the five-change revert restores columns, constraints, indexes and privileges exactly' "$([ -n "$of_base" ] && [ "$of_reverted" = "$of_base" ] && [ "$(sql "select count(*) from $CONTROL")" = 44 ]; echo $?)"
check 'the columns, the check, the index, the table and the grant are gone after the revert' "$([ "$(sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='salida_capacity' and column_name in ('hora_inicio','status')")" = 0 ] && [ "$(sql "select to_regclass('$of_pe') is null")" = t ] && [ "$(sql "select count(*) from pg_indexes where schemaname='$SCHEMA' and indexname in ('idx_salida_capacity_tenant_service_start','idx_processed_event_processed_at')")" = 0 ] && [ "$(sql "select count(*) from pg_constraint where conname='chk_salida_capacity_status'")" = 0 ]; echo $?)"
db_labels='!customer-terms and !HU-WRK-007'
liquibase update >/dev/null
check 'the five changesets reapply to 49 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 49 ]; echo $?)"
liquibase rollback-count 999 >/dev/null
liquibase update >/dev/null
liquibase validate >/dev/null
check 'a full build from empty without any label filter applies exactly 49 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 49 ]; echo $?)"
