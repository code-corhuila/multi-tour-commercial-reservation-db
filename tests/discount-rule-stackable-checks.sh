#!/usr/bin/env bash
# Sourced by db-ci.sh after the reservation-cancellation checks, on the same disposable PostgreSQL instance.
# HU-COM-003 -db, decision of 2026-11-03 (DP-04, PROPOSED): discount_rule.stackable, boolean NOT NULL DEFAULT true.
# false means "no rule of lower priority applies after this one"; rows stored before the column read true.
# Label discount-rule-stackable on the single changeset. Probes are written first: red before it, green after (Annex J.1).
st_t="$SCHEMA.discount_rule"
st_col() { sql "select $1 from information_schema.columns where table_schema='$SCHEMA' and table_name='discount_rule' and column_name='stackable'" 2>/dev/null || true; }

echo 'HU-COM-003 stackable - base: the changesets that exist before the column, holding one rule'
liquibase rollback-count 999 >/dev/null
db_labels='!discount-rule-stackable and !HU-COM-013 and !HU-COM-012 and !HU-COM-015 and !HU-COM-016 and !HU-COM-017 and !HU-COM-019'
liquibase update >/dev/null
st_base="$(snapshot)"
check 'base holds exactly 98 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 98 ]; echo $?)"
check 'on that base discount_rule has no stackable column' "$([ "$(st_col 'count(*)')" = 0 ]; echo $?)"
engine "$(cd_rule "'$(aid 1601)'")" >/dev/null || true

echo 'HU-COM-003 stackable - probes written first: red before the changeset, green after'
db_labels='discount-rule-stackable'
liquibase update >/dev/null
check 'the column brings the control table to 99 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 99 ]; echo $?)"

echo 'the column (DP-04)'
check 'stackable is boolean NOT NULL with DEFAULT true' "$([ "$(st_col "data_type || ' ' || is_nullable || ' ' || column_default")" = 'boolean NO true' ]; echo $?)"
check 'its NOT NULL constraint is named chk_discount_rule_stackable_required' "$([ "$(sql "select count(*) from pg_constraint where conrelid=to_regclass('$st_t') and contype='n' and conname='chk_discount_rule_stackable_required'")" = 1 ]; echo $?)"
check 'a rule stored before the column reads true' "$([ "$(sql "select stackable from $st_t where discount_rule_id='$(aid 1601)'")" = t ]; echo $?)"

echo 'the rows'
engine "$(cd_rule "'$(aid 1602)'")" >/dev/null || true
check 'an insert that does not state stackable stores true' "$([ "$(sql "select stackable from $st_t where discount_rule_id='$(aid 1602)'")" = t ]; echo $?)"
engine "update $st_t set stackable = false where discount_rule_id='$(aid 1602)';" >/dev/null || true
check 'false (the chain stops after this rule) is accepted and stored' "$([ "$(sql "select stackable from $st_t where discount_rule_id='$(aid 1602)'")" = f ]; echo $?)"
cd_refusal "update $st_t set stackable = NULL where discount_rule_id='$(aid 1602)';" 'ERROR:  23502.*stackable' 'a NULL stackable'
check 'writer and application user still have no DELETE on discount_rule' "$([ "$(sql "select has_table_privilege('$writer','$st_t','DELETE') or has_table_privilege('$app','$st_t','DELETE')")" = f ]; echo $?)"

echo 'Idempotence, exact revert and reapply'
st_second="$(liquibase update 2>&1)"; printf '%s\n' "$st_second"
check 'a second update applies zero changesets' "$(printf '%s\n' "$st_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
liquibase rollback-count 1
st_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$st_base" "$st_reverted"
check 'the one-change revert restores the schema exactly and leaves 98 changesets' "$([ -n "$st_base" ] && [ "$st_reverted" = "$st_base" ] && [ "$(sql "select count(*) from $CONTROL")" = 98 ]; echo $?)"
db_labels='discount-rule-stackable'
liquibase update >/dev/null
check 'the changeset reapplies to 99 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 99 ]; echo $?)"
sql "delete from $st_t where discount_rule_id in ('$(aid 1601)','$(aid 1602)')" >/dev/null 2>&1 || true
