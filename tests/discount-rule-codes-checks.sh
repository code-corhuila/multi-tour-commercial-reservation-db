#!/usr/bin/env bash
# Sourced by db-ci.sh after the persistence checks, on the same disposable PostgreSQL instance.
# HU-COM-003 -db, "Closing decisions (2026-10-28)" and the contract: the api and the contract speak
# ORIGINAL_VALUE / PREVIOUS_SUBTOTAL and PERCENTAGE / FIXED_AMOUNT, and the api requires createdAt and
# updatedAt (the evaluation filters by createdAt). Changeset ddl-alter-009, label discount-rule-codes.
# The table has no production data; the probes also prove that a row in the old words is migrated.
cd_table="$SCHEMA.discount_rule"
cd_rule() { # id, calculation_base, discount_type, bp, cents, created_at, updated_at (SQL literals; created_at OMIT drops both audit columns)
  local audit_cols='' audit_vals=''
  if [ "${6:-}" != OMIT ]; then audit_cols=', created_at, updated_at'; audit_vals=", ${6:-now()}, ${7:-now()}"; fi
  echo "insert into $cd_table (discount_rule_id, tenant_id, name, starts_on, ends_on, priority, calculation_base, discount_type, discount_percentage_bp, discount_amount_cents, status, covers_all_services$audit_cols) values (${1:-gen_random_uuid()}, '$tenant', 'codes probe', '2026-01-01', '2026-12-31', 1, ${2:-'ORIGINAL_VALUE'}, ${3:-'PERCENTAGE'}, ${4:-1000}, ${5:-NULL}, 'ACTIVE', true$audit_vals)"
}
cd_refusal() { # SQL, text of the engine answer, description
  local answer
  answer="$(engine "$1" 2>&1 || true)"; printf '%s\n' "$answer"
  check "HU-COM-003 codes: $3 is refused by $2" "$(printf '%s\n' "$answer" | grep -q "$2"; echo $?)"
}
cd_accepted() { # SQL, description
  local status=0
  engine "begin; $1; rollback;" || status=$?
  check "HU-COM-003 codes: $2 is accepted" "$status"
}

echo 'HU-COM-003 codes - base: the 39 changesets before ddl-alter-009, holding two rows in the old words'
liquibase rollback-count 999 >/dev/null
db_labels='!discount-rule-codes and !outbox-widening and !authorizable-reason and !additional-discount-immutable'
liquibase update >/dev/null
cd_base="$(snapshot)"
check 'base holds exactly 39 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 39 ]; echo $?)"
sql "insert into $cd_table (discount_rule_id, tenant_id, name, starts_on, ends_on, priority, calculation_base, discount_type, discount_percentage_bp, discount_amount_cents, status, covers_all_services) values ('$(aid 1501)', '$tenant', 'old words', '2026-01-01', '2026-12-31', 1, 'Subtotal posterior al descuento anterior', 'Porcentual', 500, NULL, 'ACTIVE', true), ('$(aid 1502)', '$tenant', 'old words fixed', '2026-01-01', '2026-12-31', 2, 'Valor original', 'Valor fijo', NULL, 90000, 'ACTIVE', true)" >/dev/null 2>&1 || true

echo 'HU-COM-003 codes - probes written first: red before the changeset, green after'
db_labels='!outbox-widening and !authorizable-reason and !additional-discount-immutable'
liquibase update >/dev/null
check 'ddl-alter-009 brings the control table to 40 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 40 ]; echo $?)"
check 'rows stored in the old words are migrated to the codes (PREVIOUS_SUBTOTAL/PERCENTAGE and ORIGINAL_VALUE/FIXED_AMOUNT)' "$([ "$(sql "select string_agg(calculation_base || '/' || discount_type, ',' order by priority) from $cd_table where discount_rule_id in ('$(aid 1501)','$(aid 1502)')")" = 'PREVIOUS_SUBTOTAL/PERCENTAGE,ORIGINAL_VALUE/FIXED_AMOUNT' ]; echo $?)"

