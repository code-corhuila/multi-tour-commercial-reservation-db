#!/usr/bin/env bash
# Sourced by db-ci.sh last, on the same disposable PostgreSQL instance.
# HU-COM-003 -db spec, "Decisions taken by default (2026-10-28)": DP-01 coverage, DP-02 calendar dates,
# DP-03 value, DP-05 optional cap, DP-07 status, DP-08 priority ties. NOT built and NOT asserted:
# accumulation DP-04, conditions of use DP-06, and any trigger that would force the coverage rule.
dp_rule_table="$SCHEMA.discount_rule"
dp_service_table="$SCHEMA.discount_rule_service"
dp_rule() { # id, covers_all_services, cap_cents, status, ends_on, starts_on, priority (SQL literals; empty = default)
  echo "insert into $dp_rule_table (discount_rule_id, tenant_id, name, starts_on, ends_on, priority, calculation_base, discount_type, discount_percentage_bp, discount_amount_cents, status, covers_all_services, cap_cents) values (${1:-gen_random_uuid()}, '$tenant', 'Season offer', ${6:-'2026-01-01'}, ${5:-'2026-12-31'}, ${7:-1}, 'Valor original', 'Porcentual', 1250, NULL, ${4:-'ACTIVE'}, ${2:-true}, ${3:-NULL})"
}
dp_link() { # rule id literal, service id literal, tenant literal
  echo "insert into $dp_service_table (tenant_id, discount_rule_id, service_id) values (${3:-'$tenant'}, $1, $2)"
}
dp_refusal() { # SQL, text of the engine answer, description
  local answer
  answer="$(engine "$1" 2>&1 || true)"; printf '%s\n' "$answer"
  check "HU-COM-003 $3 is refused by $2" "$(printf '%s\n' "$answer" | grep -q "$2"; echo $?)"
}
dp_accepted() { # SQL, description
  local status=0
  engine "begin; $1; rollback;" || status=$?
  check "HU-COM-003 $2 is accepted" "$status"
}

echo 'HU-COM-003 persistence - base: the 36 changesets of HU-COM-001..005 without the persistence slice'
liquibase rollback-count 999 >/dev/null
db_labels='!discount-persistence and !discount-rule-codes and !outbox-widening and !authorizable-reason and !additional-discount-immutable and !HU-COM-006'
liquibase update >/dev/null
dp_base="$(snapshot)"
check 'base holds exactly 36 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 36 ]; echo $?)"

echo 'HU-COM-003 persistence - probes written first: red before the changesets, green after'
db_labels='!discount-rule-codes and !outbox-widening and !authorizable-reason and !additional-discount-immutable and !HU-COM-006'
liquibase update >/dev/null
check 'the slice brings the control table to 39 changesets (tables 013, alter 008, indexes 010)' "$([ "$(sql "select count(*) from $CONTROL")" = 39 ]; echo $?)"

echo 'DP-01 coverage as a column and a child table'
check 'DP-02/03/05/01 discount_rule keeps its columns and adds covers_all_services boolean NOT NULL and cap_cents bigint NULL' "$([ "$(cols_of discount_rule)" = 'discount_rule_id uuid NO,tenant_id uuid NO,name text NO,starts_on date NO,ends_on date NO,priority integer NO,calculation_base text NO,discount_type text NO,discount_percentage_bp integer YES,discount_amount_cents bigint YES,status text NO,covers_all_services boolean NO,cap_cents bigint YES' ]; echo $?)"
check 'no accumulation or conditions column exists (DP-04 and DP-06 stay open)' "$([ "$(sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name in ('discount_rule','discount_rule_service') and (column_name ~ 'accumul|condition|stackable')")" = 0 ]; echo $?)"
check 'covers_all_services has no DEFAULT: the service states it' "$([ "$(sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='discount_rule' and column_name='covers_all_services' and column_default is not null")" = 0 ]; echo $?)"
dp_answer="$(engine "insert into $dp_rule_table (discount_rule_id, tenant_id, name, starts_on, ends_on, priority, calculation_base, discount_type, discount_percentage_bp, status) values (gen_random_uuid(), '$tenant', 'x', '2026-01-01', '2026-02-01', 1, 'Valor original', 'Porcentual', 100, 'ACTIVE');" 2>&1 || true)"; printf '%s\n' "$dp_answer"
check 'a rule that does not say its coverage is refused (SQLSTATE 23502, column covers_all_services)' "$(printf '%s\n' "$dp_answer" | grep -q 'ERROR:  23502.*column "covers_all_services"'; echo $?)"
check 'chk_discount_rule_coverage_required exists as a NOT NULL constraint' "$([ "$(sql "select count(*) from pg_constraint where conrelid=to_regclass('$dp_rule_table') and contype='n' and conname='chk_discount_rule_coverage_required'")" = 1 ]; echo $?)"
dp_accepted "$(dp_rule '' true)" 'a rule that covers every service'
dp_accepted "$(dp_rule "'$(aid 1101)'" false); $(catalog_row "'$(aid 1102)'"); $(dp_link "'$(aid 1101)'" "'$(aid 1102)'")" 'a selected-services rule with one linked service'

