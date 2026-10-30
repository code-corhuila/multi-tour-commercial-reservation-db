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


# ---- (b) reserved_service (03_tables/017, label reserved-service), reservation_fixed_discount (03_tables/018) and its UPDATE revoke
# (03_dcl/01_grants/008), both with label fixed-discount, and the keys of the companion and the additional discount
# (04_alter/013, label reservation-keys). Every changeset also carries HU-COM-007.
rs_rs="$SCHEMA.reserved_service"; rs_fd="$SCHEMA.reservation_fixed_discount"
rs_svc2="$(aid 2204)"; rs_rule1="$(aid 2205)"; rs_rule2="$(aid 2206)"
rs_service_row() { # column/value pairs (SQL literals) that replace the defaults of a valid reserved service of the kept reservation
  local -A v=([reserved_service_id]="gen_random_uuid()" [tenant_id]="'$tenant'" [reservation_id]="'$rs_keep'" [service_id]="'$rs_svc'"
    [party_size]=2 [scheduled_date]="current_date + 30" [base_rate_cents]=150000 [transport_rate_cents]=20000)
  while [ $# -ge 2 ]; do v[$1]="$2"; shift 2; done
  echo "insert into $rs_rs (reserved_service_id, tenant_id, reservation_id, service_id, party_size, scheduled_date, base_rate_cents, transport_rate_cents) values (${v[reserved_service_id]}, ${v[tenant_id]}, ${v[reservation_id]}, ${v[service_id]}, ${v[party_size]}, ${v[scheduled_date]}, ${v[base_rate_cents]}, ${v[transport_rate_cents]})"
}
rs_line_row() { # column/value pairs (SQL literals) that replace the defaults of a valid fixed discount line of the kept reservation
  local -A v=([reservation_fixed_discount_id]="gen_random_uuid()" [tenant_id]="'$tenant'" [reservation_id]="'$rs_keep'" [line_order]=1
    [discount_rule_id]="'$rs_rule1'" [rule_name]="'Season offer'" [discount_type]="'PERCENTAGE'" [discount_percentage_bp]=1000
    [discount_amount_cents]=NULL [calculation_base]="'ORIGINAL_VALUE'" [base_cents]=300000 [amount_cents]=30000 [subtotal_cents]=270000 [cap_cents]=NULL)
  while [ $# -ge 2 ]; do v[$1]="$2"; shift 2; done
  echo "insert into $rs_fd (reservation_fixed_discount_id, tenant_id, reservation_id, line_order, discount_rule_id, rule_name, discount_type, discount_percentage_bp, discount_amount_cents, calculation_base, base_cents, amount_cents, subtotal_cents, cap_cents) values (${v[reservation_fixed_discount_id]}, ${v[tenant_id]}, ${v[reservation_id]}, ${v[line_order]}, ${v[discount_rule_id]}, ${v[rule_name]}, ${v[discount_type]}, ${v[discount_percentage_bp]}, ${v[discount_amount_cents]}, ${v[calculation_base]}, ${v[base_cents]}, ${v[amount_cents]}, ${v[subtotal_cents]}, ${v[cap_cents]})"
}

echo 'HU-COM-007 reservation (b) - probes written first: red before the changesets, green after'
sql "insert into $SCHEMA.catalog_service (service_id, tenant_id, service_type, commercial_name, catalog_status, base_rate_cents, base_operational_cost_cents, configured_capacity, transport_required, high_risk, created_at, updated_at) values ('$rs_svc2', '$tenant', 'TOUR', 'Reservation probe tour 2', 'ACTIVE', 150000, 90000, 12, false, false, now(), now());
     insert into $SCHEMA.discount_rule (discount_rule_id, tenant_id, name, starts_on, ends_on, priority, calculation_base, discount_type, discount_percentage_bp, discount_amount_cents, status, covers_all_services, created_at, updated_at) values ('$rs_rule1', '$tenant', 'Season offer', current_date, current_date + 90, 1, 'ORIGINAL_VALUE', 'PERCENTAGE', 1000, NULL, 'ACTIVE', true, now(), now()), ('$rs_rule2', '$tenant', 'Fixed offer', current_date, current_date + 90, 2, 'PREVIOUS_SUBTOTAL', 'FIXED_AMOUNT', NULL, 5000, 'ACTIVE', true, now(), now())" >/dev/null 2>&1 || true
db_labels='reserved-service'
liquibase update >/dev/null
check 'reserved_service brings the control table to 57 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 57 ]; echo $?)"

echo 'oneReservedServicePerTourInAReservation (AC-D7.6)'
check 'AC-D7.6 reserved_service holds exactly the eight columns of the plan, the date and the transport fare optional' "$([ "$(cols_of reserved_service)" = 'reserved_service_id uuid NO,tenant_id uuid NO,reservation_id uuid NO,service_id uuid NO,party_size integer NO,scheduled_date date YES,base_rate_cents bigint NO,transport_rate_cents bigint YES' ]; echo $?)"
check 'AC-D7.1 nothing new appears in public, and no column has a DEFAULT' "$([ "$(sql "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p','v','m','S','f') and c.relname not like 'databasechangelog%'")" = 0 ] && [ "$(rs_sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='reserved_service' and column_default is not null")" = 0 ]; echo $?)"
for rs_pair in tenant_id:tenant reservation_id:reservation service_id:service party_size:party_size base_rate_cents:base_rate; do
  rs_col="${rs_pair%%:*}"; rs_name="chk_reserved_service_${rs_pair##*:}_required"
  rs_refusal "$(rs_service_row "$rs_col" NULL);" "ERROR:  23502.*column \"$rs_col\"" "a reserved service without $rs_col"
  check "AC-D7.6 $rs_name exists in the catalog as a NOT NULL constraint" "$([ "$(rs_sql "select count(*) from pg_constraint where conrelid='$rs_rs'::regclass and contype='n' and conname='$rs_name'")" = 1 ]; echo $?)"
done
rs_accepted "$(rs_service_row scheduled_date NULL transport_rate_cents NULL)" 'a reserved service with no date and no transport fare'
engine "$(rs_service_row);" >/dev/null || true
check 'a first reserved service of the kept reservation is stored' "$([ "$(rs_sql "select count(*) from $rs_rs where reservation_id='$rs_keep'")" = 1 ]; echo $?)"
rs_refusal "$(rs_service_row);" uq_reserved_service_reservation_service 'a second row for the same tour in the same reservation'
rs_accepted "$(rs_service_row service_id "'$rs_svc2'")" 'a row for another tour (the key stops the same tour twice only)'
rs_refusal "$(rs_service_row reservation_id "'$(aid 2299)'");" fk_reserved_service_reservation 'a service of a reservation that does not exist'
rs_refusal "$(rs_service_row service_id "'$(aid 2299)'");" fk_reserved_service_service 'a service that does not exist'
rs_refusal "$(rs_service_row party_size 0);" chk_reserved_service_party_size 'zero people'
rs_refusal "$(rs_service_row base_rate_cents -1);" chk_reserved_service_base_rate 'a negative base rate'
rs_refusal "$(rs_service_row transport_rate_cents -1);" chk_reserved_service_transport_rate 'a negative transport fare'
check 'neither the writer nor the application user holds DELETE on reserved_service' "$([ "$(sql "select has_table_privilege('$app','$rs_rs','DELETE') or has_table_privilege('$writer','$rs_rs','DELETE')")" = f ]; echo $?)"
rs_refusal "delete from $rs_rs;" 'permission denied for table reserved_service' 'DELETE as the application user on reserved_service'

echo 'salidaCapacityIsNotAlteredAndKeepsTheColumnsOf006 (AC-D7.13)'
check 'AC-D7.13 salida_capacity keeps the eight columns HU-COM-006 left it, with hora_inicio and status required' "$([ "$(cols_of salida_capacity)" = 'salida_capacity_id uuid NO,tenant_id uuid NO,salida_id uuid NO,effective_capacity integer NO,held_seats integer NO,service_id uuid NO,hora_inicio timestamp with time zone NO,status text NO' ]; echo $?)"
check 'AC-D7.13 its constraints are those of 006, and no table of this story points at it' "$([ "$(rs_sql "select string_agg(conname, ',' order by conname) from pg_constraint where conrelid='$SCHEMA.salida_capacity'::regclass and contype in ('p','u','c','f')")" = 'chk_salida_capacity_held_seats,chk_salida_capacity_status,fk_salida_capacity_service,pk_salida_capacity,uq_salida_capacity_tenant_id_salida_id' ] && [ "$(rs_sql "select count(*) from pg_constraint where contype='f' and confrelid='$SCHEMA.salida_capacity'::regclass")" = 0 ]; echo $?)"

db_labels='fixed-discount'
liquibase update >/dev/null
check 'the fixed discount lines and the UPDATE revoke bring the control table to 59 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 59 ]; echo $?)"

echo 'fixedContextLinesAreUniquePerOrderAndNeverNegative (AC-D7.7)'
rs_fd_cols='reservation_fixed_discount_id uuid NO,tenant_id uuid NO,reservation_id uuid NO,line_order integer NO,discount_rule_id uuid NO,rule_name text NO,discount_type text NO,discount_percentage_bp integer YES,discount_amount_cents bigint YES,calculation_base text NO,base_cents bigint NO,amount_cents bigint NO,subtotal_cents bigint NO,cap_cents bigint YES'
check 'AC-D7.7 the line holds the order, the rule, its copied name, type and value, the base kind, base, amount, subtotal and cap' "$([ "$(cols_of reservation_fixed_discount)" = "$rs_fd_cols" ]; echo $?)"
check 'AC-D7.7 no column has a DEFAULT, and the accumulation policy has no column (ND-06 open)' "$([ "$(rs_sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='reservation_fixed_discount' and (column_default is not null or column_name ilike '%accumulat%')")" = 0 ]; echo $?)"
for rs_pair in tenant_id:tenant reservation_id:reservation line_order:order discount_rule_id:rule rule_name:name discount_type:type calculation_base:base_kind base_cents:base amount_cents:amount subtotal_cents:subtotal; do
  rs_col="${rs_pair%%:*}"; rs_name="chk_reservation_fixed_discount_${rs_pair##*:}_required"
  rs_refusal "$(rs_line_row "$rs_col" NULL);" "ERROR:  23502.*column \"$rs_col\"" "a line without $rs_col"
  check "AC-D7.7 $rs_name exists in the catalog as a NOT NULL constraint" "$([ "$(rs_sql "select count(*) from pg_constraint where conrelid='$rs_fd'::regclass and contype='n' and conname='$rs_name'")" = 1 ]; echo $?)"
