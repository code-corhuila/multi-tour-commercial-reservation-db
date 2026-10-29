#!/usr/bin/env bash
# Sourced by db-ci.sh after the reservation checks, on the same disposable PostgreSQL instance.
# HU-COM-008 -db (issue multi-tour-docs#174), plan D-02, D-03, D-06: the story adds no table. It replaces the non-unique
# idx_customer_tenant_account_id (10_indexes/009) by the partial unique uq_customer_tenant_id_account_id (10_indexes/018, label
# customer-account-unique) and drops the old index (10_indexes/019, same label). Every changeset also carries HU-COM-008.
# The other criteria are probes over the objects of 001, 005 and 007 (plan D-06). Probes are written first: red before the
# changesets, green after (Annex J.1). The helpers rs_row, rs_refusal and rs_accepted come from reservation-checks.sh.
rd_cust="$SCHEMA.customer"; rd_acc_a="$(aid 2410)"; rd_acc_b="$(aid 2411)"
rd_cust_a="$(aid 2421)"; rd_cust_b="$(aid 2422)"; rd_cust_c="$(aid 2423)"; rd_cust_d="$(aid 2424)"; rd_cust_e="$(aid 2425)"
rd_tenant_b="00000000-0000-0000-0000-000000000002"; rd_sal="$(aid 2430)"; rd_svc="$(aid 2431)"
rd_sql() { sql "$1" 2>/dev/null || true; }
rd_customer() { # customer id, tenant, account id (SQL literal or NULL)
  echo "insert into $rd_cust (customer_id, tenant_id, full_name, created_at, document_number, birth_date_or_age, contact_info, status, terms_accepted, terms_accepted_at, account_id) values ('$1', '$2', 'Digital probe $1', now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE', true, now(), $3)"
}
rd_reservation() { # reservation id, customer id, salida id (default rd_sal), tenant (default tenant), service (default rd_svc)
  rs_row reservation_id "'$1'" customer_id "'$2'" salida_id "'${3:-$rd_sal}'" tenant_id "'${4:-$tenant}'" service_id "'${5:-$rd_svc}'"
}

echo 'HU-COM-008 reserve digital - base: the 65 changesets of HU-COM-001 to HU-COM-007'
liquibase rollback-count 999 >/dev/null
db_labels='!HU-COM-008'
liquibase update >/dev/null
rd_base="$(snapshot)"
check 'base holds exactly 65 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 65 ]; echo $?)"
check 'T-01 precondition: customer has account_id, reservation exists, idempotency_key and salida_capacity exist' "$([ "$(rd_sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='customer' and column_name='account_id'")" = 1 ] && [ "$(rd_sql "select count(*) from pg_tables where schemaname='$SCHEMA' and tablename in ('reservation','idempotency_key','salida_capacity','outbox_event')")" = 4 ]; echo $?)"
check 'on that base the old non-unique index is there and the unique one is not' "$([ "$(rd_sql "select count(*) from pg_indexes where schemaname='$SCHEMA' and indexname='idx_customer_tenant_account_id'")" = 1 ] && [ "$(rd_sql "select count(*) from pg_indexes where schemaname='$SCHEMA' and indexname='uq_customer_tenant_id_account_id'")" = 0 ]; echo $?)"
sql "insert into $SCHEMA.catalog_service (service_id, tenant_id, service_type, commercial_name, catalog_status, base_rate_cents, base_operational_cost_cents, configured_capacity, transport_required, high_risk, created_at, updated_at) values ('$rd_svc', '$tenant', 'TOUR', 'Digital probe tour', 'ACTIVE', 150000, 90000, 12, false, false, now(), now());
     insert into $SCHEMA.salida_capacity (salida_capacity_id, tenant_id, salida_id, service_id, effective_capacity, held_seats, hora_inicio, status) values ('$(aid 2432)', '$tenant', '$rd_sal', '$rd_svc', 10, 3, now() + interval '30 days', 'SCHEDULED')" >/dev/null 2>&1 || true
check 'the probe departure holds 3 of 10 seats before the story' "$([ "$(rd_sql "select held_seats from $SCHEMA.salida_capacity where salida_id='$rd_sal'")" = 3 ]; echo $?)"

echo 'HU-COM-008 reserve digital - probes written first: red before the changesets, green after'
db_labels='customer-account-unique'
liquibase update >/dev/null
check 'the unique index and the drop of the old one bring the control table to 67 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 67 ]; echo $?)"