echo 'created_at and updated_at'
check 'discount_rule has created_at and updated_at as timestamptz NOT NULL' "$([ "$(sql "select string_agg(column_name || ' ' || data_type || ' ' || is_nullable, ',' order by column_name) from information_schema.columns where table_schema='$SCHEMA' and table_name='discount_rule' and column_name in ('created_at','updated_at')")" = 'created_at timestamp with time zone NO,updated_at timestamp with time zone NO' ]; echo $?)"
check 'neither column keeps a DEFAULT: the service states the moment' "$([ "$(sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='discount_rule' and column_name in ('created_at','updated_at') and column_default is not null")" = 0 ]; echo $?)"
check 'both NOT NULL constraints are named' "$([ "$(sql "select count(*) from pg_constraint where conrelid=to_regclass('$cd_table') and contype='n' and conname in ('chk_discount_rule_created_at_required','chk_discount_rule_updated_at_required')")" = 2 ]; echo $?)"
cd_refusal "$(cd_rule '' '' '' '' '' OMIT);" 'ERROR:  23502.*column "created_at"' 'a rule without its creation moment'
cd_refusal "$(cd_rule '' '' '' '' '' 'now()' NULL);" 'ERROR:  23502.*column "updated_at"' 'a rule without its update moment'
cd_accepted "$(cd_rule)" 'a rule with both moments'

echo 'calculation_base codes'
cd_accepted "$(cd_rule '' "'ORIGINAL_VALUE'"); $(cd_rule '' "'PREVIOUS_SUBTOTAL'")" 'both ORIGINAL_VALUE and PREVIOUS_SUBTOTAL'
cd_refusal "$(cd_rule '' "'Valor original'");" chk_discount_rule_calculation_base 'the old Spanish base'
cd_refusal "$(cd_rule '' "'Subtotal posterior al descuento anterior'");" chk_discount_rule_calculation_base 'the old Spanish subtotal base'
cd_refusal "$(cd_rule '' "'original_value'");" chk_discount_rule_calculation_base 'a lower-case base'

echo 'discount_type codes and their coherence with the stored value'
cd_accepted "$(cd_rule '' '' "'PERCENTAGE'" 2500 NULL)" 'PERCENTAGE with basis points'
cd_accepted "$(cd_rule '' '' "'FIXED_AMOUNT'" NULL 70000)" 'FIXED_AMOUNT with cents'
cd_refusal "$(cd_rule '' '' "'Porcentual'" 2500 NULL);" chk_discount_rule_type 'the old word Porcentual'
cd_refusal "$(cd_rule '' '' "'Valor fijo'" NULL 70000);" chk_discount_rule_type 'the old words Valor fijo'
cd_refusal "$(cd_rule '' '' "'PERCENTAGE'" NULL 70000);" chk_discount_rule_value 'PERCENTAGE carrying cents'
cd_refusal "$(cd_rule '' '' "'FIXED_AMOUNT'" 2500 NULL);" chk_discount_rule_value 'FIXED_AMOUNT carrying basis points'
cd_refusal "$(cd_rule '' '' "'PERCENTAGE'" 2500 70000);" chk_discount_rule_value 'both values at once'

echo 'No DELETE preserved, idempotence, exact revert (with rows present), reapply, build from empty'
check 'writer and application user still have no DELETE on discount_rule' "$([ "$(sql "select has_table_privilege('$writer','$cd_table','DELETE') or has_table_privilege('$app','$cd_table','DELETE')")" = f ]; echo $?)"
cd_second="$(liquibase update 2>&1)"; printf '%s\n' "$cd_second"
check 'a second update applies zero changesets' "$(printf '%s\n' "$cd_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
liquibase rollback-count 1
cd_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$cd_base" "$cd_reverted"
check 'the revert restores columns, constraints, indexes and privileges exactly' "$([ -n "$cd_base" ] && [ "$cd_reverted" = "$cd_base" ] && [ "$(sql "select count(*) from $CONTROL")" = 39 ]; echo $?)"
check 'the revert gives the stored rows back their old words' "$([ "$(sql "select string_agg(calculation_base || '/' || discount_type, ',' order by priority) from $cd_table where discount_rule_id in ('$(aid 1501)','$(aid 1502)')")" = 'Subtotal posterior al descuento anterior/Porcentual,Valor original/Valor fijo' ]; echo $?)"
liquibase update >/dev/null
check 'the changeset reapplies to 40 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 40 ]; echo $?)"
liquibase rollback-count 999 >/dev/null
db_labels='!outbox-widening and !authorizable-reason and !additional-discount-immutable'
liquibase update >/dev/null
liquibase validate >/dev/null
check 'a full build from empty without any label filter applies exactly 40 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 40 ]; echo $?)"
