#!/usr/bin/env bash
# Sourced by db-ci.sh after the offer checks, on the same disposable PostgreSQL instance.
# HU-COM-007 -db (issue multi-tour-docs#173), plan D-02, D-04, D-05: the table reservation (03_tables/016, label
# reservation-table), the birth function (07_functions/001) and the birth trigger trg_reservation_birth (09_triggers/001),
# both with label reservation-table. Every changeset also carries HU-COM-007.
# Probes are written first: red before the changesets, green after (Annex J.1).
rs_t="$SCHEMA.reservation"
rs_customer_a="$(aid 2201)"; rs_customer_b="$(aid 2202)"; rs_svc="$(aid 2203)"
rs_tenant_b="00000000-0000-0000-0000-000000000002"
rs_sql() { sql "$1" 2>/dev/null || true; }
rs_refusal() { # SQL, text of the engine answer, description
  local answer
  answer="$(engine "$1" 2>&1 || true)"; printf '%s\n' "$answer"
  check "HU-COM-007 reservation: $3 is refused by $2" "$(printf '%s\n' "$answer" | grep -q "$2"; echo $?)"
}
rs_accepted() { # SQL, description
  local status=0
  engine "begin; $1; rollback;" || status=$?
  check "HU-COM-007 reservation: $2 is accepted" "$status"
}
rs_row() { # column/value pairs (SQL literals) that replace the defaults of a valid reservation
  local -A v=([reservation_id]="gen_random_uuid()" [tenant_id]="'$tenant'" [customer_id]="'$rs_customer_a'" [salida_id]="gen_random_uuid()"
    [service_id]="'$rs_svc'" [party_size]=2 [projected_value_cents]=300000 [final_value_cents]=270000 [pending_balance_cents]=270000
    [credit_balance_cents]=0 [reservation_status]="'PENDING_PAYMENT'" [payment_status]="'NO_PAYMENT'" [payment_type]="'DEPOSIT'"
    [payment_method]="'TRANSFER'" [created_by]="'$actor'" [created_at]="now()")
  while [ $# -ge 2 ]; do v[$1]="$2"; shift 2; done
  echo "insert into $rs_t (reservation_id, tenant_id, customer_id, salida_id, service_id, party_size, projected_value_cents, final_value_cents, pending_balance_cents, credit_balance_cents, reservation_status, payment_status, payment_type, payment_method, created_by, created_at) values (${v[reservation_id]}, ${v[tenant_id]}, ${v[customer_id]}, ${v[salida_id]}, ${v[service_id]}, ${v[party_size]}, ${v[projected_value_cents]}, ${v[final_value_cents]}, ${v[pending_balance_cents]}, ${v[credit_balance_cents]}, ${v[reservation_status]}, ${v[payment_status]}, ${v[payment_type]}, ${v[payment_method]}, ${v[created_by]}, ${v[created_at]})"
}
rs_seed() { # one customer per tenant (the same document in both) and one tour of the first tenant
  sql "insert into $SCHEMA.customer (customer_id, tenant_id, full_name, created_at, document_number, birth_date_or_age, contact_info, status, terms_accepted, terms_accepted_at) values ('$rs_customer_a', '$tenant', 'Reservation probe A', now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE', true, now()), ('$rs_customer_b', '$rs_tenant_b', 'Reservation probe B', now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE', true, now());
       insert into $SCHEMA.catalog_service (service_id, tenant_id, service_type, commercial_name, catalog_status, base_rate_cents, base_operational_cost_cents, configured_capacity, transport_required, high_risk, created_at, updated_at) values ('$rs_svc', '$tenant', 'TOUR', 'Reservation probe tour', 'ACTIVE', 150000, 90000, 12, false, false, now(), now())" >/dev/null 2>&1 || true
}

echo 'HU-COM-007 reservation - base: the 53 changesets before the reservation table, its function and its trigger'
liquibase rollback-count 999 >/dev/null
db_labels='!HU-COM-007'
liquibase update >/dev/null
rs_base="$(snapshot)"
check 'base holds exactly 53 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 53 ]; echo $?)"
check 'T-01 precondition: the schema, the control table, both roles, customer, catalog_service, salida_capacity, the outbox and the idempotency table exist' "$([ "$(sql "select count(*) from pg_namespace where nspname='$SCHEMA'")" = 1 ] && [ "$(sql "select count(*) from $CONTROL")" -gt 0 ] && [ "$(sql "select count(*) from pg_roles where rolname in ('$reader','$writer')")" = 2 ] && [ "$(sql "select count(*) from pg_tables where schemaname='$SCHEMA' and tablename in ('customer','catalog_service','salida_capacity','outbox_event','idempotency_key','discount_rule','reservation_companion','reservation_additional_discount')")" = 8 ]; echo $?)"
check 'on that base neither reservation, nor the birth function, nor the trigger exists' "$([ "$(sql "select to_regclass('$rs_t') is null")" = t ] && [ "$(sql "select count(*) from pg_proc where pronamespace='$SCHEMA'::regnamespace and proname='trg_reservation_birth'")" = 0 ]; echo $?)"
rs_seed

echo 'HU-COM-007 reservation - probes written first: red before the changesets, green after'
db_labels='reservation-table'
liquibase update >/dev/null
check 'the table, its function and its trigger bring the control table to 56 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 56 ]; echo $?)"

echo 'reservationColumnsMatchTheSpec (AC-D7.1, AC-D7.2)'
rs_cols='reservation_id uuid NO,tenant_id uuid NO,customer_id uuid NO,salida_id uuid NO,service_id uuid NO,party_size integer NO,projected_value_cents bigint NO,final_value_cents bigint NO,pending_balance_cents bigint NO,credit_balance_cents bigint NO,reservation_status text NO,payment_status text NO,payment_type text NO,payment_method text NO,created_by uuid NO,created_at timestamp with time zone NO'
check 'AC-D7.2 reservation holds exactly the sixteen columns of the plan, every one required' "$([ "$(cols_of reservation)" = "$rs_cols" ]; echo $?)"
check 'AC-D7.1 nothing new appears in public' "$([ "$(sql "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p','v','m','S','f') and c.relname not like 'databasechangelog%'")" = 0 ]; echo $?)"
check 'no column has a DEFAULT: the service states every value, the birth trigger requires them' "$([ "$(rs_sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='reservation' and column_default is not null")" = 0 ]; echo $?)"
check 'pk_reservation is the primary key, and every constraint of the table is named pk_, chk_ or fk_' "$([ "$(rs_sql "select count(*) from pg_constraint where conrelid='$rs_t'::regclass and contype='p' and conname='pk_reservation'")" = 1 ] && [ "$(rs_sql "select count(*) from pg_constraint where conrelid='$rs_t'::regclass and contype in ('p','u','c','f') and conname !~ '^(pk|uq|chk|fk)_'")" = 0 ]; echo $?)"
check 'salida_id has no foreign key: a cross-domain logical reference (Annex J.3.4)' "$([ "$(rs_sql "select count(*) from pg_constraint c join pg_attribute a on a.attrelid=c.conrelid and a.attnum=any(c.conkey) where c.conrelid='$rs_t'::regclass and c.contype='f' and a.attname='salida_id'")" = 0 ]; echo $?)"
check 'fk_reservation_customer and fk_reservation_service are simple keys ON DELETE RESTRICT' "$([ "$(rs_sql "select string_agg(conname || ':' || pg_get_constraintdef(oid), '|' order by conname) from pg_constraint where conrelid='$rs_t'::regclass and contype='f'")" = "fk_reservation_customer:FOREIGN KEY (customer_id) REFERENCES $SCHEMA.customer(customer_id) ON DELETE RESTRICT|fk_reservation_service:FOREIGN KEY (service_id) REFERENCES $SCHEMA.catalog_service(service_id) ON DELETE RESTRICT" ]; echo $?)"

