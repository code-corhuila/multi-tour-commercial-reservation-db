#!/usr/bin/env bash
# Sourced by db-ci.sh after the digital-channel checks, on the same disposable PostgreSQL instance.
# HU-COM-009 -db (issue multi-tour-docs#175), plan D-02 to D-13. Stage (a): payment_attempt (03_tables/019) and payment_proof_file
# (03_tables/020), the revokes on the proof (03_dcl/01_grants/009) and the attempt index (10_indexes/020), all with label
# payment-attempt-proof. Every changeset also carries HU-COM-009. The helpers rs_row, rs_refusal and rs_accepted come from
# reservation-checks.sh. Probes are written first: red before the changesets, green after (Annex J.1).
pa_att="$SCHEMA.payment_attempt"; pa_proof="$SCHEMA.payment_proof_file"
pa_tenant_b="00000000-0000-0000-0000-000000000002"
pa_cust="$(aid 2501)"; pa_cust_b="$(aid 2502)"; pa_svc="$(aid 2503)"; pa_res="$(aid 2510)"; pa_res_b="$(aid 2511)"
pa_hash="$(printf 'a%.0s' $(seq 1 64))"
pa_sql() { sql "$1" 2>/dev/null || true; }
pa_attempt() { # column/value pairs (SQL literals) that replace the defaults of a valid transfer attempt
  local -A v=([payment_attempt_id]="gen_random_uuid()" [tenant_id]="'$tenant'" [reservation_id]="'$pa_res'" [payment_method]="'TRANSFER'"
    [received_amount_cents]=100000 [validation_status]="'IN_VALIDATION'" [payment_status_snapshot]="'NO_PAYMENT'" [registered_by]="'$actor'" [registered_at]="now()")
  while [ $# -ge 2 ]; do v[$1]="$2"; shift 2; done
  echo "insert into $pa_att (payment_attempt_id, tenant_id, reservation_id, payment_method, received_amount_cents, validation_status, payment_status_snapshot, registered_by, registered_at) values (${v[payment_attempt_id]}, ${v[tenant_id]}, ${v[reservation_id]}, ${v[payment_method]}, ${v[received_amount_cents]}, ${v[validation_status]}, ${v[payment_status_snapshot]}, ${v[registered_by]}, ${v[registered_at]})"
}
pa_proof_row() { # attempt id, then column/value pairs (SQL literals) that replace the defaults of a valid proof
  local att="$1"; shift
  local -A v=([payment_proof_file_id]="gen_random_uuid()" [tenant_id]="'$tenant'" [content]="'\\x616263'::bytea" [content_type]="'application/pdf'" [size_bytes]=3 [sha256]="'$pa_hash'")
  while [ $# -ge 2 ]; do v[$1]="$2"; shift 2; done
  echo "insert into $pa_proof (payment_proof_file_id, tenant_id, payment_attempt_id, content, content_type, size_bytes, sha256) values (${v[payment_proof_file_id]}, ${v[tenant_id]}, '$att', ${v[content]}, ${v[content_type]}, ${v[size_bytes]}, ${v[sha256]})"
}
pa_role_refusal() { # SQL, role, text of the engine answer, description
  local answer
  answer="$(engine "$1" "$2" 2>&1 || true)"; printf '%s\n' "$answer"
  check "HU-COM-009 payment: $4 is refused by $3" "$(printf '%s\n' "$answer" | grep -q "$3"; echo $?)"
}

echo 'HU-COM-009 payment - base: the 67 changesets of HU-COM-001 to HU-COM-008'
liquibase rollback-count 999 >/dev/null
db_labels='!HU-COM-009'
liquibase update >/dev/null
pa_base="$(snapshot)"
check 'base holds exactly 67 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 67 ]; echo $?)"
check 'T-01 precondition: the schema, the control table, both roles, reservation, catalog_service, salida_capacity and the outbox exist' "$([ "$(sql "select count(*) from pg_namespace where nspname='$SCHEMA'")" = 1 ] && [ "$(sql "select count(*) from pg_roles where rolname in ('$reader','$writer')")" = 2 ] && [ "$(sql "select count(*) from pg_tables where schemaname='$SCHEMA' and tablename in ('reservation','catalog_service','salida_capacity','outbox_event','customer')")" = 5 ]; echo $?)"
check 'on that base neither payment_attempt nor payment_proof_file exists' "$([ "$(sql "select to_regclass('$pa_att') is null and to_regclass('$pa_proof') is null")" = t ]; echo $?)"
rs_seed
sql "insert into $SCHEMA.customer (customer_id, tenant_id, full_name, created_at, document_number, birth_date_or_age, contact_info, status, terms_accepted, terms_accepted_at) values ('$pa_cust', '$tenant', 'Payment probe A', now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE', true, now()), ('$pa_cust_b', '$pa_tenant_b', 'Payment probe B', now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE', true, now());
     insert into $SCHEMA.catalog_service (service_id, tenant_id, service_type, commercial_name, catalog_status, base_rate_cents, base_operational_cost_cents, configured_capacity, transport_required, high_risk, created_at, updated_at) values ('$pa_svc', '$tenant', 'TOUR', 'Payment probe tour', 'ACTIVE', 150000, 90000, 12, false, false, now(), now())" >/dev/null 2>&1 || true
engine "$(rs_row reservation_id "'$pa_res'" customer_id "'$pa_cust'" service_id "'$pa_svc'"); $(rs_row reservation_id "'$pa_res_b'" tenant_id "'$pa_tenant_b'" customer_id "'$pa_cust_b'" service_id "'$pa_svc'");" >/dev/null || true
check 'the probe reservations of two tenants exist' "$([ "$(sql "select count(*) from $SCHEMA.reservation where reservation_id in ('$pa_res','$pa_res_b')")" = 2 ]; echo $?)"

echo 'HU-COM-009 payment (a) - probes written first: red before the changesets, green after'
db_labels='payment-attempt-proof'
liquibase update >/dev/null
check 'attempt, proof, revokes and attempt index bring the control table to 71 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 71 ]; echo $?)"

echo 'paymentAttemptHoldsTheRegistrationColumns (AC-D9.1, AC-D9.2)'
pa_cols='payment_attempt_id uuid NO,tenant_id uuid NO,reservation_id uuid NO,payment_method text NO,received_amount_cents bigint NO,validation_status text YES,payment_status_snapshot text NO,registered_by uuid NO,registered_at timestamp with time zone NO'
check 'AC-D9.2 payment_attempt holds exactly the nine registration columns of the plan' "$([ "$(cols_of payment_attempt)" = "$pa_cols" ]; echo $?)"
check 'AC-D9.1 nothing new appears in public' "$([ "$(sql "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p','v','m','S','f') and c.relname not like 'databasechangelog%'")" = 0 ]; echo $?)"
check 'every constraint of the two tables is named pk_, uq_, chk_ or fk_' "$([ "$(pa_sql "select count(*) from pg_constraint where conrelid in ('$pa_att'::regclass, '$pa_proof'::regclass) and contype in ('p','u','c','f') and conname !~ '^(pk|uq|chk|fk)_'")" = 0 ]; echo $?)"

echo 'anAttemptWithoutRequiredValuesIsRefusedByName (AC-D9.3)'
for pa_pair in tenant_id:tenant reservation_id:reservation payment_method:method received_amount_cents:received_amount payment_status_snapshot:payment_status_snapshot registered_by:registered_by registered_at:registered_at; do
  pa_col="${pa_pair%%:*}"; pa_name="chk_payment_attempt_${pa_pair##*:}_required"
  rs_refusal "$(pa_attempt "$pa_col" NULL);" "ERROR:  23502.*column \"$pa_col\"" "an attempt without $pa_col"
  check "AC-D9.3 $pa_name exists in the catalog as a NOT NULL constraint" "$([ "$(pa_sql "select count(*) from pg_constraint where conrelid='$pa_att'::regclass and contype='n' and conname='$pa_name'")" = 1 ]; echo $?)"
done
rs_refusal "$(pa_attempt received_amount_cents 0);" chk_payment_attempt_amount_positive 'an attempt of zero'
rs_refusal "$(pa_attempt received_amount_cents -500);" chk_payment_attempt_amount_positive 'a negative amount'
rs_refusal "$(pa_attempt payment_method "'CARD'");" chk_payment_attempt_method 'a method outside transfer and cash'
rs_refusal "$(pa_attempt reservation_id "'$(aid 2599)'");" fk_payment_attempt_reservation 'an attempt for a reservation that does not exist'

echo 'aTransferCarriesAValidationStatusAndCashCarriesNone (AC-D9.4)'
rs_refusal "$(pa_attempt validation_status NULL);" chk_payment_attempt_status_matches_method 'a transfer without validation status'
rs_refusal "$(pa_attempt payment_method "'CASH'" validation_status "'APPROVED'");" chk_payment_attempt_status_matches_method 'cash with a validation status'
rs_refusal "$(pa_attempt validation_status "'En validación'");" chk_payment_attempt_status_matches_method 'a Spanish display value as the status'
rs_refusal "$(pa_attempt payment_status_snapshot "'Pagado'");" chk_payment_attempt_payment_status_snapshot 'a snapshot outside the five situation codes'
for pa_status in IN_VALIDATION APPROVED REJECTED; do rs_accepted "$(pa_attempt validation_status "'$pa_status'")" "a transfer $pa_status"; done
rs_accepted "$(pa_attempt payment_method "'CASH'" validation_status NULL)" 'cash with no validation status'
for pa_snap in NO_PAYMENT PARTIAL DEPOSIT_RECEIVED BALANCE_PENDING FULLY_PAID; do rs_accepted "$(pa_attempt payment_status_snapshot "'$pa_snap'")" "the snapshot $pa_snap"; done

echo 'aProofIsOnePerAttemptAndItsRowTellsTheTruthAboutTheBytes (AC-D9.6)'
pa_att_1="$(aid 2520)"; pa_att_2="$(aid 2521)"
engine "$(pa_attempt payment_attempt_id "'$pa_att_1'"); $(pa_attempt payment_attempt_id "'$pa_att_2'" payment_method "'CASH'" validation_status NULL);" >/dev/null || true
check 'two attempts of the first tenant are stored by the application user' "$([ "$(pa_sql "select count(*) from $pa_att where payment_attempt_id in ('$pa_att_1','$pa_att_2')")" = 2 ]; echo $?)"
pa_cols_p='payment_proof_file_id uuid NO,tenant_id uuid NO,payment_attempt_id uuid NO,content bytea NO,content_type text NO,size_bytes integer NO,sha256 text NO'
check 'AC-D9.6 payment_proof_file holds exactly the seven columns of the plan and no creation time (DP-D9-9)' "$([ "$(cols_of payment_proof_file)" = "$pa_cols_p" ]; echo $?)"
check 'AC-D9.6 uq_payment_proof_file_payment_attempt is the unique key of the one-to-one and the foreign key restricts' "$([ "$(pa_sql "select count(*) from pg_constraint where conrelid='$pa_proof'::regclass and ((conname='uq_payment_proof_file_payment_attempt' and contype='u') or (conname='fk_payment_proof_file_payment_attempt' and contype='f' and pg_get_constraintdef(oid) like '%ON DELETE RESTRICT'))")" = 2 ]; echo $?)"
rs_refusal "$(pa_proof_row "$pa_att_1" content_type "'image/gif'");" chk_payment_proof_file_content_type 'a type outside pdf, jpeg and png'
rs_refusal "$(pa_proof_row "$pa_att_1" size_bytes 4);" chk_payment_proof_file_size 'a size that differs from the content length'
rs_refusal "$(pa_proof_row "$pa_att_1" size_bytes 0 content "''::bytea");" chk_payment_proof_file_size 'a size of zero'
rs_refusal "$(pa_proof_row "$pa_att_1" size_bytes 5242881 content "decode(repeat('00', 5242881), 'hex')");" chk_payment_proof_file_size 'a file of 5 242 881 bytes'
rs_refusal "$(pa_proof_row "$pa_att_1" sha256 "'abc'");" chk_payment_proof_file_sha256 'a short hash'
rs_refusal "$(pa_proof_row "$pa_att_1" sha256 "'$(printf 'A%.0s' $(seq 1 64))'");" chk_payment_proof_file_sha256 'a hash in capital letters'
rs_refusal "$(pa_proof_row "$(aid 2599)");" fk_payment_proof_file_payment_attempt 'a proof of an attempt that does not exist'
for pa_type in application/pdf image/jpeg image/png; do rs_accepted "$(pa_proof_row "$pa_att_1" content_type "'$pa_type'")" "a proof of type $pa_type"; done
rs_accepted "$(pa_proof_row "$pa_att_1" size_bytes 5242880 content "decode(repeat('00', 5242880), 'hex')")" 'a file of exactly 5 242 880 bytes'
engine "$(pa_proof_row "$pa_att_1");" >/dev/null || true
rs_refusal "$(pa_proof_row "$pa_att_1");" uq_payment_proof_file_payment_attempt 'a second proof for one attempt'
check 'AC-D9.6 exactly one proof is stored for the attempt' "$([ "$(pa_sql "select count(*) from $pa_proof where payment_attempt_id='$pa_att_1'")" = 1 ]; echo $?)"

echo 'theReaderRoleCannotReadTheProofTable and noRowOfTheSliceCanBeDeleted (AC-D9.5, AC-D9.14)'
pa_role_refusal "select content from $pa_proof;" "$reader" 'permission denied for table payment_proof_file' 'the reader selecting the proof'
check 'AC-D9.5 the reader still reads the attempt table, and the writer reads and inserts the proof' "$([ "$(sql "select has_table_privilege('$reader','$pa_att','SELECT') and has_table_privilege('$writer','$pa_proof','SELECT') and has_table_privilege('$writer','$pa_proof','INSERT') and not has_table_privilege('$reader','$pa_proof','SELECT')")" = t ]; echo $?)"
rs_refusal "update $pa_proof set content_type = 'image/png';" 'permission denied for table payment_proof_file' 'UPDATE of a proof by the application user'
check 'AC-D9.5 the writer and the application user hold no UPDATE on the proof' "$([ "$(sql "select has_table_privilege('$writer','$pa_proof','UPDATE') or has_table_privilege('$app','$pa_proof','UPDATE')")" = f ]; echo $?)"
rs_refusal "delete from $pa_proof;" 'permission denied for table payment_proof_file' 'DELETE of a proof by the application user'
rs_refusal "delete from $pa_att;" 'permission denied for table payment_attempt' 'DELETE of an attempt by the application user'
check 'AC-D9.14 no DELETE on the two tables for the writer, the application user or the reader' "$([ "$(sql "select count(*) from information_schema.tables t where t.table_schema='$SCHEMA' and t.table_name in ('payment_attempt','payment_proof_file') and (has_table_privilege('$writer', format('%I.%I', t.table_schema, t.table_name), 'DELETE') or has_table_privilege('$app', format('%I.%I', t.table_schema, t.table_name), 'DELETE') or has_table_privilege('$reader', format('%I.%I', t.table_schema, t.table_name), 'DELETE'))")" = 0 ]; echo $?)"

echo 'twoTenantsHoldTheSameDataAndNoneSeesTheOther (AC-D9.7)'
engine "$(pa_attempt tenant_id "'$pa_tenant_b'" reservation_id "'$pa_res_b'");" >/dev/null || true
check 'AC-D9.7 both tenants stored an attempt with the same values' "$([ "$(pa_sql "select count(distinct tenant_id) from $pa_att where received_amount_cents=100000 and validation_status='IN_VALIDATION'")" = 2 ]; echo $?)"
check 'AC-D9.7 a query scoped to tenant A never returns a row of tenant B' "$([ "$(pa_sql "select count(*) from $pa_att where tenant_id='$tenant' and reservation_id='$pa_res_b'")" = 0 ] && [ "$(pa_sql "select count(*) from $pa_proof where tenant_id='$pa_tenant_b'")" = 0 ]; echo $?)"

echo 'theAttemptsOfAReservationUseTheirIndex (AC-D9.16)'
pa_explain() { printf '%s\n' 'set enable_seqscan = off;' "explain $1;" | docker exec -i -e PGPASSWORD "$container" psql -X -U postgres -d postgres 2>&1 || true; }
sql "insert into $pa_att (payment_attempt_id, tenant_id, reservation_id, payment_method, received_amount_cents, validation_status, payment_status_snapshot, registered_by, registered_at)
     select gen_random_uuid(), '$tenant', '$pa_res', 'TRANSFER', 1000, 'IN_VALIDATION', 'NO_PAYMENT', '$actor', now() - n * interval '1 minute' from generate_series(1, 300) n; analyze $pa_att" >/dev/null 2>&1 || true
pa_plan="$(pa_explain "select payment_attempt_id from $pa_att where tenant_id='$tenant' and reservation_id='$pa_res' order by registered_at desc")"; printf '%s\n' "$pa_plan"
check 'AC-D9.16 idx_payment_attempt_tenant_reservation_registered_at exists on (tenant_id, reservation_id, registered_at DESC)' "$([ "$(pa_sql "select count(*) from pg_indexes where schemaname='$SCHEMA' and indexname='idx_payment_attempt_tenant_reservation_registered_at' and indexdef like '%(tenant_id, reservation_id, registered_at DESC)%'")" = 1 ]; echo $?)"
check 'AC-D9.16 the attempts of a reservation, newest first, use that index' "$(printf '%s\n' "$pa_plan" | grep -q 'idx_payment_attempt_tenant_reservation_registered_at'; echo $?)"

echo 'Idempotence, exact revert and reapply of stage (a) (AC-D9.17, AC-D9.18)'
pa_second="$(liquibase update 2>&1)"; printf '%s\n' "$pa_second"
check 'AC-D9.17 a second update applies zero changesets' "$(printf '%s\n' "$pa_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
sql "delete from $SCHEMA.outbox_event where reservation_id in ('$pa_res','$pa_res_b'); delete from $pa_proof; delete from $pa_att; delete from $SCHEMA.reservation where reservation_id in ('$pa_res','$pa_res_b')" >/dev/null 2>&1 || true
check 'the rows of the probes are gone before the revert' "$([ "$(sql "select (select count(*) from $pa_att) + (select count(*) from $pa_proof)")" = 0 ]; echo $?)"
liquibase rollback-count 4
pa_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$pa_base" "$pa_reverted"
check 'AC-D9.18 the four-change revert restores columns, constraints, indexes and privileges exactly' "$([ -n "$pa_base" ] && [ "$pa_reverted" = "$pa_base" ] && [ "$(sql "select count(*) from $CONTROL")" = 67 ]; echo $?)"
check 'the two tables are gone after the revert' "$([ "$(sql "select to_regclass('$pa_att') is null and to_regclass('$pa_proof') is null")" = t ]; echo $?)"
db_labels=''
liquibase update >/dev/null
liquibase rollback-count 999 >/dev/null
liquibase update >/dev/null
liquibase validate >/dev/null
check 'a full build from empty without any label filter applies exactly 71 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 71 ]; echo $?)"
