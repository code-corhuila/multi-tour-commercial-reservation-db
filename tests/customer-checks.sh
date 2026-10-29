#!/usr/bin/env bash
# Sourced by db-ci.sh after discount-rule-checks.sh, on the same disposable PostgreSQL instance.
# HU-COM-005 (-db), tasks T-01 to T-06, T-09, T-11 (issue multi-tour-docs#171).
# Stage A (label customer-tables): customer(customer_id, tenant_id, full_name, created_at) and
#        reservation_companion(reservation_companion_id, tenant_id, reservation_id, full_name).
# Stage B (every other HU-COM-005 label): the defaults of the spec section "Decisions taken by default
# (2026-10-28)": DP-D5-1 text and jsonb columns, DP-D5-2 companion document plain and unique per
# reservation, DP-D5-4 account_id, DP-D5-5 birth_date_or_age, DP-D5-6 status without CHECK, DP-D5-7 two
# sensitive tables revoked from the reader.
# RULE OF THIS SLICE: a column whose decision is still open is NOT built, and no probe judges it:
# e-mail, keyed hashes and the customer document unique (DP-D5-2, 3), terms and consents (DP-D5-7,
# DP-D5-10), outbox columns (DP-D5-8, shared with HU-COM-004), companion contact (DP-D5-9), retention
# (DP-D5-10), companion key to the reservation table (HU-COM-007).
cust_table="$SCHEMA.customer"; comp_table="$SCHEMA.reservation_companion"
cust_total=29 # 27 of HU-COM-001..003 plus the two tables of this slice

echo 'HU-COM-005 T-01 - preconditions of HU-COM-001..003 (nothing is created; the first failure ends the run)'
precondition "schema, control table, outbox and idempotency key of HU-COM-001 are present" "$([ "$(sql "select (to_regnamespace('$SCHEMA') is not null and to_regclass('$CONTROL') is not null and to_regclass('$SCHEMA.outbox_event') is not null and to_regclass('$SCHEMA.idempotency_key') is not null)")" = t ]; echo $?)"
precondition "catalog_service, associated_establishment and discount_rule of HU-COM-001..003 are present" "$([ "$(sql "select count(*) from pg_tables where schemaname = '$SCHEMA' and tablename in ('catalog_service','associated_establishment','discount_rule')")" = 3 ]; echo $?)"
precondition "both roles exist and hold no DELETE outside the two technical tables" "$([ "$(sql "select count(*) from pg_roles where rolname in ('$reader','$writer')")" = 2 ] && [ "$(sql "select count(*) from information_schema.tables t where t.table_schema = '$SCHEMA' and t.table_name not in ('idempotency_key','outbox_event') and (has_table_privilege('$writer', format('%I.%I', t.table_schema, t.table_name), 'DELETE') or has_table_privilege('$app', format('%I.%I', t.table_schema, t.table_name), 'DELETE'))")" = 0 ]; echo $?)"
precondition "HU-COM-001..003 applied exactly 27 changesets" "$([ "$(sql "select count(*) from $CONTROL")" = 27 ]; echo $?)"
cust_base="$(snapshot)"

cust_insert() { # table, columns, values
  echo "insert into $1 ($2) values ($3)"
}
cust_row() { # tenant expression, name expression
  cust_insert "$cust_table" 'customer_id, tenant_id, full_name, created_at' "gen_random_uuid(), ${1:-'$tenant'}, ${2:-'Ana Perez'}, now()"
}
comp_row() { # tenant expression, name expression
  cust_insert "$comp_table" 'reservation_companion_id, tenant_id, reservation_id, full_name' "gen_random_uuid(), ${1:-'$tenant'}, gen_random_uuid(), ${2:-'Luis Gomez'}"
}
cust_not_null_refusal() { # SQL, constraint name, table, column
  local answer
  answer="$(engine "$1" 2>&1 || true)"; printf '%s\n' "$answer"
  check "HU-COM-005 AC-D5.3 insert is refused for a null $4 (SQLSTATE 23502)" "$(printf '%s\n' "$answer" | grep -q "ERROR:  23502.*column \"$4\""; echo $?)"
  check "HU-COM-005 AC-D5.3 $2 exists in the catalog as a NOT NULL constraint" "$([ "$(sql "select count(*) from pg_constraint where conrelid = to_regclass('$3') and contype = 'n' and conname = '$2'" 2>/dev/null || true)" = 1 ]; echo $?)"
}