echo 'DP-01 discount_rule_service'
check 'discount_rule_service exists only in the domain schema' "$([ "$(sql "select count(*) from pg_tables where tablename='discount_rule_service' and schemaname='$SCHEMA'")" = 1 ] && [ "$(sql "select count(*) from pg_tables where tablename='discount_rule_service' and schemaname='public'")" = 0 ]; echo $?)"
check 'discount_rule_service has exactly tenant, rule and service, all NOT NULL uuid' "$([ "$(cols_of discount_rule_service)" = 'tenant_id uuid NO,discount_rule_id uuid NO,service_id uuid NO' ]; echo $?)"
check 'the pair (rule, service) is the primary key pk_discount_rule_service' "$([ "$(sql "select string_agg(a.attname, ',' order by k.ord) from pg_constraint c cross join unnest(c.conkey) with ordinality k(attnum, ord) join pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.attnum where c.conname='pk_discount_rule_service' and c.contype='p'")" = 'discount_rule_id,service_id' ]; echo $?)"
check 'both foreign keys exist with ON DELETE RESTRICT' "$([ "$(sql "select count(*) from pg_constraint where conrelid=to_regclass('$dp_service_table') and contype='f' and confdeltype='r' and ((conname='fk_discount_rule_service_rule' and confrelid=to_regclass('$dp_rule_table')) or (conname='fk_discount_rule_service_service' and confrelid=to_regclass('$SCHEMA.catalog_service')))")" = 2 ]; echo $?)"
check 'service_id has its own foreign key index; the rule side is served by the primary key' "$([ "$(sql "select count(*) from pg_indexes where schemaname='$SCHEMA' and indexname='idx_discount_rule_service_service_id' and indexdef like '%(service_id)%'")" = 1 ]; echo $?)"
engine "$(dp_rule "'$(aid 1201)'" false); $(dp_rule "'$(aid 1202)'" false); $(catalog_row "'$(aid 1211)'"); $(catalog_row "'$(aid 1212)'"); $(dp_link "'$(aid 1201)'" "'$(aid 1211)'");" >/dev/null || true
dp_refusal "$(dp_link "'$(aid 1201)'" "'$(aid 1211)'");" pk_discount_rule_service 'the same service listed twice for one rule'
dp_refusal "$(dp_link "'$(aid 1299)'" "'$(aid 1211)'");" fk_discount_rule_service_rule 'a link to a rule that does not exist'
dp_refusal "$(dp_link "'$(aid 1201)'" "'$(aid 1299)'");" fk_discount_rule_service_service 'a link to a service that does not exist'
dp_refusal "$(dp_link "'$(aid 1201)'" "'$(aid 1212)'" NULL);" '23502' 'a link without tenant'
dp_accepted "$(dp_link "'$(aid 1201)'" "'$(aid 1212)'")" 'a second service for the same rule'
dp_accepted "$(dp_link "'$(aid 1202)'" "'$(aid 1211)'")" 'the same service under another rule'
check 'no trigger on the two tables: the coverage rule is not forced by the engine (not proposed)' "$([ "$(sql "select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid where c.relnamespace='$SCHEMA'::regnamespace and not t.tgisinternal and c.relname in ('discount_rule','discount_rule_service')")" = 0 ]; echo $?)"
for dp_role in "$writer" "$app"; do
  check "no DELETE for $dp_role on discount_rule_service" "$([ "$(sql "select has_table_privilege('$dp_role','$dp_service_table','DELETE')")" = f ]; echo $?)"
  check "$dp_role keeps SELECT, INSERT, UPDATE on discount_rule_service" "$([ "$(sql "select has_table_privilege('$dp_role','$dp_service_table','SELECT') and has_table_privilege('$dp_role','$dp_service_table','INSERT') and has_table_privilege('$dp_role','$dp_service_table','UPDATE')")" = t ]; echo $?)"
done
dp_refusal "delete from $dp_service_table;" 'permission denied for table discount_rule_service' 'DELETE as the application user'
check 'the reader can read discount_rule_service' "$([ "$(sql "select has_table_privilege('$reader','$dp_service_table','SELECT')")" = t ]; echo $?)"