echo 'reservationRequiredColumnsAreRefusedByName (AC-D7.3)'
for rs_pair in tenant_id:tenant customer_id:customer salida_id:salida service_id:service party_size:party_size projected_value_cents:projected_value final_value_cents:final_value pending_balance_cents:pending_balance credit_balance_cents:credit_balance reservation_status:status payment_status:payment_status payment_type:payment_type payment_method:payment_method created_by:created_by created_at:created_at; do
  rs_col="${rs_pair%%:*}"; rs_name="chk_reservation_${rs_pair##*:}_required"
  rs_refusal "$(rs_row "$rs_col" NULL);" "ERROR:  23502.*column \"$rs_col\"" "a reservation without $rs_col"
  check "AC-D7.3 $rs_name exists in the catalog as a NOT NULL constraint" "$([ "$(rs_sql "select count(*) from pg_constraint where conrelid='$rs_t'::regclass and contype='n' and conname='$rs_name'")" = 1 ]; echo $?)"
done

echo 'reservationIsBornPendingNoPaymentWithFinalNotAboveProjectedOnly (AC-D7.4)'
rs_accepted "$(rs_row)" 'a valid birth (final below projected, balance equal to final)'
rs_accepted "$(rs_row final_value_cents 300000 pending_balance_cents 300000)" 'a birth with final equal to projected (no discount)'
rs_refusal "$(rs_row reservation_status "'CONFIRMED'");" trg_reservation_birth 'a birth with status CONFIRMED'
rs_refusal "$(rs_row reservation_status "'CANCELLED'");" trg_reservation_birth 'a birth with status CANCELLED'
rs_refusal "$(rs_row payment_status "'FULLY_PAID'");" trg_reservation_birth 'a birth with situation FULLY_PAID'
rs_refusal "$(rs_row payment_status "'PARTIAL'");" trg_reservation_birth 'a birth with situation PARTIAL'
rs_refusal "$(rs_row pending_balance_cents 100);" trg_reservation_birth 'a birth with a pending balance different from the final value'
rs_refusal "$(rs_row final_value_cents 300001 pending_balance_cents 300001);" trg_reservation_birth 'a birth with a final value above the projected one'
rs_refusal "$(rs_row credit_balance_cents 5);" trg_reservation_birth 'a birth with a credit balance above zero'
check 'trg_reservation_birth is a BEFORE INSERT row trigger on reservation and nothing else (updates are free)' "$([ "$(rs_sql "select count(*) from pg_trigger where tgrelid='$rs_t'::regclass and not tgisinternal and tgname='trg_reservation_birth' and (tgtype & 1) = 1 and (tgtype & 2) = 2 and (tgtype & 4) = 4 and (tgtype & 8) = 0 and (tgtype & 16) = 0 and (tgtype & 32) = 0")" = 1 ] && [ "$(rs_sql "select count(*) from pg_trigger where tgrelid='$rs_t'::regclass and not tgisinternal")" = 1 ]; echo $?)"
check 'the birth function lives in the domain schema and reads no other table' "$([ "$(rs_sql "select count(*) from pg_proc where pronamespace='$SCHEMA'::regnamespace and proname='trg_reservation_birth' and prosrc !~* '(from|join)[[:space:]]'")" = 1 ] && [ "$(rs_sql "select count(*) from pg_proc where pronamespace='public'::regnamespace and proname like '%reservation%'")" = 0 ]; echo $?)"