echo 'HU-COM-005 T-02 - probes written first: seen red before the changesets, green after'
db_labels='HU-COM-005 and customer-tables'
liquibase update
check "HU-COM-005 the two tables brought the control table to $cust_total changesets" "$([ "$(sql "select count(*) from $CONTROL")" = "$cust_total" ]; echo $?)"

# AC-D5.1
check 'AC-D5.1 customer and reservation_companion exist in the domain schema' "$([ "$(sql "select count(*) from pg_tables where schemaname = '$SCHEMA' and tablename in ('customer','reservation_companion')" 2>/dev/null || true)" = 2 ]; echo $?)"
check 'AC-D5.1 nothing of them appears in public' "$([ "$(sql "select count(*) from pg_tables where schemaname = 'public' and tablename in ('customer','reservation_companion')")" = 0 ]; echo $?)"
# AC-D5.2 (the decided part): exact columns, so that a column of an open decision fails this probe
cust_columns() { sql "select string_agg(column_name || ' ' || data_type || ' ' || is_nullable || ' ' || coalesce(column_default, '-'), ',' order by ordinal_position) from information_schema.columns where table_schema = '$SCHEMA' and table_name = '$1'" 2>/dev/null || true; }
check 'AC-D5.2 customer holds exactly the decided columns, none for an open decision' "$([ "$(cust_columns customer)" = 'customer_id uuid NO -,tenant_id uuid NO -,full_name text NO -,created_at timestamp with time zone NO -' ]; echo $?)"
check 'AC-D5.2 reservation_companion holds exactly the decided columns, none for an open decision' "$([ "$(cust_columns reservation_companion)" = 'reservation_companion_id uuid NO -,tenant_id uuid NO -,reservation_id uuid NO -,full_name text NO -' ]; echo $?)"
check 'AC-D5.2 primary keys pk_customer and pk_reservation_companion are named' "$([ "$(sql "select count(*) from pg_constraint where contype = 'p' and conname in ('pk_customer','pk_reservation_companion') and connamespace = '$SCHEMA'::regnamespace" 2>/dev/null || true)" = 2 ]; echo $?)"
check 'AC-D5.2 no CHECK, UNIQUE or foreign key exists yet: they wait for DP-D5-2, 3, 6 and HU-COM-007' "$([ "$(sql "select count(*) from pg_constraint where conrelid in (to_regclass('$cust_table'), to_regclass('$comp_table')) and contype in ('c','u','f')")" = 0 ]; echo $?)"
# AC-D5.3 (the decided part): tenant and name are mandatory, through psql as the application user
cust_not_null_refusal "$(cust_row NULL);" chk_customer_tenant_required "$cust_table" tenant_id
cust_not_null_refusal "$(cust_row "'$tenant'" NULL);" chk_customer_full_name_required "$cust_table" full_name
cust_not_null_refusal "$(comp_row NULL);" chk_reservation_companion_tenant_required "$comp_table" tenant_id
cust_not_null_refusal "$(comp_row "'$tenant'" NULL);" chk_reservation_companion_full_name_required "$comp_table" full_name
# AC-D5.5 (the decided part): the same name in two tenants is accepted and a scoped query sees one
iso_status=0
iso_answer="$(engine "begin; $(cust_row "'$tenant'" "'Same Name'"); $(cust_row "'$other_tenant'" "'Same Name'"); select count(*) as scoped from $cust_table where tenant_id = '$tenant' and full_name = 'Same Name'; rollback;" 2>&1)" || iso_status=$?
printf '%s\n' "$iso_answer"
check 'AC-D5.5 two tenants accept the same name' "$iso_status"
check 'AC-D5.5 a query scoped to tenant A returns exactly one of the two rows' "$(printf '%s\n' "$iso_answer" | grep -Eq '^ +1$'; echo $?)"
# AC-D5.9: the application user never deletes
for t in "$cust_table" "$comp_table"; do
  for r in "$writer" "$app"; do
    check "AC-D5.9 $r has no DELETE grant on ${t#$SCHEMA.}" "$([ "$(sql "select has_table_privilege('$r', '$t', 'DELETE')" 2>/dev/null || true)" = f ]; echo $?)"
  done
  del_answer="$(engine "delete from $t;" "$app" 2>&1 || true)"; printf '%s\n' "$del_answer"
  check "AC-D5.9 DELETE as the application user on ${t#$SCHEMA.} is denied by privilege" "$(printf '%s\n' "$del_answer" | grep -q "permission denied for table ${t#$SCHEMA.}"; echo $?)"
done
# AC-D5.12 / AC-D5.13: idempotent update, exact revert, reapply
cust_second="$(liquibase update 2>&1)"; printf '%s\n' "$cust_second"
check 'AC-D5.12 a second update applies zero changesets and the count is still 29' "$(printf '%s\n' "$cust_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets' && [ "$(sql "select count(*) from $CONTROL")" = "$cust_total" ]; echo $?)"
if [ "$(sql "select count(*) from $CONTROL")" = "$cust_total" ]; then
  liquibase rollback-count 2
  cust_reverted="$(snapshot)"
  printf 'HU-COM-001..003 schema MD5: %s\nAfter HU-COM-005 revert MD5: %s\n' "$cust_base" "$cust_reverted"
  check 'AC-D5.13 the revert removes both tables and leaves the schema exactly as 001-003 had it' "$([ -n "$cust_base" ] && [ "$cust_reverted" = "$cust_base" ] && [ "$(sql "select count(*) from pg_tables where schemaname = '$SCHEMA' and tablename in ('customer','reservation_companion')")" = 0 ] && [ "$(sql "select count(*) from $CONTROL")" = 27 ]; echo $?)"
  liquibase update
  check 'AC-D5.13 the slice applies again to the same 29 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = "$cust_total" ]; echo $?)"
else
  check 'AC-D5.13 the revert cannot be judged: the slice is not applied (no rollback is run, so 001-003 stay untouched)' 1
fi
# ---------------------------------------------------------------------------------------------------
# Stage B: the default decisions of 2026-10-28. Written first; red until the changesets 010 onward.
cust_stage_a="$(snapshot)"
sens_cust="$SCHEMA.customer_sensitive_data"; sens_comp="$SCHEMA.reservation_companion_sensitive_data"
comp_reservation="00000000-0000-0000-0000-0000000000c1"; comp_reservation_2="00000000-0000-0000-0000-0000000000c2"
cust_total_b=35 # the 29 of stage A plus six: two tables, two column alters, one index, one revoke
echo 'HU-COM-005 stage B - probes of the default decisions, seen red before the changesets, green after'
db_labels='HU-COM-005 and !customer-terms and !HU-WRK-007'
liquibase update
check "HU-COM-005 stage B brought the control table to $cust_total_b changesets" "$([ "$(sql "select count(*) from $CONTROL")" = "$cust_total_b" ]; echo $?)"

b_cust_row() { # tenant, name, document, birth, contact, status (SQL expressions; the defaults are valid values)
  cust_insert "$cust_table" 'customer_id, tenant_id, full_name, created_at, document_number, birth_date_or_age, contact_info, status' "gen_random_uuid(), ${1:-'$tenant'}, ${2:-'Ana Perez'}, now(), ${3:-'v1:doc'}, ${4:-'v1:birth'}, ${5:-'{}'::jsonb}, ${6:-'ACTIVE'}"
}
b_comp_row() { # tenant, reservation, document, birth
  cust_insert "$comp_table" 'reservation_companion_id, tenant_id, reservation_id, full_name, document_number, birth_date_or_age' "gen_random_uuid(), ${1:-'$tenant'}, ${2:-gen_random_uuid()}, 'Luis Gomez', ${3:-'CC123'}, ${4:-'v1:birth'}"
}
b_accepted() { # description, SQL run inside a transaction that is rolled back
  local status=0; engine "begin; $2 rollback;" >/dev/null 2>&1 || status=$?; check "$1" "$status"
}
b_refused() { # description, SQL, SQLSTATE, text the answer must carry
  local answer; answer="$(engine "begin; $2 commit;" 2>&1 || true)"; printf '%s\n' "$answer"
  check "$1" "$(printf '%s\n' "$answer" | grep -q "ERROR:  $3.*$4"; echo $?)"
}

# AC-D5.1 / AC-D5.2: four tables, exact columns, nothing for an open decision
check 'AC-D5.1 the four tables of the slice exist in the domain schema and none appears in public' "$([ "$(sql "select count(*) from pg_tables where schemaname = '$SCHEMA' and tablename in ('customer','reservation_companion','customer_sensitive_data','reservation_companion_sensitive_data')" 2>/dev/null || true)" = 4 ] && [ "$(sql "select count(*) from pg_tables where schemaname = 'public' and (tablename like '%customer%' or tablename like '%companion%')")" = 0 ]; echo $?)"
check 'AC-D5.2 customer: document and birth as text, contact jsonb, status text, nullable account_id; no e-mail, hash, terms or retention column' "$([ "$(cust_columns customer)" = 'customer_id uuid NO -,tenant_id uuid NO -,full_name text NO -,created_at timestamp with time zone NO -,document_number text NO -,birth_date_or_age text NO -,contact_info jsonb NO -,status text NO -,account_id uuid YES -' ]; echo $?)"
check 'AC-D5.2 reservation_companion: plain document and birth_date_or_age as text; no contact column (DP-D5-9)' "$([ "$(cust_columns reservation_companion)" = 'reservation_companion_id uuid NO -,tenant_id uuid NO -,reservation_id uuid NO -,full_name text NO -,document_number text NO -,birth_date_or_age text NO -' ]; echo $?)"
check 'AC-D5.2 customer_sensitive_data holds emergency_info jsonb only, keyed by the customer, with tenant' "$([ "$(cust_columns customer_sensitive_data)" = 'customer_id uuid NO -,tenant_id uuid NO -,emergency_info jsonb NO -' ]; echo $?)"
check 'AC-D5.2 reservation_companion_sensitive_data holds activity_requirements jsonb only, keyed by the companion, with tenant' "$([ "$(cust_columns reservation_companion_sensitive_data)" = 'reservation_companion_id uuid NO -,tenant_id uuid NO -,activity_requirements jsonb NO -' ]; echo $?)"
# AC-D5.3: every mandatory column is refused by its named NOT NULL
cust_not_null_refusal "$(b_cust_row "'$tenant'" "'Ana'" NULL);" chk_customer_document_number_required "$cust_table" document_number
cust_not_null_refusal "$(b_cust_row "'$tenant'" "'Ana'" "'d'" NULL);" chk_customer_birth_date_or_age_required "$cust_table" birth_date_or_age
cust_not_null_refusal "$(b_cust_row "'$tenant'" "'Ana'" "'d'" "'b'" NULL);" chk_customer_contact_info_required "$cust_table" contact_info
cust_not_null_refusal "$(b_cust_row "'$tenant'" "'Ana'" "'d'" "'b'" "'{}'::jsonb" NULL);" chk_customer_status_required "$cust_table" status
cust_not_null_refusal "$(b_comp_row "'$tenant'" "gen_random_uuid()" NULL);" chk_reservation_companion_document_number_required "$comp_table" document_number
cust_not_null_refusal "$(b_comp_row "'$tenant'" "gen_random_uuid()" "'CC1'" NULL);" chk_reservation_companion_birth_date_or_age_required "$comp_table" birth_date_or_age
# DP-D5-6 and DP-D5-4: status has no CHECK and no catalogue; account_id has no foreign key
b_accepted 'DP-D5-6 any status text is accepted: there is no CHECK or catalogue' "$(b_cust_row "'$tenant'" "'Ana'" "'d'" "'b'" "'{}'::jsonb" "'ANY'");"
check 'DP-D5-6 customer carries no CHECK and no UNIQUE (the customer document and e-mail rules are open, DP-D5-2, 3)' "$([ "$(sql "select count(*) from pg_constraint where conrelid = to_regclass('$cust_table') and contype in ('c','u')")" = 0 ]; echo $?)"
check 'DP-D5-4 account_id has no foreign key and a partial index where it is not null' "$([ "$(sql "select count(*) from pg_constraint where conrelid = to_regclass('$cust_table') and contype = 'f'")" = 0 ] && [ "$(sql "select count(*) from pg_indexes where schemaname = '$SCHEMA' and tablename = 'customer' and indexname = 'idx_customer_tenant_account_id' and indexdef like '%(tenant_id, account_id)%WHERE (account_id IS NOT NULL)'")" = 1 ]; echo $?)"
# AC-D5.4: companion document, normalized form and unique per reservation
b_refused 'AC-D5.4 a second companion with the same document in the same reservation is refused by uq_reservation_companion_reservation_document' "$(b_comp_row "'$tenant'" "'$comp_reservation'" "'CC123'"); $(b_comp_row "'$tenant'" "'$comp_reservation'" "'CC123'");" 23505 uq_reservation_companion_reservation_document
b_accepted 'AC-D5.4 the same document in another reservation is accepted' "$(b_comp_row "'$tenant'" "'$comp_reservation'" "'CC123'"); $(b_comp_row "'$tenant'" "'$comp_reservation_2'" "'CC123'");"
b_refused 'AC-D5.4 an unnormalized document (lower case or spaces) is refused by chk_reservation_companion_document_number_normalized' "$(b_comp_row "'$tenant'" "'$comp_reservation'" "' cc123'");" 23514 chk_reservation_companion_document_number_normalized
b_refused 'AC-D5.4 an empty document is refused by the same normalization check' "$(b_comp_row "'$tenant'" "'$comp_reservation'" "''");" 23514 chk_reservation_companion_document_number_normalized
# AC-D5.5: two tenants, same document, a scoped query sees one row
iso_status=0
iso_answer="$(engine "begin; $(b_cust_row "'$tenant'" "'Same'" "'v1:same'"); $(b_cust_row "'$other_tenant'" "'Same'" "'v1:same'"); select count(*) as scoped from $cust_table where tenant_id = '$tenant' and document_number = 'v1:same'; rollback;" 2>&1)" || iso_status=$?
printf '%s\n' "$iso_answer"
check 'AC-D5.5 two tenants accept the same customer document and a scoped query returns one row' "$([ "$iso_status" -eq 0 ] && printf '%s\n' "$iso_answer" | grep -Eq '^ +1$'; echo $?)"
b_accepted 'AC-D5.5 two tenants accept the same companion document, each under its own reservation' "$(b_comp_row "'$tenant'" "'$comp_reservation'" "'CC9'"); $(b_comp_row "'$other_tenant'" "'$comp_reservation_2'" "'CC9'");"
# AC-D5.7: sensitive tables revoked from the reader; the writer inserts
for t in "$sens_cust" "$sens_comp"; do
  check "AC-D5.7 the reader role has no SELECT on ${t#$SCHEMA.}" "$([ "$(sql "select has_table_privilege('$reader', '$t', 'SELECT')" 2>/dev/null || true)" = f ]; echo $?)"
  sel_answer="$(engine "select count(*) from $t;" "$reader" 2>&1 || true)"; printf '%s\n' "$sel_answer"
  check "AC-D5.7 SELECT as the reader on ${t#$SCHEMA.} is denied by privilege" "$(printf '%s\n' "$sel_answer" | grep -q "permission denied for table ${t#$SCHEMA.}"; echo $?)"
  check "AC-D5.7 the writer and the application user keep SELECT and INSERT on ${t#$SCHEMA.}" "$([ "$(sql "select has_table_privilege('$writer', '$t', 'SELECT,INSERT') and has_table_privilege('$app', '$t', 'SELECT,INSERT')" 2>/dev/null || true)" = t ]; echo $?)"
done
check 'AC-D5.7 the reader still reads the ordinary tables customer and reservation_companion' "$([ "$(sql "select has_table_privilege('$reader', '$cust_table', 'SELECT') and has_table_privilege('$reader', '$comp_table', 'SELECT')" 2>/dev/null || true)" = t ]; echo $?)"
b_accepted 'AC-D5.7 the application user inserts sensitive data for a customer and for a companion' "$(b_cust_row "'$tenant'" "'Ana'" "'v1:s'"); insert into $sens_cust (customer_id, tenant_id, emergency_info) select customer_id, tenant_id, '{}'::jsonb from $cust_table where document_number = 'v1:s'; $(b_comp_row "'$tenant'" "'$comp_reservation'" "'CS1'"); insert into $sens_comp (reservation_companion_id, tenant_id, activity_requirements) select reservation_companion_id, tenant_id, '{}'::jsonb from $comp_table where document_number = 'CS1';"
b_refused 'AC-D5.7 sensitive data for a customer that does not exist is refused by its foreign key' "insert into $sens_cust (customer_id, tenant_id, emergency_info) values (gen_random_uuid(), '$tenant', '{}'::jsonb);" 23503 fk_customer_sensitive_data_customer
b_refused 'AC-D5.7 sensitive data for a companion that does not exist is refused by its foreign key' "insert into $sens_comp (reservation_companion_id, tenant_id, activity_requirements) values (gen_random_uuid(), '$tenant', '{}'::jsonb);" 23503 fk_reservation_companion_sensitive_data_companion
# AC-D5.9: no DELETE on the two sensitive tables (the two ordinary ones were judged in stage A)
for t in "$sens_cust" "$sens_comp"; do
  for r in "$writer" "$app"; do
    check "AC-D5.9 $r has no DELETE grant on ${t#$SCHEMA.}" "$([ "$(sql "select has_table_privilege('$r', '$t', 'DELETE')" 2>/dev/null || true)" = f ]; echo $?)"
  done
  del_answer="$(engine "delete from $t;" "$app" 2>&1 || true)"; printf '%s\n' "$del_answer"
  check "AC-D5.9 DELETE as the application user on ${t#$SCHEMA.} is denied by privilege" "$(printf '%s\n' "$del_answer" | grep -q "permission denied for table ${t#$SCHEMA.}"; echo $?)"
done
# AC-D5.12 / AC-D5.13: a second update applies zero; the six changesets revert to stage A exactly
cust_b_second="$(liquibase update 2>&1)"; printf '%s\n' "$cust_b_second"
check 'AC-D5.12 a second update applies zero changesets and the count is still 35' "$(printf '%s\n' "$cust_b_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets' && [ "$(sql "select count(*) from $CONTROL")" = "$cust_total_b" ]; echo $?)"
if [ "$(sql "select count(*) from $CONTROL")" = "$cust_total_b" ]; then
  liquibase rollback-count 6
  cust_b_reverted="$(snapshot)"
  printf 'Stage A schema MD5: %s\nAfter stage B revert MD5: %s\n' "$cust_stage_a" "$cust_b_reverted"
  check 'AC-D5.13 the revert of stage B removes the sensitive tables, the columns, the index and the revoke, leaving stage A exactly' "$([ -n "$cust_stage_a" ] && [ "$cust_b_reverted" = "$cust_stage_a" ] && [ "$(sql "select count(*) from $CONTROL")" = "$cust_total" ]; echo $?)"
  liquibase update
  check 'AC-D5.13 stage B applies again to the same 35 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = "$cust_total_b" ]; echo $?)"
else
  check 'AC-D5.13 the revert of stage B cannot be judged: stage B is not applied (no rollback is run)' 1
fi
db_labels='!HU-COM-006 and !HU-WRK-007 and !HU-COM-007 and !HU-COM-008 and !HU-COM-009 and !HU-COM-010'