done
engine "$(rs_line_row);" >/dev/null || true
engine "$(rs_line_row line_order 2 discount_rule_id "'$rs_rule2'" rule_name "'Fixed offer'" discount_type "'FIXED_AMOUNT'" discount_percentage_bp NULL discount_amount_cents 5000 calculation_base "'PREVIOUS_SUBTOTAL'" base_cents 270000 amount_cents 5000 subtotal_cents 265000 cap_cents 8000);" >/dev/null || true
engine "$(rs_line_row line_order 3 amount_cents 0 subtotal_cents 265000 base_cents 265000);" >/dev/null || true
check 'a percentage line, a fixed amount line and a line whose amount is zero are stored: every rule in force is a line' "$([ "$(rs_sql "select count(*) from $rs_fd where reservation_id='$rs_keep'")" = 3 ] && [ "$(rs_sql "select count(*) from $rs_fd where reservation_id='$rs_keep' and amount_cents = 0")" = 1 ]; echo $?)"
rs_refusal "$(rs_line_row line_order 1);" uq_reservation_fixed_discount_reservation_order 'a second line with the same order in a reservation'
rs_accepted "$(rs_line_row reservation_id "'$(aid 2210)'" line_order 9)" 'another order of the same reservation'
rs_refusal "$(rs_line_row line_order 0);" chk_reservation_fixed_discount_order 'an order of zero'
rs_refusal "$(rs_line_row line_order 4 amount_cents -1);" chk_reservation_fixed_discount_amount 'a negative amount'
rs_refusal "$(rs_line_row line_order 4 base_cents -1);" chk_reservation_fixed_discount_base 'a negative base'
rs_refusal "$(rs_line_row line_order 4 subtotal_cents -1);" chk_reservation_fixed_discount_subtotal 'a negative subtotal'
rs_refusal "$(rs_line_row line_order 4 cap_cents 0);" chk_reservation_fixed_discount_cap 'a cap of zero'
rs_refusal "$(rs_line_row line_order 4 discount_type "'Porcentual'");" chk_reservation_fixed_discount_type 'a Spanish discount type'
rs_refusal "$(rs_line_row line_order 4 calculation_base "'Valor original'");" chk_reservation_fixed_discount_base_kind 'a Spanish calculation base'
rs_refusal "$(rs_line_row line_order 4 discount_amount_cents 100);" chk_reservation_fixed_discount_value 'a percentage line that also carries an amount'
rs_refusal "$(rs_line_row line_order 4 discount_type "'FIXED_AMOUNT'");" chk_reservation_fixed_discount_value 'a fixed amount line that carries a percentage and no amount'
rs_refusal "$(rs_line_row line_order 4 discount_percentage_bp 10001);" chk_reservation_fixed_discount_percentage 'a percentage above 10000 basis points'
rs_refusal "$(rs_line_row line_order 4 rule_name "'  '");" chk_reservation_fixed_discount_name 'a blank rule name'
rs_refusal "$(rs_line_row line_order 4 discount_rule_id "'$(aid 2299)'");" fk_reservation_fixed_discount_rule 'a line of a rule that does not exist'
rs_refusal "$(rs_line_row line_order 4 reservation_id "'$(aid 2299)'");" fk_reservation_fixed_discount_reservation 'a line of a reservation that does not exist'
rs_refusal "delete from $rs_fd;" 'permission denied for table reservation_fixed_discount' 'DELETE as the application user on the lines'