echo 'DP-05 optional cap'
check 'cap_cents is nullable and bigint' "$([ "$(sql "select data_type || ' ' || is_nullable from information_schema.columns where table_schema='$SCHEMA' and table_name='discount_rule' and column_name='cap_cents'")" = 'bigint YES' ]; echo $?)"
dp_refusal "$(dp_rule '' true 0);" chk_discount_rule_cap 'a zero cap'
dp_refusal "$(dp_rule '' true -5);" chk_discount_rule_cap 'a negative cap'
dp_accepted "$(dp_rule '' true NULL)" 'a rule without cap'
dp_accepted "$(dp_rule '' true 500000)" 'a rule with a positive cap'

echo 'DP-07 status ACTIVE or INACTIVE'
dp_refusal "$(dp_rule '' true '' "'UNDECIDED'");" chk_discount_rule_status 'an unknown status'
dp_refusal "$(dp_rule '' true '' "'active'");" chk_discount_rule_status 'a lower-case status'
dp_accepted "$(dp_rule '' true '' "'ACTIVE'"); $(dp_rule '' true '' "'INACTIVE'")" 'both ACTIVE and INACTIVE'
dp_accepted "$(dp_rule "'$(aid 1301)'"); update $dp_rule_table set status='INACTIVE' where discount_rule_id='$(aid 1301)'" 'inactivating a rule'

echo 'DP-02 calendar dates, inclusive at both ends'
check 'starts_on and ends_on are date, not timestamp' "$([ "$(sql "select string_agg(data_type, ',' order by column_name) from information_schema.columns where table_schema='$SCHEMA' and table_name='discount_rule' and column_name in ('starts_on','ends_on')")" = 'date,date' ]; echo $?)"
dp_accepted "$(dp_rule '' true '' '' "'2026-03-01'" "'2026-03-01'")" 'a one-day validity (starts_on = ends_on)'
dp_refusal "$(dp_rule '' true '' '' "'2026-02-28'" "'2026-03-01'");" chk_discount_rule_validity 'an end date before the start date'
engine "$(dp_rule "'$(aid 1401)'" true '' '' "'2026-03-31'" "'2026-03-01'");" >/dev/null || true
check 'a rule is in force on its first and last day, and not the day after' "$([ "$(sql "select (select count(*) from $dp_rule_table where discount_rule_id='$(aid 1401)' and date '2026-03-01' between starts_on and ends_on)::text || (select count(*) from $dp_rule_table where discount_rule_id='$(aid 1401)' and date '2026-03-31' between starts_on and ends_on)::text || (select count(*) from $dp_rule_table where discount_rule_id='$(aid 1401)' and date '2026-04-01' between starts_on and ends_on)")" = 110 ]; echo $?)"

echo 'DP-08 priority ties accepted: no UNIQUE on tenant and priority'
dp_accepted "$(dp_rule '' true '' '' '' '' 7); $(dp_rule '' true '' '' '' '' 7)" 'two rules of one tenant with equal priority'
check 'discount_rule has no UNIQUE constraint and no unique index besides its primary key' "$([ "$(sql "select count(*) from pg_constraint where conrelid=to_regclass('$dp_rule_table') and contype='u'")" = 0 ] && [ "$(sql "select count(*) from pg_indexes where schemaname='$SCHEMA' and tablename='discount_rule' and indexdef ilike '%unique%' and indexname <> 'pk_discount_rule'")" = 0 ]; echo $?)"

echo 'No DELETE on discount_rule is preserved'
check 'writer and application user still have no DELETE on discount_rule' "$([ "$(sql "select has_table_privilege('$writer','$dp_rule_table','DELETE') or has_table_privilege('$app','$dp_rule_table','DELETE')")" = f ]; echo $?)"

echo 'Idempotence, exact revert, reapply and a build from empty'
dp_second="$(liquibase update 2>&1)"; printf '%s\n' "$dp_second"
check 'a second update applies zero changesets' "$(printf '%s\n' "$dp_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
sql "truncate $dp_service_table, $dp_rule_table cascade" >/dev/null 2>&1 || true
liquibase rollback-count 3
dp_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$dp_base" "$dp_reverted"
check 'the three-change revert restores columns, constraints, indexes and privileges exactly' "$([ -n "$dp_base" ] && [ "$dp_reverted" = "$dp_base" ] && [ "$(sql "select count(*) from $CONTROL")" = 36 ]; echo $?)"
check 'the child table is gone after the revert' "$([ "$(sql "select to_regclass('$dp_service_table') is null")" = t ]; echo $?)"
liquibase update >/dev/null
check 'the slice reapplies to 39 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 39 ]; echo $?)"
liquibase rollback-count 999 >/dev/null
liquibase update >/dev/null
liquibase validate >/dev/null
check 'a full build from empty without any label filter applies exactly 39 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 39 ]; echo $?)"