echo 'valuesAreNeverNegativeAndNoPermanentLinkBetweenFinalAndProjected (AC-D7.5)'
rs_keep="$(aid 2210)"
engine "$(rs_row reservation_id "'$rs_keep'");" >/dev/null || true
check 'a valid reservation is stored by the application user' "$([ "$(rs_sql "select count(*) from $rs_t where reservation_id='$rs_keep'")" = 1 ]; echo $?)"
rs_upd() { echo "update $rs_t set $1 where reservation_id='$rs_keep'"; }
rs_refusal "$(rs_upd 'projected_value_cents = -1');" chk_reservation_projected_value 'a negative projected value'
rs_refusal "$(rs_upd 'final_value_cents = -1');" chk_reservation_final_value 'a negative final value'
rs_refusal "$(rs_upd 'pending_balance_cents = -1');" chk_reservation_pending_balance 'a negative pending balance'
rs_refusal "$(rs_upd 'credit_balance_cents = -1');" chk_reservation_credit_balance 'a negative credit balance'
rs_refusal "$(rs_row party_size 0);" chk_reservation_party_size 'zero people'
rs_refusal "$(rs_upd "reservation_status = 'Pendiente de pago'");" chk_reservation_status 'a Spanish display value as the status'
rs_refusal "$(rs_upd "payment_status = 'Pagado'");" chk_reservation_payment_status 'a payment situation outside the list'
rs_refusal "$(rs_row payment_type "'CHEQUE'");" chk_reservation_payment_type 'a payment type outside the list'
rs_refusal "$(rs_row payment_method "'CARD'");" chk_reservation_payment_method 'a payment medium outside the list'
for rs_status in PENDING_PAYMENT CONFIRMED IN_EXECUTION COMPLETED CANCELLED; do
  rs_accepted "$(rs_upd "reservation_status = '$rs_status'")" "a later status $rs_status (the trigger fires on insert only)"
