#!/usr/bin/env bash
# Sourced by db-ci.sh after account-session-cutoff-checks.sh, on the same disposable PostgreSQL instance, with every changeset that exists before the slice (counted at run time); the slice is four changesets:
# alter 046 (contact columns), table 040 (change), index 058 and grant 019 (UPDATE withdrawn). All carry the label establishment-contact-log.
# HU-COM-002 -db (docs spec 002, PROPOSED, 2026-11-12): AC-D2.11 to AC-D2.15. The contact of an association is three optional columns; every inactivation or reactivation leaves one row in
# associated_establishment_change (event, reason, actor, instant), appended and never edited. Probes are written first: red before the changesets, green after (Annex J.1).
ec_t="$SCHEMA.associated_establishment_change"
ec_sql() { sql "$1" 2>/dev/null || true; }
ec_refusal() { # SQL, text of the engine answer, description
  local answer
  answer="$(engine "$1" 2>&1 || true)"; printf '%s\n' "$answer"
  check "establishment contact and log: $3 is refused by $2" "$(printf '%s\n' "$answer" | grep -q "$2"; echo $?)"
}
ec_accepted() { # SQL, description
  local status=0
  engine "begin; $1; rollback;" >/dev/null || status=$?
  check "establishment contact and log: $2 is accepted" "$status"
}
ec_contact() { # association id, then the three contact values as SQL expressions
  echo "insert into $ae_table (association_id, tenant_id, establishment_type, commercial_name, commercial_information, association_status, created_at, updated_at, contact_email, contact_phone, contact_address) values ('$1', '$tenant', 'HOTEL', 'Hotel Andino', 'Breakfast included', 'ACTIVE', now(), now(), $2, $3, $4)"
}
ec_change() { # association id, event type, reason as an SQL expression
  echo "insert into $ec_t (change_id, tenant_id, association_id, event_type, reason, actor_id, occurred_at) values (gen_random_uuid(), '$tenant', '$1', '$2', $3, '$actor', now())"
}

echo 'establishment contact and log - base: every changeset that exists before the slice'
liquibase rollback-count 999 >/dev/null
db_labels='!establishment-contact-log'
liquibase update >/dev/null
ec_base="$(snapshot)"
ec_n0="$(sql "select count(*) from $CONTROL")"
check "the base holds every changeset except the four of the slice ($ec_n0)" "$([ "$ec_n0" -gt 0 ] && [ "$(sql "select count(*) from $CONTROL where labels ilike '%establishment-contact-log%'")" = 0 ]; echo $?)"
check 'on that base the change table does not exist' "$([ "$(sql "select to_regclass('$ec_t') is null")" = t ]; echo $?)"

echo 'establishment contact and log - probes written first: red before the changesets, green after'
db_labels='establishment-contact-log'
liquibase update >/dev/null
check 'the slice adds exactly four changesets to the control table' "$([ "$(sql "select count(*) from $CONTROL")" = "$((ec_n0 + 4))" ]; echo $?)"

echo 'the contact columns (AC-D2.11)'
ec_ae_cols='association_id uuid NO,tenant_id uuid NO,establishment_type text NO,commercial_name text NO,commercial_information text NO,association_status text NO,created_at timestamp with time zone NO,updated_at timestamp with time zone NO,contact_email text YES,contact_phone text YES,contact_address text YES'
check 'AC-D2.11 associated_establishment holds its eight columns and the three optional contact columns' "$([ "$(cols_of associated_establishment)" = "$ec_ae_cols" ]; echo $?)"
ec_accepted "$(ec_contact "$(aid 9601)" "'info@hotelandino.example'" "'+57 8 8700000'" "'Calle 1 No. 2-3'")" 'a row with the whole contact'
ec_accepted "$(ec_contact "$(aid 9602)" null "'+57 8 8700000'" null)" 'a row with only a phone'
ec_accepted "$(ae_row "'$(aid 9603)'")" 'a row with no contact, as every row that existed before the slice'
ec_refusal "$(ec_contact "$(aid 9604)" "''" null null);" chk_associated_establishment_contact_email_length 'AC-D2.11 an empty email'
ec_refusal "$(ec_contact "$(aid 9604)" "repeat('a', 255)" null null);" chk_associated_establishment_contact_email_length 'AC-D2.11 an email of 255 characters'
ec_refusal "$(ec_contact "$(aid 9604)" null "repeat('7', 31)" null);" chk_associated_establishment_contact_phone_length 'AC-D2.11 a phone of 31 characters'
ec_refusal "$(ec_contact "$(aid 9604)" null null "'   '");" chk_associated_establishment_contact_address_length 'AC-D2.11 an address of blanks'