echo 'fixedDiscountLinesSurviveTheRuleAndCannotBeUpdated (AC-D7.8)'
rs_before="$(rs_sql "select md5(string_agg(t::text, '|' order by line_order)) from $rs_fd t where reservation_id='$rs_keep'")"
sql "update $SCHEMA.discount_rule set name = 'Renamed offer', status = 'INACTIVE', discount_percentage_bp = 2500, updated_at = now() where discount_rule_id = '$rs_rule1'" >/dev/null 2>&1 || true
check 'AC-D7.8 after the rule is renamed, edited and inactivated the lines are byte for byte as they were stored' "$([ -n "$rs_before" ] && [ "$(rs_sql "select md5(string_agg(t::text, '|' order by line_order)) from $rs_fd t where reservation_id='$rs_keep'")" = "$rs_before" ] && [ "$(rs_sql "select rule_name from $rs_fd where reservation_id='$rs_keep' and line_order=1")" = 'Season offer' ]; echo $?)"
rs_refusal "update $rs_fd set amount_cents = 1 where reservation_id='$rs_keep';" 'permission denied for table reservation_fixed_discount' 'an UPDATE of a line as the application user'
rs_refusal "update $rs_fd set rule_name = 'x';" 'permission denied for table reservation_fixed_discount' 'an UPDATE of every line as the application user'
check 'AC-D7.8 the writer and the application user hold SELECT and INSERT on the lines, not UPDATE or DELETE; the reader reads' "$([ "$(sql "select has_table_privilege('$writer','$rs_fd','SELECT') and has_table_privilege('$writer','$rs_fd','INSERT') and has_table_privilege('$app','$rs_fd','INSERT') and has_table_privilege('$reader','$rs_fd','SELECT')")" = t ] && [ "$(sql "select has_table_privilege('$writer','$rs_fd','UPDATE') or has_table_privilege('$app','$rs_fd','UPDATE') or has_table_privilege('$writer','$rs_fd','DELETE') or has_table_privilege('$app','$rs_fd','DELETE')")" = f ]; echo $?)"
check 'HU-COM-007 reservation: deleting a rule that a line copied from is refused by fk_reservation_fixed_discount_rule' "$(refused "delete from $SCHEMA.discount_rule where discount_rule_id = '$rs_rule1'" 'fk_reservation_fixed_discount_rule')"