done
for rs_situation in NO_PAYMENT PARTIAL DEPOSIT_RECEIVED BALANCE_PENDING FULLY_PAID; do
  rs_accepted "$(rs_upd "payment_status = '$rs_situation'")" "a later situation $rs_situation"
done
rs_accepted "$(rs_row payment_type "'FULL_PAYMENT'" payment_method "'CASH'")" 'FULL_PAYMENT paid in CASH'
rs_accepted "$(rs_upd 'final_value_cents = 400000')" 'a later final value above the projected one (a modification may raise it)'
rs_accepted "$(rs_upd 'pending_balance_cents = 0, credit_balance_cents = 10')" 'a later zero pending balance with a positive credit'

echo 'two tenants (AC-D7.9)'
rs_accepted "$(rs_row tenant_id "'$tenant'" customer_id "'$rs_customer_a'");" 'a reservation of tenant A for its customer'
engine "$(rs_row tenant_id "'$rs_tenant_b'" customer_id "'$rs_customer_b'");" >/dev/null || true
check 'sameDocumentAndEmailInTwoTenantsAreAccepted: both tenants hold a customer with the same document and each stores its reservation' "$([ "$(rs_sql "select count(*) from $SCHEMA.customer where document_number='enc:v1:x'")" = 2 ] && [ "$(rs_sql "select count(*) from $rs_t where tenant_id in ('$tenant','$rs_tenant_b')")" = 2 ]; echo $?)"
check 'a query scoped to tenant A returns no row of tenant B' "$([ "$(rs_sql "select count(*) from $rs_t where tenant_id='$tenant' and customer_id='$rs_customer_b'")" = 0 ] && [ "$(rs_sql "select count(distinct tenant_id) from $rs_t where tenant_id='$tenant'")" = 1 ]; echo $?)"
rs_refusal "$(rs_row customer_id "'$(aid 2299)'");" fk_reservation_customer 'a reservation of a customer that does not exist'
rs_refusal "$(rs_row service_id "'$(aid 2299)'");" fk_reservation_service 'a reservation of a service that does not exist'
check 'DP-D7-4 default: the customer key is simple, so the engine does not compare tenants; the -api load and this scoped probe do' "$([ "$(rs_sql "select count(*) from pg_constraint where conrelid='$rs_t'::regclass and conname='fk_reservation_customer' and array_length(conkey,1)=1")" = 1 ]; echo $?)"

echo 'no DELETE for the application (AC-D7.14)'
check 'neither the writer nor the application user holds DELETE on reservation, the reader does not either' "$([ "$(sql "select has_table_privilege('$app','$rs_t','DELETE') or has_table_privilege('$writer','$rs_t','DELETE') or has_table_privilege('$reader','$rs_t','DELETE')")" = f ] && [ "$(sql "select has_table_privilege('$reader','$rs_t','SELECT')")" = t ]; echo $?)"
rs_refusal "delete from $rs_t;" 'permission denied for table reservation' 'DELETE as the application user on reservation'

echo 'Idempotence, exact revert and reapply of the table, the function and the trigger (AC-D7.16, AC-D7.17)'
rs_second="$(liquibase update 2>&1)"; printf '%s\n' "$rs_second"
check 'a second update applies zero changesets' "$(printf '%s\n' "$rs_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
sql "delete from $rs_t" >/dev/null 2>&1 || true
liquibase rollback-count 3
rs_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$rs_base" "$rs_reverted"
check 'the three-change revert restores columns, constraints, indexes and privileges exactly' "$([ -n "$rs_base" ] && [ "$rs_reverted" = "$rs_base" ] && [ "$(sql "select count(*) from $CONTROL")" = 53 ]; echo $?)"
check 'the table, the function and the trigger are gone after the revert' "$([ "$(sql "select to_regclass('$rs_t') is null")" = t ] && [ "$(sql "select count(*) from pg_proc where pronamespace='$SCHEMA'::regnamespace and proname='trg_reservation_birth'")" = 0 ]; echo $?)"
db_labels=''
liquibase update >/dev/null
check 'the three changesets reapply to 56 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 56 ]; echo $?)"
liquibase rollback-count 999 >/dev/null
liquibase update >/dev/null
liquibase validate >/dev/null
check 'a full build from empty without any label filter applies exactly 56 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 56 ]; echo $?)"
