#!/usr/bin/env bash
# Sourced by db-ci.sh, using its one disposable PostgreSQL 18 instance and runner.
# DP-03 (Fernanda, 2026-10-11) overrides plan D-04; labels follow the data dictionary.
discount_table="$SCHEMA.discount_rule"
discount_row() { # id expression, end date, start date, base, percentage, amount, type, priority, tenant
  local ends="${2:-}" starts="${3:-}" owner="${9:-}"
  [ -n "$ends" ] || ends="'2026-12-31'"
  [ -n "$starts" ] || starts="'2026-01-01'"
  [ -n "$owner" ] || owner="'$tenant'"
  echo "insert into $discount_table (discount_rule_id, tenant_id, name, starts_on, ends_on, priority, calculation_base, discount_type, discount_percentage_bp, discount_amount_cents, status) values (${1:-gen_random_uuid()}, $owner, 'Season offer', $starts, $ends, ${8:-1}, '${4:-Valor original}', '${7:-Porcentual}', ${5:-1250}, ${6:-NULL}, 'UNDECIDED')"
}
discount_refusal() { # SQL, named engine constraint
  local answer
  answer="$(engine "$1" 2>&1 || true)"; printf '%s\n' "$answer"
  check "HU-COM-003 invalid insert is rejected by $2" "$(printf '%s\n' "$answer" | grep -q "$2"; echo $?)"
}
discount_not_null_refusal() { # SQL, named NOT NULL constraint, column (PostgreSQL 18 reports the column in the error, not the constraint name)
  local answer
  answer="$(engine "$1" 2>&1 || true)"; printf '%s\n' "$answer"
  check "HU-COM-003 invalid insert is rejected by $2 (SQLSTATE 23502, column $3)" "$(printf '%s\n' "$answer" | grep -q "ERROR:  23502.*column \"$3\""; echo $?)"
  check "$2 exists in the catalog as a NOT NULL constraint" "$([ "$(sql "select count(*) from pg_constraint where conrelid=to_regclass('$discount_table') and contype='n' and conname='$2'")" = 1 ]; echo $?)"
}
discount_table_checks() {
  echo 'T-07 STEP 2 - table in the domain schema, no new domain object in public'
  check 'AC-D3.1 discount_rule exists only in commercial_reservation' "$([ "$(sql "select count(*) from pg_tables where tablename='discount_rule' and schemaname='$SCHEMA'")" = 1 ] && [ "$(sql "select count(*) from pg_tables where tablename='discount_rule' and schemaname='public'")" = 0 ]; echo $?)"
  echo 'T-07 STEP 3 - exact columns, types, nullability; no open-decision column'
  engine "select column_name, data_type, is_nullable from information_schema.columns where table_schema='$SCHEMA' and table_name='discount_rule' order by ordinal_position;"
  local expected actual
  expected='discount_rule_id uuid NO,tenant_id uuid NO,name text NO,starts_on date NO,ends_on date NO,priority integer NO,calculation_base text NO,discount_type text NO,discount_percentage_bp integer YES,discount_amount_cents bigint YES,status text NO'
  actual="$(sql "select string_agg(column_name || ' ' || data_type || ' ' || is_nullable, ',' order by ordinal_position) from information_schema.columns where table_schema='$SCHEMA' and table_name='discount_rule'")"
  check 'AC-D3.2/6 exact confirmed columns and mandatory UUID tenant; open decisions absent' "$([ "$actual" = "$expected" ]; echo $?)"
  check 'DP-07 status has no CHECK; DP-08 priority has no UNIQUE' "$([ "$(sql "select count(*) from pg_constraint where conrelid=to_regclass('$discount_table') and ((contype='c' and pg_get_constraintdef(oid) ~ '\\mstatus\\M') or contype='u')")" = 0 ]; echo $?)"
  echo 'T-07 STEP 4 - six invalid inserts rejected by their named constraints'
  discount_not_null_refusal "$(discount_row '' '' NULL);" chk_discount_rule_starts_on_required starts_on
  discount_not_null_refusal "$(discount_row '' NULL);" chk_discount_rule_ends_on_required ends_on
  discount_refusal "$(discount_row '' "'2025-12-31'");" chk_discount_rule_validity
  discount_refusal "$(discount_row '' '' '' UNKNOWN);" chk_discount_rule_calculation_base
  discount_refusal "$(discount_row '' '' '' '' 1250 100);" chk_discount_rule_value
  discount_refusal "$(discount_row '' '' '' '' NULL NULL);" chk_discount_rule_value
  discount_refusal "$(discount_row '' '' '' '' 10001);" chk_discount_rule_percentage
  discount_refusal "$(discount_row '' '' '' '' NULL 0 'Valor fijo');" chk_discount_rule_amount
  discount_refusal "$(discount_row '' '' '' '' 1250 NULL 'Valor fijo');" chk_discount_rule_value
  discount_refusal "$(discount_row '' '' '' '' 1250 NULL UNKNOWN);" chk_discount_rule_type
  discount_refusal "$(discount_row '' '' '' '' '' '' '' 0);" chk_discount_rule_priority
  discount_not_null_refusal "$(discount_row '' '' '' '' '' '' '' '' NULL);" chk_discount_rule_tenant_required tenant_id
  echo 'T-07 STEP 5 - writer and inherited application role cannot DELETE'
  check 'T-04 app inherits real commercial_reservation_writer role' "$([ "$(sql "select pg_has_role('$app','$writer','member')")" = t ]; echo $?)"
  local role answer
  for role in "$writer" "$app"; do
    check "AC-D3.7 $role has no DELETE grant" "$([ "$(sql "select has_table_privilege('$role', '$discount_table', 'DELETE')" 2>/dev/null || true)" = f ]; echo $?)"
    answer="$(engine "delete from $discount_table;" "$role" 2>&1 || true)"; printf '%s\n' "$answer"
    check "AC-D3.7 DELETE as $role is denied by privilege" "$(printf '%s\n' "$answer" | grep -q 'permission denied for table discount_rule'; echo $?)"
  done
  local insert_status=0
  engine "begin; $(discount_row); $(discount_row '' '' '' 'Subtotal posterior al descuento anterior' NULL 100 'Valor fijo'); rollback;" || insert_status=$?
  check 'valid percentage/fixed amount and equal priority are accepted; unknown status remains allowed' "$insert_status"
  echo 'T-07 STEP 6 - EXPLAIN real tenant validity query with selective fixtures'
  if [ "$(sql "select to_regclass('$discount_table') is not null")" = t ]; then
    sql "insert into $discount_table select gen_random_uuid(), md5((n%20)::text)::uuid, 'Plan fixture', date '2020-01-01'+(n%2000), date '2020-01-01'+(n%2000)+5, 1, 'Valor original', 'Porcentual', 100, null, 'UNDECIDED' from generate_series(1,20000) n; analyze $discount_table;" >/dev/null
  fi
  local plan
  plan="$(engine "explain select discount_rule_id, priority from $discount_table where tenant_id=md5('1')::uuid and starts_on <= date '2022-01-01' and ends_on >= date '2022-01-01' order by priority;" 2>&1 || true)"; printf '%s\n' "$plan"
  check 'AC-D3.9 planner uses idx_discount_rule_tenant_validity without disabling sequential scan' "$(printf '%s\n' "$plan" | grep -q idx_discount_rule_tenant_validity; echo $?)"
  check 'T-03 tenant-only index exists with its declared columns' "$([ "$(sql "select count(*) from pg_indexes where schemaname='$SCHEMA' and indexname='idx_discount_rule_tenant_id' and indexdef like '%(tenant_id)%'")" = 1 ]; echo $?)"
}
echo 'HU-COM-003 T-07 STEP 1 - rebuild prerequisite HU-COM-001 + HU-COM-002 (23)'
liquibase rollback-count 999
db_labels='!HU-COM-003 and !HU-COM-004 and !HU-COM-005'
liquibase update
discount_base_snapshot="$(snapshot)"
check 'T-01 schema, own control table, outbox, writer and no business DELETE exist' "$([ "$(sql "select (to_regnamespace('$SCHEMA') is not null and to_regclass('$CONTROL') is not null and to_regclass('$SCHEMA.outbox_event') is not null and exists(select 1 from pg_roles where rolname='$writer') and (select count(*) from information_schema.tables t where t.table_schema='$SCHEMA' and t.table_name not in ('idempotency_key','outbox_event') and has_table_privilege('$writer',format('%I.%I',t.table_schema,t.table_name),'DELETE'))=0)")" = t ]; echo $?)"
check 'T-01 commercial_reservation_app inherits the NOLOGIN writer bundle' "$([ "$(sql "select pg_has_role('$app','$writer','member')")" = t ] && [ "$(sql "select rolcanlogin from pg_roles where rolname='$writer'")" = f ]; echo $?)"
check 'T-01 prior stories applied exactly 23 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 23 ]; echo $?)"
if [ "${TDD_PHASE:-all}" = table ]; then
  db_labels='!HU-COM-003 and !HU-COM-004 and !HU-COM-005'