db_labels='reservation-keys'
liquibase update >/dev/null
check 'the two keys bring the control table to 60 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 60 ]; echo $?)"

echo 'companionAndAdditionalDiscountRequireAnExistingReservation (AC-D7.10)'
rs_comp() { # reservation, document
  echo "insert into $SCHEMA.reservation_companion (reservation_companion_id, tenant_id, reservation_id, full_name, document_number, birth_date_or_age) values (gen_random_uuid(), '$tenant', '$1', 'Luis Gomez', '$2', 'v1:birth')"
}
rs_addl() { # reservation
  echo "insert into $SCHEMA.reservation_additional_discount (additional_discount_id, tenant_id, reservation_id, discount_percentage_bp, reason, applied_by, applied_at, previous_value_cents, amount_cents) values (gen_random_uuid(), '$tenant', '$1', 1000, 'Fidelizacion', '$actor', now(), 100000, 10000)"
}
check 'AC-D7.10 both keys exist, simple, ON DELETE RESTRICT' "$([ "$(rs_sql "select string_agg(conname || ':' || pg_get_constraintdef(oid), '|' order by conname) from pg_constraint where conname in ('fk_reservation_companion_reservation','fk_reservation_additional_discount_reservation')")" = "fk_reservation_additional_discount_reservation:FOREIGN KEY (reservation_id) REFERENCES $SCHEMA.reservation(reservation_id) ON DELETE RESTRICT|fk_reservation_companion_reservation:FOREIGN KEY (reservation_id) REFERENCES $SCHEMA.reservation(reservation_id) ON DELETE RESTRICT" ]; echo $?)"
rs_refusal "$(rs_comp "$(aid 2299)" CC900);" fk_reservation_companion_reservation 'a companion of a reservation that does not exist'
rs_refusal "$(rs_addl "$(aid 2299)");" fk_reservation_additional_discount_reservation 'an additional discount of a reservation that does not exist'
engine "$(rs_comp "$rs_keep" CC900);" >/dev/null || true
engine "$(rs_addl "$rs_keep");" >/dev/null || true
check 'a companion and an additional discount of a stored reservation are accepted' "$([ "$(rs_sql "select count(*) from $SCHEMA.reservation_companion where reservation_id='$rs_keep'")" = 1 ] && [ "$(rs_sql "select count(*) from $SCHEMA.reservation_additional_discount where reservation_id='$rs_keep'")" = 1 ]; echo $?)"
rs_refusal "$(rs_comp "$rs_keep" CC900);" uq_reservation_companion_reservation_document 'theDocumentUniquePerReservationStillHolds: the same document twice in one reservation'
rs_accepted "$(rs_comp "$(aid 2210)" CC901)" 'another document in the same reservation'
rs_refusal "$(rs_addl "$rs_keep");" uq_reservation_additional_discount_reservation 'a second additional discount in one reservation'
rs_refusal "delete from $rs_t where reservation_id = '$rs_keep';" 'permission denied for table reservation' 'deleting a referenced reservation as the application user'
check 'a reservation referenced by a companion cannot be deleted even by its owner: the key restricts' "$(refused "delete from $rs_t where reservation_id = '$rs_keep'" 'foreign key constraint')"

