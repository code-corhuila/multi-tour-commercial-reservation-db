#!/usr/bin/env bash
# Sourced by db-ci.sh after the payment checks, on the same disposable PostgreSQL instance.
# HU-COM-001 -db, task T-05 (decision of Jhon, 2026-10-30; PDR RF-004): the tenant_catalog_settings table (03_tables/025), one row per
# tenant with the collaborator-editing flag. Label collaborator-editing-flag on the single changeset.
# Probes are written first: red before the changeset, green after (Annex J.1).
cf_t="$SCHEMA.tenant_catalog_settings"
cf_a="$(aid 4001)"; cf_b="$(aid 4002)"
cf_sql() { sql "$1" 2>/dev/null || true; }
cf_refusal() { # SQL, text of the engine answer, description
  local answer
  answer="$(engine "$1" 2>&1 || true)"; printf '%s\n' "$answer"
  check "HU-COM-001 collaborator flag: $3 is refused by $2" "$(printf '%s\n' "$answer" | grep -q "$2"; echo $?)"
}

echo 'HU-COM-001 collaborator flag - base: the changesets that exist before the table'
liquibase rollback-count 999 >/dev/null
db_labels='!collaborator-editing-flag'
liquibase update >/dev/null
cf_base="$(snapshot)"
check 'base holds exactly 84 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 84 ]; echo $?)"
check 'on that base tenant_catalog_settings does not exist' "$([ "$(sql "select to_regclass('$cf_t') is null")" = t ]; echo $?)"

echo 'HU-COM-001 collaborator flag - probes written first: red before the changeset, green after'
db_labels='collaborator-editing-flag'
liquibase update >/dev/null
check 'the table brings the control table to 85 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 85 ]; echo $?)"

echo 'the table (RF-004, T-05)'
cf_cols='tenant_id uuid NO,collaborator_editing boolean NO,updated_by uuid NO,created_at timestamp with time zone NO,updated_at timestamp with time zone NO'
check 'tenant_catalog_settings holds its five columns, all required' "$([ "$(cols_of tenant_catalog_settings)" = "$cf_cols" ]; echo $?)"
check 'collaborator_editing is the only column with a DEFAULT and it is false' "$([ "$(cf_sql "select string_agg(column_name || '=' || column_default, ',') from information_schema.columns where table_schema='$SCHEMA' and table_name='tenant_catalog_settings' and column_default is not null")" = 'collaborator_editing=false' ]; echo $?)"
check 'the primary key is tenant_id: one row per tenant' "$([ "$(cf_sql "select pg_get_constraintdef(oid) from pg_constraint where conname='pk_tenant_catalog_settings' and conrelid='$cf_t'::regclass")" = 'PRIMARY KEY (tenant_id)' ]; echo $?)"
check 'nothing new appears in public' "$([ "$(sql "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p','v','m','S','f') and c.relname not like 'databasechangelog%'")" = 0 ]; echo $?)"
check 'every constraint is named pk_, uq_, chk_ or fk_' "$([ "$(cf_sql "select count(*) from pg_constraint where conrelid='$cf_t'::regclass and conname !~ '^(pk|uq|chk|fk)_'")" = 0 ]; echo $?)"
check 'the table starts empty: an absent row means the flag is off, nothing is seeded' "$([ "$(sql "select count(*) from $cf_t")" = 0 ]; echo $?)"

echo 'the rows'
engine "insert into $cf_t (tenant_id, updated_by, created_at, updated_at) values ('$cf_a', '$actor', now(), now());" >/dev/null || true
check 'a row that states no flag takes false' "$([ "$(sql "select collaborator_editing from $cf_t where tenant_id='$cf_a'")" = f ]; echo $?)"
engine "insert into $cf_t (tenant_id, collaborator_editing, updated_by, created_at, updated_at) values ('$cf_b', true, '$actor', now(), now());" >/dev/null || true
check 'another tenant keeps its own true and the first one stays false' "$([ "$(sql "select string_agg(collaborator_editing::text, ',' order by tenant_id) from $cf_t")" = 'false,true' ]; echo $?)"
cf_refusal "insert into $cf_t (tenant_id, collaborator_editing, updated_by, created_at, updated_at) values ('$cf_a', true, '$actor', now(), now());" pk_tenant_catalog_settings 'a second row for the same tenant'
cf_refusal "insert into $cf_t (tenant_id, collaborator_editing, updated_by, created_at, updated_at) values (null, true, '$actor', now(), now());" 'ERROR:  23502.*column "tenant_id"' 'a row without tenant'
cf_refusal "insert into $cf_t (tenant_id, collaborator_editing, updated_by, created_at, updated_at) values (gen_random_uuid(), null, '$actor', now(), now());" 'ERROR:  23502.*column "collaborator_editing"' 'a null flag'
cf_refusal "insert into $cf_t (tenant_id, updated_by, created_at, updated_at) values (gen_random_uuid(), null, now(), now());" 'ERROR:  23502.*column "updated_by"' 'a row without who changed it'
cf_refusal "insert into $cf_t (tenant_id, updated_by, created_at) values (gen_random_uuid(), '$actor', now());" 'ERROR:  23502.*column "updated_at"' 'a row without updated_at'
engine "update $cf_t set collaborator_editing = true, updated_at = now() where tenant_id = '$cf_a';" >/dev/null || true
check 'the application user may update the flag (idempotent PUT)' "$([ "$(sql "select collaborator_editing from $cf_t where tenant_id='$cf_a'")" = t ]; echo $?)"

echo 'privileges'
check 'the application user selects, inserts and updates; neither it nor the writer deletes' "$([ "$(privileges_of "$cf_t")" = 'INSERT,SELECT,UPDATE' ] && [ "$(sql "select has_table_privilege('$writer','$cf_t','DELETE')")" = f ]; echo $?)"
check 'the reader reads and does not write' "$([ "$(sql "select has_table_privilege('$reader','$cf_t','SELECT') and not has_table_privilege('$reader','$cf_t','INSERT')")" = t ]; echo $?)"
cf_refusal "delete from $cf_t;" 'permission denied for table tenant_catalog_settings' 'DELETE as the application user'

echo 'Idempotence, exact revert and reapply'
cf_second="$(liquibase update 2>&1)"; printf '%s\n' "$cf_second"
check 'a second update applies zero changesets' "$(printf '%s\n' "$cf_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
sql "truncate $cf_t" >/dev/null 2>&1 || true
liquibase rollback-count 1
cf_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$cf_base" "$cf_reverted"
check 'the one-change revert restores the schema exactly and leaves 84 changesets' "$([ -n "$cf_base" ] && [ "$cf_reverted" = "$cf_base" ] && [ "$(sql "select count(*) from $CONTROL")" = 84 ]; echo $?)"
check 'the table is gone after the revert' "$([ "$(sql "select to_regclass('$cf_t') is null")" = t ]; echo $?)"
db_labels='collaborator-editing-flag'
liquibase update >/dev/null
check 'the changeset reapplies to 85 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 85 ]; echo $?)"