else
  db_labels='HU-COM-003 and discount-table'
fi
liquibase update
discount_table_checks

if [ "${TDD_PHASE:-all}" = table ]; then exit "$fail"; fi

discount_event() { # event SQL id, rule SQL id, previous jsonb SQL expression
  echo "insert into $SCHEMA.outbox_event (outbox_event_id, tenant_id, event_type, discount_rule_id, actor_id, occurred_at, previous_discount_rule_state, new_discount_rule_state) select $1, tenant_id, 'DiscountRuleChanged', discount_rule_id, '$actor', now(), $3, to_jsonb(r) from $discount_table r where discount_rule_id=$2"
}
discount_outbox_checks() {
  echo 'HU-COM-003 T-05 - application-written full previous/new state and atomicity'
  check 'discount_rule_id is a nullable UUID on the same outbox' "$([ "$(sql "select data_type || ' ' || is_nullable from information_schema.columns where table_schema='$SCHEMA' and table_name='outbox_event' and column_name='discount_rule_id'")" = 'uuid YES' ]; echo $?)"
  check 'discount FK uses ON DELETE RESTRICT and the tenant/rule index' "$([ "$(sql "select count(*) from pg_constraint where conrelid='$SCHEMA.outbox_event'::regclass and conname='fk_outbox_event_discount_rule' and confrelid=to_regclass('$discount_table') and confdeltype='r'")" = 1 ] && [ "$(sql "select count(*) from pg_indexes where schemaname='$SCHEMA' and indexname='idx_outbox_event_tenant_id_discount_rule_id' and indexdef like '%(tenant_id, discount_rule_id)%'")" = 1 ]; echo $?)"
  local phase rule event prior change before result actual saved_tenant
  saved_tenant="$tenant"; tenant="$other_tenant"
  for phase in create update inactivate; do
    rule="'$(aid 901)'"; event="'$(aid 951)'"; prior=NULL; before=ABSENT
    if [ "$phase" = create ]; then change="$(discount_row "$rule")"
    else
      prior="'$(sql "select to_jsonb(r) from $discount_table r where discount_rule_id=$rule")'::jsonb"
      before="$(sql "select name || '/' || status from $discount_table where discount_rule_id=$rule")"
      if [ "$phase" = update ]; then change="update $discount_table set name='Updated offer' where discount_rule_id=$rule"
      else change="update $discount_table set status='INACTIVE' where discount_rule_id=$rule"; fi
    fi
    result=0
    engine "begin; $change; $(discount_event "$event" "$rule" "$prior"); rollback;" || result=$?
    check "DiscountRuleChanged $phase ROLLBACK executes as application role" "$result"
    actual="$(sql "select coalesce((select name || '/' || status from $discount_table where discount_rule_id=$rule),'ABSENT') || '/' || (select count(*) from $SCHEMA.outbox_event where outbox_event_id=$event)")"
    check "DiscountRuleChanged $phase ROLLBACK leaves neither rule change nor event" "$([ "$actual" = "$before/0" ]; echo $?)"
    result=0
    engine "begin; $change; $(discount_event "$event" "$rule" "$prior"); commit;" || result=$?
    check "DiscountRuleChanged $phase COMMIT executes as application role" "$result"
    check "DiscountRuleChanged $phase has exactly one correct tenant/aggregate and full audit snapshots" "$([ "$(sql "select count(*) from $SCHEMA.outbox_event e join $discount_table r using(discount_rule_id) where outbox_event_id=$event and e.tenant_id='$tenant' and e.service_id is null and e.association_id is null and e.new_discount_rule_state=to_jsonb(r) and e.previous_discount_rule_state is not distinct from $prior" 2>/dev/null || true)" = 1 ]; echo $?)"
    engine "select outbox_event_id, tenant_id, event_type, service_id, association_id, discount_rule_id, previous_discount_rule_state, new_discount_rule_state from $SCHEMA.outbox_event where outbox_event_id=$event;" || true
    engine "delete from $SCHEMA.outbox_event where outbox_event_id=$event;" || true
  done
  tenant="$saved_tenant"
  # Both legacy fixture aggregates exist, so aggregate refusals cannot be false positives from FKs.
  engine "$(catalog_row "'$(aid 801)'"); $(ae_row "'$(aid 802)'");" || true
  local event_sql
  event_sql="$(discount_event 'gen_random_uuid()' "'$(aid 901)'" NULL)"
  for extra in service_id association_id; do
    local extra_id="$(aid 801)"; [ "$extra" = association_id ] && extra_id="$(aid 802)"
    discount_refusal "begin; $event_sql; update $SCHEMA.outbox_event set $extra='$extra_id' where event_type='DiscountRuleChanged'; commit;" chk_outbox_event_exactly_one_aggregate
  done
  # An UPDATE after the insert is a separate statement: PostgreSQL data-changing CTEs share a snapshot.
  discount_refusal "begin; $event_sql; update $SCHEMA.outbox_event set service_id='$(aid 801)', association_id='$(aid 802)' where event_type='DiscountRuleChanged'; commit;" chk_outbox_event_exactly_one_aggregate
  discount_refusal "begin; $event_sql; update $SCHEMA.outbox_event set discount_rule_id=null where event_type='DiscountRuleChanged'; commit;" chk_outbox_event_exactly_one_aggregate
  discount_refusal "begin; $event_sql; update $SCHEMA.outbox_event set event_type='CatalogServiceReactivated', previous_catalog_status='INACTIVE', new_catalog_status='ACTIVE', previous_discount_rule_state=null, new_discount_rule_state=null where event_type='DiscountRuleChanged'; commit;" chk_outbox_event_exactly_one_aggregate
  discount_refusal "begin; $event_sql; update $SCHEMA.outbox_event set discount_rule_id='$(aid 999)' where event_type='DiscountRuleChanged'; commit;" fk_outbox_event_discount_rule
  # Generalizing the aggregate selector must preserve catalog/association event semantics.
  engine "$(catalog_row "'$(aid 811)'"); $(ae_row "'$(aid 812)'");" || true
  local legacy_catalog legacy_association
  legacy_catalog="$(engine "insert into $SCHEMA.outbox_event (outbox_event_id, tenant_id, event_type, service_id, previous_catalog_status, new_catalog_status, actor_id, occurred_at) values ('$(aid 861)', '$tenant', 'CatalogServiceInactivated', '$(aid 811)', 'ACTIVE', 'INACTIVE', '$actor', now());" 2>&1 || true)"
  legacy_association="$(engine "insert into $SCHEMA.outbox_event (outbox_event_id, tenant_id, event_type, association_id, previous_catalog_status, new_catalog_status, actor_id, occurred_at) values ('$(aid 862)', '$tenant', 'EstablishmentAssociationPublished', '$(aid 812)', NULL, 'ACTIVE', '$actor', now());" 2>&1 || true)"
  check 'generalized outbox still accepts catalog and association events; previous_catalog_status stays nullable' "$(printf '%s\n%s\n' "$legacy_catalog" "$legacy_association" | grep -q 'INSERT 0 1'; echo $?)"
  check 'legacy event rows select exactly one aggregate and keep discount snapshots null' "$([ "$(sql "select count(*) from $SCHEMA.outbox_event where outbox_event_id in ('$(aid 861)','$(aid 862)') and discount_rule_id is null and previous_discount_rule_state is null and new_discount_rule_state is null and ((service_id is not null and association_id is null) or (service_id is null and association_id is not null))")" = 2 ]; echo $?)"
  engine "delete from $SCHEMA.outbox_event where outbox_event_id in ('$(aid 861)','$(aid 862)');" || true
  check 'D-10 no trigger writes rule events' "$([ "$(sql "select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='$SCHEMA' and not t.tgisinternal and (c.relname='discount_rule' or pg_get_functiondef(t.tgfoid) ilike '%outbox_event%')")" = 0 ]; echo $?)"
}
if [ "${TDD_PHASE:-all}" = outbox ]; then
  discount_outbox_checks
  exit "$fail"