rs_ob="$SCHEMA.outbox_event"

# ---- (c) the second widening of outbox_event (04_alter/012, label reservation-outbox) and the four indexes (10_indexes/014 to 017,
# label reservation-indexes). Every changeset also carries HU-COM-007.
rs_ob="$SCHEMA.outbox_event"
rs_ob_cols_before="$(cols_of outbox_event)"
rs_event() { # event type, reservation id, payload (SQL literals; empty payload = NULL), actor (default the actor)
  echo "insert into $rs_ob (tenant_id, event_type, reservation_id, actor_id, occurred_at, payload) values ('$tenant', $1, $2, ${4:-'$actor'}, now(), ${3:-NULL})"
}
rs_created_payload="'{\"customerId\":\"$rs_customer_a\",\"serviceId\":\"$rs_svc\",\"projectedValueCents\":300000,\"finalValueCents\":270000,\"reservationStatus\":\"PENDING_PAYMENT\",\"paymentStatus\":\"NO_PAYMENT\"}'::jsonb"

echo 'HU-COM-007 reservation (c) - probes written first: red before the changesets, green after'
db_labels='reservation-outbox'
liquibase update >/dev/null
check 'the second widening brings the control table to 61 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 61 ]; echo $?)"

echo 'reservationCreatedFitsTheOutboxAndCarriesNoPersonalColumn (AC-D7.11)'
check 'AC-D7.11 fk_outbox_event_reservation exists, simple, ON DELETE RESTRICT' "$([ "$(rs_sql "select pg_get_constraintdef(oid) from pg_constraint where conname='fk_outbox_event_reservation' and conrelid='$rs_ob'::regclass")" = "FOREIGN KEY (reservation_id) REFERENCES $SCHEMA.reservation(reservation_id) ON DELETE RESTRICT" ]; echo $?)"
check 'AC-D7.11 the widening adds no column: the payload is the generic jsonb of piece 2, nothing personal' "$([ "$(cols_of outbox_event)" = "$rs_ob_cols_before" ] && [ "$(rs_sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='outbox_event' and (column_name ~* '(document|email|phone|contact|medical|birth|full_name)')")" = 0 ]; echo $?)"
rs_accepted "$(rs_event "'ReservationCreated'" "'$rs_keep'" "$rs_created_payload")" 'ReservationCreated with its six keys, its reservation and its actor'
rs_refusal "$(rs_event "'ReservationCreated'" "'$rs_keep'" "'{\"customerId\":\"x\"}'::jsonb");" chk_outbox_event_payload_keys_reservation_created 'ReservationCreated with a missing key'
rs_refusal "$(rs_event "'ReservationCreated'" "'$rs_keep'" "'{\"customerId\":\"x\",\"serviceId\":\"x\",\"projectedValueCents\":1,\"finalValueCents\":1,\"reservationStatus\":\"PENDING_PAYMENT\",\"paymentStatus\":\"NO_PAYMENT\",\"note\":\"x\"}'::jsonb");" chk_outbox_event_payload_keys_reservation_created 'ReservationCreated with a seventh key'
rs_refusal "$(rs_event "'ReservationCreated'" "'$rs_keep'" "'{\"customerId\":\"x\",\"serviceId\":\"x\",\"projectedValueCents\":1,\"finalValueCents\":1,\"reservationStatus\":\"PENDING_PAYMENT\",\"paymentStatus\":\"NO_PAYMENT\",\"email\":\"x\"}'::jsonb");" 'chk_outbox_event_payload_\(keys_reservation_created\|no_sensitive_keys\)' 'ReservationCreated carrying an e-mail'
rs_refusal "$(rs_event "'ReservationCreated'" "'$rs_keep'" NULL);" chk_outbox_event_payload 'ReservationCreated without payload'
rs_refusal "$(rs_event "'ReservationCreated'" "'$rs_keep'" "'[1]'::jsonb");" chk_outbox_event_payload 'ReservationCreated with a payload that is not an object'
rs_refusal "$(rs_event "'ReservationCreated'" NULL "$rs_created_payload");" chk_outbox_event_exactly_one_aggregate 'ReservationCreated without a reservation'
rs_refusal "$(rs_event "'ReservationCreated'" "'$(aid 2299)'" "$rs_created_payload");" fk_outbox_event_reservation 'ReservationCreated for a reservation that does not exist'
rs_refusal "$(rs_event "'ReservationCreated'" "'$rs_keep'" "$rs_created_payload" NULL);" chk_outbox_event_actor_required 'ReservationCreated without an actor'
for rs_type in PaymentEvidenceRegistered CapacityAllocated PaymentValidated PaymentRejected ReservationConfirmed CapacityReleased ReservationModified; do
  rs_accepted "$(rs_event "'$rs_type'" "'$rs_keep'" "'{\"reason\":\"x\"}'::jsonb")" "$rs_type with its reservation and an object payload"
  rs_refusal "$(rs_event "'$rs_type'" "'$rs_keep'" NULL);" chk_outbox_event_payload "$rs_type without payload"