echo 'oneAccountIsOneCustomerPerTenant (AC-D8.2)'
rs_accepted "$(rd_customer "$rd_cust_a" "$tenant" "'$rd_acc_a'")" 'the first customer of an account in tenant A'
engine "$(rd_customer "$rd_cust_a" "$tenant" "'$rd_acc_a'");" >/dev/null || true
rs_refusal "$(rd_customer "$rd_cust_b" "$tenant" "'$rd_acc_a'");" uq_customer_tenant_id_account_id 'a second customer with the same account in the same tenant'
engine "$(rd_customer "$rd_cust_c" "$rd_tenant_b" "'$rd_acc_a'");" >/dev/null || true
check 'AC-D8.2 the same account value in another tenant is accepted' "$([ "$(rd_sql "select count(*) from $rd_cust where account_id='$rd_acc_a'")" = 2 ]; echo $?)"
engine "$(rd_customer "$rd_cust_d" "$tenant" NULL); $(rd_customer "$rd_cust_e" "$tenant" NULL);" >/dev/null || true
check 'AC-D8.2 two customers without account in one tenant are accepted (registered by an internal user)' "$([ "$(rd_sql "select count(*) from $rd_cust where tenant_id='$tenant' and account_id is null and customer_id in ('$rd_cust_d','$rd_cust_e')")" = 2 ]; echo $?)"
check 'AC-D8.2 uq_customer_tenant_id_account_id is unique, on (tenant_id, account_id), partial where account_id is not null' "$([ "$(rd_sql "select indexdef from pg_indexes where schemaname='$SCHEMA' and indexname='uq_customer_tenant_id_account_id'")" = "CREATE UNIQUE INDEX uq_customer_tenant_id_account_id ON $SCHEMA.customer USING btree (tenant_id, account_id) WHERE (account_id IS NOT NULL)" ]; echo $?)"
check 'AC-D8.2 the old non-unique index is dropped and the new index is valid' "$([ "$(rd_sql "select count(*) from pg_indexes where schemaname='$SCHEMA' and indexname='idx_customer_tenant_account_id'")" = 0 ] && [ "$(rd_sql "select indisvalid from pg_index where indexrelid='$SCHEMA.uq_customer_tenant_id_account_id'::regclass")" = t ]; echo $?)"
check 'RNF-D5 each index changeset is one statement outside a transaction (runInTransaction false)' "$([ "$(awk '/id: ddl-indexes-01[89]/{f=1} f&&/runInTransaction: false/{n++;f=0} END{print n+0}' 01_ddl/10_indexes/changelog.yaml)" = 2 ] && [ "$(grep -cE '^(CREATE|DROP) .*CONCURRENTLY' 01_ddl/10_indexes/018_create_customer_account_unique_index.sql)" = 1 ] && [ "$(grep -cE '^(CREATE|DROP) .*CONCURRENTLY' 01_ddl/10_indexes/019_drop_customer_account_index.sql)" = 1 ]; echo $?)"

echo 'aNewReservationIsPendingPaymentWithNoPayment and creatingAReservationLeavesHeldSeatsUnchanged (AC-D8.3, AC-D8.4)'
rd_res_1="$(aid 2440)"
engine "$(rd_reservation "$rd_res_1" "$rd_cust_a");" >/dev/null || true
check 'AC-D8.3 a reservation inserted through the creation path is PENDING_PAYMENT and NO_PAYMENT' "$([ "$(rd_sql "select reservation_status || '/' || payment_status from $rs_t where reservation_id='$rd_res_1'")" = 'PENDING_PAYMENT/NO_PAYMENT' ]; echo $?)"
rs_refusal "$(rd_reservation "$(aid 2441)" "$rd_cust_a" | sed "s/'PENDING_PAYMENT'/'CONFIRMED'/");" trg_reservation_birth 'a reservation born CONFIRMED'
rs_refusal "$(rd_reservation "$(aid 2442)" "$rd_cust_a" | sed "s/'NO_PAYMENT'/'PARTIAL'/");" trg_reservation_birth 'a reservation born with a payment situation'
check 'AC-D8.4 held_seats of the departure is unchanged after the reservation (3 of 10)' "$([ "$(rd_sql "select held_seats from $SCHEMA.salida_capacity where salida_id='$rd_sal'")" = 3 ]; echo $?)"
check 'AC-D8.4 no allocation row exists for the reservation (the table is HU-COM-009; none can exist yet)' "$([ "$(rd_sql "select case when to_regclass('$SCHEMA.capacity_allocation') is null then 0 else (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %s where reservation_id = %L', to_regclass('$SCHEMA.capacity_allocation'), '$rd_res_1'), false, true, '')))[1]::text::int end")" = 0 ]; echo $?)"