fi

db_labels='HU-COM-003 and discount-outbox'
liquibase update
discount_outbox_checks

echo 'T-07 STEP 7 - second update, protected rollback, exact revert and reapply'
db_labels='HU-COM-003 and !discount-persistence'
discount_second="$(liquibase update 2>&1)"; printf '%s\n' "$discount_second"
check 'AC-D3.10 second full update applies zero changesets' "$(printf '%s\n' "$discount_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
check 'HU-COM-003 adds exactly four changesets (23 -> 27)' "$([ "$(sql "select count(*) from $CONTROL")" = 27 ]; echo $?)"

# Refusal is tested through Liquibase itself, not just by inspecting the rollback SQL.
engine "$(discount_event "'$(aid 952)'" "'$(aid 901)'" NULL);" || true
discount_protected="$(liquibase rollback-count 3 2>&1 || true)"; printf '%s\n' "$discount_protected"
check 'outbox rollback refuses while discount rule events remain' "$(printf '%s\n' "$discount_protected" | grep -q 'Cannot revert outbox generalization while discount rule events remain'; echo $?)"
check 'refused rollback preserves the discount event and rule' "$([ "$(sql "select count(*) from $SCHEMA.outbox_event where outbox_event_id='$(aid 952)'" 2>/dev/null || true)" = 1 ]; echo $?)"
engine "delete from $SCHEMA.outbox_event where discount_rule_id is not null;" || true
liquibase update # Restore the concurrently dropped index before the complete slice rollback.
liquibase rollback-count 4
discount_reverted="$(snapshot)"
printf 'HU-COM-001/002 schema MD5: %s\nAfter HU-COM-003 revert MD5: %s\n' "$discount_base_snapshot" "$discount_reverted"
check 'AC-D3.11 four-change revert restores exact columns/constraints/indexes/privileges' "$([ -n "$discount_base_snapshot" ] && [ "$discount_reverted" = "$discount_base_snapshot" ]; echo $?)"
check 'AC-D3.11 discount table is gone and all 23 prior changesets remain' "$([ "$(sql "select to_regclass('$discount_table') is null")" = t ] && [ "$(sql "select count(*) from $CONTROL")" = 23 ]; echo $?)"
liquibase update
check 'HU-COM-003 reapplies to the identical 27-changeset schema' "$([ "$(sql "select count(*) from $CONTROL")" = 27 ]; echo $?)"

# Also build all 27 in master-changelog order, without staging labels, from empty.
liquibase rollback-count 999
db_labels='!HU-COM-004 and !HU-COM-005 and !discount-persistence' # HU-COM-005 has its own staged checks in customer-checks.sh
liquibase update
liquibase validate
check 'full update from empty applies exactly 27 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 27 ]; echo $?)"
discount_second="$(liquibase update 2>&1)"; printf '%s\n' "$discount_second"
check 'fresh build second update applies zero changesets' "$(printf '%s\n' "$discount_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
liquibase rollback-count 999
check 'full revert removes the schema and both domain privilege roles' "$([ "$(sql "select (to_regnamespace('$SCHEMA') is null and not exists(select 1 from pg_roles where rolname in ('$reader','$writer')))")" = t ]; echo $?)"
liquibase update
check 'full reapply restores all 27 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 27 ]; echo $?)"
echo 'T-07 STEP 8 - db-ci.sh / db-ci.yml entrypoint result'
if [ "$fail" -eq 0 ]; then
  echo 'PASS: database CI entrypoint is green locally; remote GitHub workflow has not been run.'
else
  echo 'FAIL: at least one engine or runner check failed.'
fi