done
rs_refusal "$(rs_event "'ReservationCancelled'" "'$rs_keep'" "'{}'::jsonb");" chk_outbox_event_event_type 'ReservationCancelled, which is HU-COM-011 and not widened here'
rs_refusal "insert into $rs_ob (tenant_id, event_type, customer_id, actor_id, occurred_at, payload) values ('$tenant', 'PaymentValidated', '$rs_customer_a', '$actor', now(), '{}'::jsonb);" chk_outbox_event_exactly_one_aggregate 'PaymentValidated pointing at a customer'
rs_refusal "insert into $rs_ob (tenant_id, event_type, reservation_id, previous_catalog_status, new_catalog_status, actor_id, occurred_at, payload) values ('$tenant', 'CapacityAllocated', '$rs_keep', 'ACTIVE', 'INACTIVE', '$actor', now(), '{}'::jsonb);" chk_outbox_event_exactly_one_aggregate 'a catalog status on a reservation event'
rs_accepted "insert into $rs_ob (tenant_id, event_type, service_id, previous_catalog_status, new_catalog_status, actor_id, occurred_at) values ('$tenant', 'CatalogServiceInactivated', '$rs_svc', 'ACTIVE', 'INACTIVE', '$actor', now())" 'a catalog event as before'

echo 'aRetriedCreationLeavesOneKeyOneReservationOneEvent (AC-D7.12)'
rs_tx() { # idempotency key, reservation id: key, reservation and event in one transaction
  printf '%s\n' "set role $app;" "begin;" \
    "insert into $SCHEMA.idempotency_key (key, tenant_id, resource_type, resource_id) values ('$1', '$tenant', 'reservation', '$2');" \
    "$(rs_row reservation_id "'$2'");" \
    "$(rs_event "'ReservationCreated'" "'$2'" "$rs_created_payload");" "commit;" | docker exec -i -e PGPASSWORD "$container" psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 >/dev/null 2>&1
}
rs_retry_a="$(aid 2220)"; rs_retry_b="$(aid 2221)"
rs_tx 'reservation-key-1' "$rs_retry_a" || true
rs_tx 'reservation-key-1' "$rs_retry_b" || true
check 'AC-D7.12 the same key twice leaves one key, one reservation and one ReservationCreated event; the retry rolled back whole' "$([ "$(rs_sql "select count(*) from $SCHEMA.idempotency_key where key='reservation-key-1'")" = 1 ] && [ "$(rs_sql "select count(*) from $rs_t where reservation_id in ('$rs_retry_a','$rs_retry_b')")" = 1 ] && [ "$(rs_sql "select count(*) from $rs_ob where event_type='ReservationCreated' and reservation_id in ('$rs_retry_a','$rs_retry_b')")" = 1 ]; echo $?)"