echo 'aRepeatedKeyWritesOneResource (AC-D8.5)'
rd_key() { echo "insert into $SCHEMA.idempotency_key (key, tenant_id, resource_type, resource_id) values ('$1', '$2', 'reservation', '$3')"; }
rs_accepted "$(rd_key 'digital-key-0001' "$tenant" "$rd_res_1")" 'a new request key'
engine "$(rd_key 'digital-key-0001' "$tenant" "$rd_res_1");" >/dev/null || true
rs_refusal "$(rd_key 'digital-key-0001' "$tenant" "$(aid 2443)");" pk_idempotency_key 'the same key of the same tenant written again'
rs_accepted "$(rd_key 'digital-key-0001' "$rd_tenant_b" "$(aid 2443)")" 'the same key in another tenant'

echo 'mineIsIndexedAndIsolatedByCustomerAndTenant (AC-D8.6, AC-D8.7)'
rd_explain() { printf '%s\n' 'set enable_seqscan = off;' "explain $1;" | docker exec -i -e PGPASSWORD "$container" psql -X -U postgres -d postgres 2>&1 || true; }
sql "insert into $rs_t (reservation_id, tenant_id, customer_id, salida_id, service_id, party_size, projected_value_cents, final_value_cents, pending_balance_cents, credit_balance_cents, reservation_status, payment_status, payment_type, payment_method, created_by, created_at)
     select gen_random_uuid(), '$tenant', case when n % 4 = 0 then '$rd_cust_d'::uuid else '$rd_cust_a'::uuid end, '$rd_sal', '$rd_svc', 2, 300000, 270000, 270000, 0, 'PENDING_PAYMENT', 'NO_PAYMENT', 'DEPOSIT', 'TRANSFER', '$actor', now() - n * interval '1 minute'
     from generate_series(1, 400) n; analyze $rs_t" >/dev/null 2>&1 || true
rd_plan="$(rd_explain "select reservation_id from $rs_t where tenant_id='$tenant' and customer_id='$rd_cust_a' order by created_at desc limit 20")"; printf '%s\n' "$rd_plan"
check 'AC-D8.6 the list "mine" (tenant, customer, newest first, limited) uses idx_reservation_tenant_customer_created' "$(printf '%s\n' "$rd_plan" | grep -q 'idx_reservation_tenant_customer_created'; echo $?)"
check 'AC-D8.6 there are more than one hundred reservations for the planner to choose from' "$([ "$(rd_sql "select count(*) from $rs_t where tenant_id='$tenant'")" -gt 100 ]; echo $?)"
check 'AC-D8.7 a query scoped to tenant A and customer D never returns a reservation of customer A' "$([ "$(rd_sql "select count(*) from $rs_t where tenant_id='$tenant' and customer_id='$rd_cust_d' and reservation_id='$rd_res_1'")" = 0 ]; echo $?)"
check 'AC-D8.7 the same customer scoped to another tenant returns no row at all' "$([ "$(rd_sql "select count(*) from $rs_t where tenant_id='$rd_tenant_b' and customer_id='$rd_cust_a'")" = 0 ]; echo $?)"

echo 'customerReservationAndEventsCommitTogether (AC-D8.8, AC-D8.9)'
rd_ob="$SCHEMA.outbox_event"; rd_new_cust="$(aid 2450)"; rd_new_res="$(aid 2451)"; rd_acc_new="$(aid 2452)"
rd_confirm() { # customer id, reservation id, account, key, reservation service (default the probe tour)
  echo "begin; $(rd_key "$4" "$tenant" "$2"); $(rd_customer "$1" "$tenant" "'$3'"); $(rd_reservation "$2" "$1" "$rd_sal" "$tenant" "${5:-$rd_svc}");
    insert into $rd_ob (tenant_id, event_type, customer_id, occurred_at, payload) values ('$tenant', 'CustomerRegistered', '$1', now(), '{\"customerId\":\"$1\"}'::jsonb);
    insert into $rd_ob (tenant_id, event_type, reservation_id, actor_id, occurred_at, payload) values ('$tenant', 'ReservationCreated', '$2', '$actor', now(), '{\"customerId\":\"$1\",\"serviceId\":\"$rd_svc\",\"projectedValueCents\":300000,\"finalValueCents\":270000,\"reservationStatus\":\"PENDING_PAYMENT\",\"paymentStatus\":\"NO_PAYMENT\"}'::jsonb); commit"
}
engine "$(rd_confirm "$rd_new_cust" "$rd_new_res" "$rd_acc_new" 'digital-key-fail1' "$(aid 2499)");" >/dev/null || true
check 'AC-D8.8 when the transaction fails after the customer insert, neither the customer, the reservation, the key nor the events exist' "$([ "$(rd_sql "select (select count(*) from $rd_cust where customer_id='$rd_new_cust') + (select count(*) from $rs_t where reservation_id='$rd_new_res') + (select count(*) from $SCHEMA.idempotency_key where key='digital-key-fail1') + (select count(*) from $rd_ob where customer_id='$rd_new_cust' or reservation_id='$rd_new_res')")" = 0 ]; echo $?)"
engine "$(rd_confirm "$rd_new_cust" "$rd_new_res" "$rd_acc_new" 'digital-key-ok001');" >/dev/null || true
check 'AC-D8.9 a confirmation that commits leaves the customer, the reservation, the key, CustomerRegistered and ReservationCreated' "$([ "$(rd_sql "select (select count(*) from $rd_cust where customer_id='$rd_new_cust') || '/' || (select count(*) from $rs_t where reservation_id='$rd_new_res') || '/' || (select count(*) from $SCHEMA.idempotency_key where key='digital-key-ok001') || '/' || (select count(*) from $rd_ob where customer_id='$rd_new_cust' and event_type='CustomerRegistered') || '/' || (select count(*) from $rd_ob where reservation_id='$rd_new_res' and event_type='ReservationCreated')")" = '1/1/1/1/1' ]; echo $?)"
check 'AC-D8.9 no column of the outbox carries a document, contact or medical value' "$([ "$(rd_sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='outbox_event' and column_name ~* '(document|email|phone|contact|medical|birth|full_name)'")" = 0 ]; echo $?)"