echo 'the change table (AC-D2.12, AC-D2.13)'
ec_cols='change_id uuid NO,tenant_id uuid NO,association_id uuid NO,event_type text NO,reason text YES,actor_id uuid NO,occurred_at timestamp with time zone NO'
check 'AC-D2.12 associated_establishment_change holds its seven columns, all required but the reason' "$([ "$(cols_of associated_establishment_change)" = "$ec_cols" ]; echo $?)"
check 'AC-D2.12 no column has a DEFAULT' "$([ "$(ec_sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='associated_establishment_change' and column_default is not null")" = 0 ]; echo $?)"
ec_a="$(aid 9610)"
engine "$(ae_row "'$ec_a'")" >/dev/null || true
ec_accepted "$(ae_row "'$(aid 9611)'"); $(ec_change "$(aid 9611)" REGISTERED null)" 'a REGISTERED entry with no reason'
ec_accepted "$(ec_change "$ec_a" INACTIVATED "'Closed for works'"); $(ec_change "$ec_a" REACTIVATED "'Works finished'")" 'an inactivation and a reactivation with a reason'
ec_refusal "$(ec_change "$ec_a" INACTIVATED null);" chk_associated_establishment_change_reason 'AC-D2.13 an inactivation without a reason'
ec_refusal "$(ec_change "$ec_a" REACTIVATED "'   '");" chk_associated_establishment_change_reason 'AC-D2.13 a reactivation with a blank reason'
ec_refusal "$(ec_change "$ec_a" REACTIVATED "repeat('x', 501)");" chk_associated_establishment_change_reason 'AC-D2.13 a reason of 501 characters'
ec_refusal "$(ec_change "$ec_a" REGISTERED "'Because'");" chk_associated_establishment_change_reason 'AC-D2.13 a REGISTERED entry with a reason'
ec_refusal "$(ec_change "$ec_a" DELETED "'Because'");" chk_associated_establishment_change_event_type 'AC-D2.13 an event type outside the closed set'
ec_refusal "$(ec_change "$(aid 9699)" INACTIVATED "'Because'");" fk_associated_establishment_change_association 'AC-D2.12 an entry of an association that does not exist'
ec_refusal "insert into $ec_t (change_id, tenant_id, association_id, event_type, reason, actor_id, occurred_at) values (gen_random_uuid(), '$tenant', '$ec_a', 'INACTIVATED', 'Because', null, now());" 'column "actor_id"' 'AC-D2.12 an entry without an actor'
check 'AC-D2.12 the tenant leads an index of the change table, newest first' "$([ "$(ec_sql "select count(*) from pg_indexes where schemaname='$SCHEMA' and tablename='associated_establishment_change' and indexname='idx_associated_establishment_change_tenant_occurred' and indexdef like '%(tenant_id, occurred_at DESC)%'")" = 1 ]; echo $?)"

echo 'privileges (AC-D2.14)'
check 'AC-D2.14 the application user selects and inserts, and neither it nor the writer updates or deletes' "$([ "$(privileges_of "$ec_t")" = 'INSERT,SELECT' ] && [ "$(sql "select has_table_privilege('$writer','$ec_t','UPDATE') or has_table_privilege('$writer','$ec_t','DELETE')")" = f ]; echo $?)"
check 'AC-D2.14 the reader reads and does not write' "$([ "$(sql "select has_table_privilege('$reader','$ec_t','SELECT') and not has_table_privilege('$reader','$ec_t','INSERT')")" = t ]; echo $?)"
ec_refusal "update $ec_t set reason = 'Edited';" 'permission denied for table associated_establishment_change' 'AC-D2.14 UPDATE as the application user'
ec_refusal "delete from $ec_t;" 'permission denied for table associated_establishment_change' 'AC-D2.14 DELETE as the application user'

echo 'Idempotence, exact revert and reapply (AC-D2.15)'
ec_second="$(liquibase update 2>&1)"; printf '%s\n' "$ec_second"
check 'AC-D2.15 a second update applies zero changesets' "$(printf '%s\n' "$ec_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
sql "delete from $ec_t" >/dev/null 2>&1 || true
ec_n="$(sql "select count(*) from $CONTROL where labels ilike '%establishment-contact-log%'" 2>/dev/null || echo 0)"
liquibase rollback-count "$ec_n"
ec_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$ec_base" "$ec_reverted"
check 'AC-D2.15 the revert restores the schema exactly and leaves the base changesets' "$([ -n "$ec_base" ] && [ "$ec_reverted" = "$ec_base" ] && [ "$(sql "select count(*) from $CONTROL")" = "$ec_n0" ]; echo $?)"
db_labels='establishment-contact-log'
liquibase update >/dev/null
check 'AC-D2.15 the four changesets of the slice apply again' "$([ "$(sql "select count(*) from $CONTROL")" = "$((ec_n0 + 4))" ]; echo $?)"