db_labels='reservation-indexes'
liquibase update >/dev/null
check 'the four indexes bring the control table to 65 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 65 ]; echo $?)"

echo 'theThreeListQueriesUseTheirIndex (AC-D7.15)'
rs_explain() { printf '%s\n' 'set enable_seqscan = off;' "explain $1;" | docker exec -i -e PGPASSWORD "$container" psql -X -U postgres -d postgres 2>&1 || true; }
check 'AC-D7.15 the four indexes exist with the columns of the plan' "$([ "$(rs_sql "select count(*) from pg_indexes where schemaname='$SCHEMA' and ((indexname='idx_reservation_tenant_status_created' and indexdef like '%(tenant_id, reservation_status, created_at DESC)%') or (indexname='idx_reservation_tenant_salida' and indexdef like '%(tenant_id, salida_id)%') or (indexname='idx_reservation_tenant_customer_created' and indexdef like '%(tenant_id, customer_id, created_at DESC)%') or (indexname='idx_outbox_event_reservation' and indexdef like '%(reservation_id)%'))")" = 4 ]; echo $?)"
sql "insert into $rs_t (reservation_id, tenant_id, customer_id, salida_id, service_id, party_size, projected_value_cents, final_value_cents, pending_balance_cents, credit_balance_cents, reservation_status, payment_status, payment_type, payment_method, created_by, created_at)
     select gen_random_uuid(), t, case when t = '$tenant' then '$rs_customer_a'::uuid else '$rs_customer_b'::uuid end, (array['$(aid 2231)','$(aid 2232)','$(aid 2233)'])[1 + n % 3]::uuid, '$rs_svc', 2, 300000, 270000, 270000, 0, 'PENDING_PAYMENT', 'NO_PAYMENT', 'DEPOSIT', 'TRANSFER', '$actor', now() - n * interval '1 minute'
     from unnest(array['$tenant', '$rs_tenant_b']::uuid[]) t, generate_series(1, 3000) n; analyze $rs_t" >/dev/null 2>&1 || true
rs_plan="$(rs_explain "select reservation_id from $rs_t where tenant_id='$tenant' and reservation_status='PENDING_PAYMENT' order by created_at desc limit 20")"; printf '%s\n' "$rs_plan"
check 'AC-D7.15 the active list of a tenant uses idx_reservation_tenant_status_created' "$(printf '%s\n' "$rs_plan" | grep -q 'idx_reservation_tenant_status_created'; echo $?)"
rs_plan="$(rs_explain "select count(*) from $rs_t where tenant_id='$tenant' and salida_id='$(aid 2231)'")"; printf '%s\n' "$rs_plan"
check 'AC-D7.15 the reservations of a departure use idx_reservation_tenant_salida' "$(printf '%s\n' "$rs_plan" | grep -q 'idx_reservation_tenant_salida'; echo $?)"
rs_plan="$(rs_explain "select reservation_id from $rs_t where tenant_id='$tenant' and customer_id='$rs_customer_a' order by created_at desc limit 20")"; printf '%s\n' "$rs_plan"
check 'AC-D7.15 the reservations of a customer use idx_reservation_tenant_customer_created' "$(printf '%s\n' "$rs_plan" | grep -q 'idx_reservation_tenant_customer_created'; echo $?)"
rs_plan="$(rs_explain "select outbox_event_id from $rs_ob where reservation_id='$rs_keep'")"; printf '%s\n' "$rs_plan"
check 'AC-D7.15 the events of a reservation use idx_outbox_event_reservation' "$(printf '%s\n' "$rs_plan" | grep -q 'idx_outbox_event_reservation'; echo $?)"
sql "delete from $rs_t where reservation_id not in ('$rs_keep','$rs_retry_a') and created_by = '$actor' and salida_id in ('$(aid 2231)','$(aid 2232)','$(aid 2233)')" >/dev/null 2>&1 || true