echo 'theApplicationUserCannotDeleteCustomersOrReservations (AC-D8.10)'
rs_refusal "delete from $rd_cust where customer_id='$rd_cust_a';" 'permission denied for table customer' 'DELETE as the application user on customer'
rs_refusal "delete from $rs_t where reservation_id='$rd_res_1';" 'permission denied for table reservation' 'DELETE as the application user on reservation'
check 'AC-D8.10 neither the writer nor the application user holds DELETE on customer or reservation' "$([ "$(sql "select (has_table_privilege('$app','$rd_cust','DELETE') or has_table_privilege('$writer','$rd_cust','DELETE') or has_table_privilege('$app','$rs_t','DELETE') or has_table_privilege('$writer','$rs_t','DELETE'))")" = f ]; echo $?)"

echo 'nothingNewAppearsInPublic, aSecondRunAppliesNothing and theRollbackRestoresThePreviousIndex (AC-D8.1, AC-D8.11, AC-D8.12)'
check 'AC-D8.1 nothing new appears in public' "$([ "$(sql "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p','v','m','S','f','i') and c.relname not like 'databasechangelog%'")" = 0 ]; echo $?)"
rd_second="$(liquibase update 2>&1)"; printf '%s\n' "$rd_second"
check 'AC-D8.11 a second update applies zero changesets' "$(printf '%s\n' "$rd_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
sql "delete from $rd_ob where customer_id in (select customer_id from $rd_cust) or reservation_id in (select reservation_id from $rs_t); delete from $SCHEMA.idempotency_key where key like 'digital-key-%'; delete from $rs_t; delete from $rd_cust" >/dev/null 2>&1 || true
check 'the rows of the probes are gone before the revert' "$([ "$(sql "select (select count(*) from $rd_cust) + (select count(*) from $rs_t)")" = 0 ]; echo $?)"
liquibase rollback-count 2
rd_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$rd_base" "$rd_reverted"
check 'AC-D8.12 the two-change revert restores columns, constraints, indexes and privileges exactly' "$([ -n "$rd_base" ] && [ "$rd_reverted" = "$rd_base" ] && [ "$(sql "select count(*) from $CONTROL")" = 65 ]; echo $?)"
check 'AC-D8.12 after the revert the old index is back and the unique one is gone' "$([ "$(rd_sql "select indexdef from pg_indexes where schemaname='$SCHEMA' and indexname='idx_customer_tenant_account_id'")" = "CREATE INDEX idx_customer_tenant_account_id ON $SCHEMA.customer USING btree (tenant_id, account_id) WHERE (account_id IS NOT NULL)" ] && [ "$(rd_sql "select count(*) from pg_indexes where schemaname='$SCHEMA' and indexname='uq_customer_tenant_id_account_id'")" = 0 ]; echo $?)"
db_labels=''
liquibase update >/dev/null
check 'the two changesets reapply to 67 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 67 ]; echo $?)"
liquibase rollback-count 999 >/dev/null
liquibase update >/dev/null
liquibase validate >/dev/null
check 'a full build from empty without any label filter applies exactly 67 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 67 ]; echo $?)"