echo 'noDeleteGrantOnAnyTableOfTheSlice and heldSeatsIsNeverReadForUpdateOrWrittenByTheSlice (AC-D7.14, RNF-D7.4)'
check 'AC-D7.14 no DELETE on reservation, reserved_service, reservation_fixed_discount for the writer, the application user or the reader' "$([ "$(sql "select count(*) from information_schema.tables t where t.table_schema='$SCHEMA' and t.table_name in ('reservation','reserved_service','reservation_fixed_discount') and (has_table_privilege('$writer', format('%I.%I', t.table_schema, t.table_name), 'DELETE') or has_table_privilege('$app', format('%I.%I', t.table_schema, t.table_name), 'DELETE') or has_table_privilege('$reader', format('%I.%I', t.table_schema, t.table_name), 'DELETE'))")" = 0 ]; echo $?)"
check 'AC-D7.14 DELETE is held only on the two technical tables and processed_event, as before this story' "$([ "$(sql "select string_agg(t.table_name, ',' order by t.table_name) from information_schema.tables t where t.table_schema='$SCHEMA' and has_table_privilege('$app', format('%I.%I', t.table_schema, t.table_name), 'DELETE')")" = 'idempotency_key,outbox_event,processed_event' ]; echo $?)"
rs_scan_files="$(ls 01_ddl/*/*reservation*.sql 01_ddl/03_tables/017_*.sql 01_ddl/04_alter/012_*.sql 01_ddl/04_alter/013_*.sql 01_ddl/07_functions/*.sql 01_ddl/09_triggers/*.sql 03_dcl/01_grants/008_*.sql 2>/dev/null | sort -u)"
check 'RNF-D7.4 no changeset of this story mentions held_seats: the capacity row is neither read FOR UPDATE nor written' "$([ -n "$rs_scan_files" ] && ! grep -qi 'held_seats\|salida_capacity' $rs_scan_files; echo $?)"

rs_ob="$SCHEMA.outbox_event"
echo 'Idempotence, exact revert and reapply of the whole story (AC-D7.16, AC-D7.17)'
rs_second="$(liquibase update 2>&1)"; printf '%s\n' "$rs_second"
check 'a second update applies zero changesets' "$(printf '%s\n' "$rs_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
sql "delete from $rs_ob where reservation_id is not null; delete from $SCHEMA.reservation_companion where reservation_id in (select reservation_id from $rs_t); delete from $SCHEMA.reservation_additional_discount where reservation_id in (select reservation_id from $rs_t); delete from $rs_fd; delete from $rs_rs; delete from $rs_t" >/dev/null 2>&1 || true
check 'the rows of the probes are gone before the revert' "$([ "$(sql "select (select count(*) from $rs_t) + (select count(*) from $rs_rs) + (select count(*) from $rs_fd)")" = 0 ]; echo $?)"
liquibase rollback-count 12
rs_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$rs_base" "$rs_reverted"
check 'the twelve-change revert restores columns, constraints, indexes and privileges exactly' "$([ -n "$rs_base" ] && [ "$rs_reverted" = "$rs_base" ] && [ "$(sql "select count(*) from $CONTROL")" = 53 ]; echo $?)"
check 'the three tables, the function, the trigger, the keys and the widening are gone after the revert' "$([ "$(sql "select count(*) from pg_tables where schemaname='$SCHEMA' and tablename in ('reservation','reserved_service','reservation_fixed_discount')")" = 0 ] && [ "$(sql "select count(*) from pg_proc where pronamespace='$SCHEMA'::regnamespace and proname='trg_reservation_birth'")" = 0 ] && [ "$(sql "select count(*) from pg_constraint where conname in ('fk_outbox_event_reservation','fk_reservation_companion_reservation','fk_reservation_additional_discount_reservation','chk_outbox_event_payload_keys_reservation_created')")" = 0 ]; echo $?)"
db_labels=''
liquibase update >/dev/null
check 'the twelve changesets reapply to 65 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 65 ]; echo $?)"
liquibase rollback-count 999 >/dev/null
liquibase update >/dev/null
liquibase validate >/dev/null
check 'a full build from empty without any label filter applies exactly 65 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 65 ]; echo $?)"
check 'AC-D7.8 after the whole runner the writer and the application user still hold no UPDATE on the fixed discount lines' "$([ "$(sql "select has_table_privilege('$writer','$rs_fd','UPDATE') or has_table_privilege('$app','$rs_fd','UPDATE')")" = f ]; echo $?)"
check 'AC-D7.1 the whole story leaves nothing in public' "$([ "$(sql "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p','v','m','S','f') and c.relname not like 'databasechangelog%'")" = 0 ]; echo $?)"
