#!/usr/bin/env bash
# Sourced by db-ci.sh after the stackable checks, on the same disposable PostgreSQL instance.
# HU-COM-014 -db (issue multi-tour-docs#180), plan D-02 to D-06: a read slice. It adds no table, column, grant or index (DP-D14-1: the
# three reads of "my reservations and my supports" are served by indexes that already exist). These probes prove it: the plans, the
# isolation of the reads by tenant and customer, the closed proof content and the absence of any new write privilege.
# The helpers rs_row, pa_attempt and pa_proof_row come from reservation-checks.sh and payment-checks.sh.
cc_tenant_b="00000000-0000-0000-0000-000000000002"
cc_a1="$(aid 4101)"; cc_a2="$(aid 4102)"; cc_b1="$(aid 4103)"; cc_b2="$(aid 4104)"; cc_svc="$(aid 4105)"; cc_svc_b="$(aid 4106)"
cc_res_a1="$(aid 4110)"; cc_res_a2="$(aid 4111)"; cc_res_b1="$(aid 4112)"
cc_att_a1="$(aid 4120)"; cc_att_a2="$(aid 4121)"; cc_att_b1="$(aid 4122)"
cc_sql() { sql "$1" 2>/dev/null || true; }
cc_app() { # SQL: one value read as the application user, last output line
  printf '%s\n' "set role $app;" "$1" | docker exec -i -e PGPASSWORD "$container" psql -X -q -U postgres -d postgres -tA -f - 2>&1 | tail -n 1
}
cc_explain() { printf '%s\n' "${CC_PLAN_SETUP:-select 1;}" "explain $1;" | docker exec -i -e PGPASSWORD "$container" psql -X -U postgres -d postgres 2>&1 || true; }
cc_file() { # tenant, attempt, customer (SQL literals): the owner check of plan D-04, one statement
  echo "select count(*) from $SCHEMA.payment_proof_file f join $SCHEMA.payment_attempt a on a.payment_attempt_id = f.payment_attempt_id and a.tenant_id = $1 join $SCHEMA.reservation r on r.reservation_id = a.reservation_id and r.tenant_id = $1 where f.payment_attempt_id = $2 and r.customer_id = $3"
}
cc_grants() { # the write privileges of the writer and the application user on the three tables of the reads
  sql "select string_agg(role || ':' || tbl || ':' || priv, ',' order by role || tbl || priv) from (select r role, t tbl, p priv from unnest(array['$writer','$app']) r, unnest(array['reservation','payment_attempt','payment_proof_file']) t, unnest(array['INSERT','UPDATE','DELETE']) p where has_table_privilege(r, format('%I.%I', '$SCHEMA', t), p)) g" 2>/dev/null || true
}

echo 'HU-COM-014 consultation - base: the full schema, with the slice adding nothing to it'
liquibase rollback-count 999 >/dev/null
db_labels=''
liquibase update >/dev/null
cc_base="$(snapshot)"
cc_changesets="$(sql "select count(*) from $CONTROL")"
cc_public="select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p','v','m','S','f') and c.relname not like 'databasechangelog%'"
check 'slice014AddsNothingOrOneIndexAndNothingInPublic (AC-D14.1): the slice has no changeset of its own and nothing is in public' "$([ "$(sql "select count(*) from $CONTROL where labels ilike '%HU-COM-014%'")" = 0 ] && [ "$(sql "$cc_public")" = 0 ]; echo $?)"
check 'the names the probes read exist: three tables and their three indexes' "$([ "$(sql "select count(*) from pg_tables where schemaname='$SCHEMA' and tablename in ('reservation','payment_attempt','payment_proof_file')")" = 3 ] && [ "$(sql "select count(*) from pg_indexes where schemaname='$SCHEMA' and indexname in ('idx_reservation_tenant_customer_created','idx_payment_attempt_tenant_reservation_registered_at','uq_payment_proof_file_payment_attempt')")" = 3 ]; echo $?)"

echo 'seed: two tenants, two customers each, a tenant of 100 000 reservations, five of them of one customer'
sql "insert into $SCHEMA.customer (customer_id, tenant_id, full_name, created_at, document_number, birth_date_or_age, contact_info, status, terms_accepted, terms_accepted_at) values ('$cc_a1', '$tenant', 'Consultation A1', now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE', true, now()), ('$cc_a2', '$tenant', 'Consultation A2', now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE', true, now()), ('$cc_b1', '$cc_tenant_b', 'Consultation B1', now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE', true, now()), ('$cc_b2', '$cc_tenant_b', 'Consultation B2', now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE', true, now());
     insert into $SCHEMA.catalog_service (service_id, tenant_id, service_type, commercial_name, catalog_status, base_rate_cents, base_operational_cost_cents, configured_capacity, transport_required, high_risk, created_at, updated_at) values ('$cc_svc', '$tenant', 'TOUR', 'Consultation tour', 'ACTIVE', 150000, 90000, 12, false, false, now(), now()), ('$cc_svc_b', '$cc_tenant_b', 'TOUR', 'Consultation tour B', 'ACTIVE', 150000, 90000, 12, false, false, now(), now())" >/dev/null 2>&1 || true
sql "insert into $SCHEMA.reservation (reservation_id, tenant_id, customer_id, salida_id, service_id, party_size, projected_value_cents, final_value_cents, pending_balance_cents, credit_balance_cents, reservation_status, payment_status, payment_type, payment_method, created_by, created_at)
     select case when n = 1 then '$cc_res_a2'::uuid else gen_random_uuid() end, '$tenant', '$cc_a2', gen_random_uuid(), '$cc_svc', 2, 300000, 270000, 270000, 0, 'PENDING_PAYMENT', 'NO_PAYMENT', 'DEPOSIT', 'TRANSFER', '$actor', now() - (n || ' seconds')::interval from generate_series(1, 99995) n;
     insert into $SCHEMA.reservation (reservation_id, tenant_id, customer_id, salida_id, service_id, party_size, projected_value_cents, final_value_cents, pending_balance_cents, credit_balance_cents, reservation_status, payment_status, payment_type, payment_method, created_by, created_at)
     select case when n = 1 then '$cc_res_a1'::uuid else gen_random_uuid() end, '$tenant', '$cc_a1', gen_random_uuid(), '$cc_svc', 2, 300000, 270000, 270000, 0, 'PENDING_PAYMENT', 'NO_PAYMENT', 'DEPOSIT', 'TRANSFER', '$actor', now() - (n || ' minutes')::interval from generate_series(1, 5) n;
     insert into $SCHEMA.reservation (reservation_id, tenant_id, customer_id, salida_id, service_id, party_size, projected_value_cents, final_value_cents, pending_balance_cents, credit_balance_cents, reservation_status, payment_status, payment_type, payment_method, created_by, created_at)
     select case when n = 1 then '$cc_res_b1'::uuid else gen_random_uuid() end, '$cc_tenant_b', '$cc_b1', gen_random_uuid(), '$cc_svc_b', 2, 300000, 270000, 270000, 0, 'PENDING_PAYMENT', 'NO_PAYMENT', 'DEPOSIT', 'TRANSFER', '$actor', now() - (n || ' minutes')::interval from generate_series(1, 3) n;" >/dev/null 2>&1 || true
sql "insert into $SCHEMA.payment_attempt (payment_attempt_id, tenant_id, reservation_id, payment_method, received_amount_cents, validation_status, payment_status_snapshot, registered_by, registered_at)
     select gen_random_uuid(), '$tenant', r.reservation_id, 'TRANSFER', 100000, 'IN_VALIDATION', 'NO_PAYMENT', '$actor', now() - (g || ' minutes')::interval
     from (select reservation_id from $SCHEMA.reservation where customer_id = '$cc_a2' limit 400) r, generate_series(1, 8) g where r.reservation_id <> '$cc_res_a2';
     insert into $SCHEMA.payment_attempt (payment_attempt_id, tenant_id, reservation_id, payment_method, received_amount_cents, validation_status, payment_status_snapshot, registered_by, registered_at) values
       ('$cc_att_a1', '$tenant', '$cc_res_a1', 'TRANSFER', 100000, 'IN_VALIDATION', 'NO_PAYMENT', '$actor', now()),
       ('$cc_att_a2', '$tenant', '$cc_res_a2', 'TRANSFER', 100000, 'IN_VALIDATION', 'NO_PAYMENT', '$actor', now()),
       ('$cc_att_b1', '$cc_tenant_b', '$cc_res_b1', 'TRANSFER', 100000, 'IN_VALIDATION', 'NO_PAYMENT', '$actor', now());
     insert into $SCHEMA.payment_proof_file (payment_proof_file_id, tenant_id, payment_attempt_id, content, content_type, size_bytes, sha256)
     select gen_random_uuid(), tenant_id, payment_attempt_id, '\\x616263'::bytea, 'application/pdf', 3, repeat('a', 64) from $SCHEMA.payment_attempt where payment_attempt_id in ('$cc_att_a1', '$cc_att_a2', '$cc_att_b1');
     analyze $SCHEMA.reservation; analyze $SCHEMA.payment_attempt; analyze $SCHEMA.payment_proof_file" >/dev/null 2>&1 || true
check 'the seed holds 100 000 reservations in the first tenant, five of one customer, and the attempts and files of the probe' "$([ "$(cc_sql "select count(*) from $SCHEMA.reservation where tenant_id='$tenant' and (customer_id in ('$cc_a1','$cc_a2'))")" = 100000 ] && [ "$(cc_sql "select count(*) from $SCHEMA.reservation where customer_id='$cc_a1'")" = 5 ] && [ "$(cc_sql "select count(*) from $SCHEMA.payment_proof_file where payment_attempt_id in ('$cc_att_a1','$cc_att_a2','$cc_att_b1')")" = 3 ]; echo $?)"

echo 'ownReservationsListUsesTheCustomerIndex (AC-D14.2)'
cc_plan_l="$(cc_explain "select reservation_id from $SCHEMA.reservation where tenant_id='$tenant' and customer_id='$cc_a1' order by created_at desc limit 100")"; printf '%s\n' "$cc_plan_l"
check 'AC-D14.2 the list of one customer, newest first, uses idx_reservation_tenant_customer_created and no sequential scan' "$(printf '%s\n' "$cc_plan_l" | grep -q 'idx_reservation_tenant_customer_created' && ! printf '%s\n' "$cc_plan_l" | grep -q 'Seq Scan'; echo $?)"
cc_plan_o="$(cc_explain "select reservation_id from $SCHEMA.reservation where tenant_id='$tenant' and customer_id='$cc_a1' and reservation_status in ('PENDING_PAYMENT','CONFIRMED') and pending_balance_cents > 0 order by created_at desc limit 100")"; printf '%s\n' "$cc_plan_o"
check 'DP-D14-1 the open-with-balance filter needs no new index: the same index serves it, so T-05 is not needed' "$(printf '%s\n' "$cc_plan_o" | grep -q 'idx_reservation_tenant_customer_created' && ! printf '%s\n' "$cc_plan_o" | grep -q 'Seq Scan'; echo $?)"

echo 'attemptsOfAReservationUseTheAttemptIndex (AC-D14.3)'
cc_plan_a="$(cc_explain "select * from $SCHEMA.payment_attempt where tenant_id='$tenant' and reservation_id='$cc_res_a1' order by registered_at desc")"; printf '%s\n' "$cc_plan_a"
check 'AC-D14.3 the attempts of one reservation, newest first, use idx_payment_attempt_tenant_reservation_registered_at' "$(printf '%s\n' "$cc_plan_a" | grep -q 'idx_payment_attempt_tenant_reservation_registered_at'; echo $?)"
cc_plan_p="$(cc_explain "select r.reservation_id, la.registered_at from $SCHEMA.reservation r left join lateral (select a.registered_at from $SCHEMA.payment_attempt a where a.tenant_id = r.tenant_id and a.reservation_id = r.reservation_id order by a.registered_at desc limit 1) la on true where r.tenant_id='$tenant' and r.customer_id='$cc_a1' order by r.created_at desc limit 20")"; printf '%s\n' "$cc_plan_p"
check 'AC-D14.3 the latest attempt per reservation of a page uses the attempt index through the lateral join' "$(printf '%s\n' "$cc_plan_p" | grep -q 'idx_payment_attempt_tenant_reservation_registered_at'; echo $?)"

echo 'theFileWithItsOwnerCheckIsOneStatementByTheUniqueKey (AC-D14.4)'
check 'AC-D14.4 the owner reads the file of their payment, as the application user' "$([ "$(cc_app "$(cc_file "'$tenant'" "'$cc_att_a1'" "'$cc_a1'")")" = 1 ]; echo $?)"
check 'AC-D14.4 another customer of the same tenant gets no row for that payment' "$([ "$(cc_app "$(cc_file "'$tenant'" "'$cc_att_a1'" "'$cc_a2'")")" = 0 ]; echo $?)"
check 'AC-D14.4 another tenant gets no row for that payment, even with the owner customer' "$([ "$(cc_app "$(cc_file "'$cc_tenant_b'" "'$cc_att_a1'" "'$cc_a1'")")" = 0 ]; echo $?)"
check 'AC-D14.4 a payment that does not exist gets no row' "$([ "$(cc_app "$(cc_file "'$tenant'" "'$(aid 4199)'" "'$cc_a1'")")" = 0 ]; echo $?)"
cc_plan_f="$(CC_PLAN_SETUP='set enable_seqscan = off;' cc_explain "$(cc_file "'$tenant'" "'$cc_att_a1'" "'$cc_a1'")")"; printf '%s\n' "$cc_plan_f"
check 'AC-D14.4 the plan reaches the file by uq_payment_proof_file_payment_attempt and the attempt by its key (the primary key or the key that starts with tenant_id)' "$(printf '%s\n' "$cc_plan_f" | grep -q 'uq_payment_proof_file_payment_attempt' && printf '%s\n' "$cc_plan_f" | grep -Eq 'pk_payment_attempt|uq_payment_attempt_tenant_id_payment_attempt_id'; echo $?)"

echo 'noReadCrossesACustomerOrATenant (AC-D14.5)'
check 'AC-D14.5 the list of the first customer of tenant B holds its own three reservations and no row of tenant A' "$([ "$(cc_app "select count(*) from $SCHEMA.reservation where tenant_id='$cc_tenant_b' and customer_id='$cc_b1'")" = 3 ] && [ "$(cc_app "select count(*) from $SCHEMA.reservation where tenant_id='$cc_tenant_b' and customer_id='$cc_a1'")" = 0 ]; echo $?)"
check 'AC-D14.5 the list of customer A1 never carries a reservation of customer A2 or of tenant B' "$([ "$(cc_app "select count(*) from $SCHEMA.reservation where tenant_id='$tenant' and customer_id='$cc_a1' and (reservation_id = '$cc_res_a2' or reservation_id = '$cc_res_b1')")" = 0 ]; echo $?)"
check 'AC-D14.5 the attempts of a reservation, read with the tenant of another one, are none' "$([ "$(cc_app "select count(*) from $SCHEMA.payment_attempt where tenant_id='$cc_tenant_b' and reservation_id='$cc_res_a1'")" = 0 ] && [ "$(cc_app "select count(*) from $SCHEMA.payment_attempt where tenant_id='$tenant' and reservation_id='$cc_res_a1'")" = 1 ]; echo $?)"

echo 'theReaderRoleCannotSelectTheProofContent and noNewWritePrivilegeAppears (AC-D14.6, AC-D14.7)'
cc_reader_answer="$(as_role "$reader" "select content from $SCHEMA.payment_proof_file;")"; printf '%s\n' "$cc_reader_answer"
check 'AC-D14.6 the reader role is refused the proof content for lack of privilege' "$(printf '%s\n' "$cc_reader_answer" | grep -q 'permission denied for table payment_proof_file'; echo $?)"
check 'AC-D14.6 the application user still reads the proof content' "$([ "$(cc_app "select count(*) from $SCHEMA.payment_proof_file where content is not null")" -ge 3 ]; echo $?)"
cc_grants_now="$(cc_grants)"; printf 'Write privileges on the three tables: %s\n' "$cc_grants_now"
check 'AC-D14.7 the writer and the application user hold only the INSERT and UPDATE the earlier stories gave, never a DELETE, and none on the proof but INSERT' "$(printf '%s\n' "$cc_grants_now" | grep -qv 'DELETE' && ! printf '%s\n' "$cc_grants_now" | grep -q 'payment_proof_file:UPDATE'; echo $?)"
check 'AC-D14.7 neither the writer nor the application user can DELETE on the three tables of the reads (the over-granted count stays 0)' "$([ "$(sql "select count(*) from unnest(array['reservation','payment_attempt','payment_proof_file']) t where has_table_privilege('$writer', format('%I.%I', '$SCHEMA', t), 'DELETE') or has_table_privilege('$app', format('%I.%I', '$SCHEMA', t), 'DELETE')")" = 0 ]; echo $?)"

echo 'secondRunAppliesZeroAndTheRevertRestoresTheSchema (AC-D14.8, AC-D14.9)'
cc_second="$(liquibase update 2>&1)"; printf '%s\n' "$cc_second"
check 'AC-D14.8 a second update applies zero changesets' "$(printf '%s\n' "$cc_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
sql "delete from $SCHEMA.payment_proof_file where payment_attempt_id in (select payment_attempt_id from $SCHEMA.payment_attempt where tenant_id in ('$tenant','$cc_tenant_b') and reservation_id in (select reservation_id from $SCHEMA.reservation where customer_id in ('$cc_a1','$cc_a2','$cc_b1')));
     delete from $SCHEMA.payment_attempt where reservation_id in (select reservation_id from $SCHEMA.reservation where customer_id in ('$cc_a1','$cc_a2','$cc_b1'));
     delete from $SCHEMA.reservation where customer_id in ('$cc_a1','$cc_a2','$cc_b1');
     delete from $SCHEMA.catalog_service where service_id in ('$cc_svc', '$cc_svc_b');
     delete from $SCHEMA.customer where customer_id in ('$cc_a1','$cc_a2','$cc_b1','$cc_b2')" >/dev/null 2>&1 || true
check 'AC-D14.9 with the rows of the probe gone, the schema is exactly the one the earlier stories left, and the slice leaves no changeset behind' "$([ -n "$cc_base" ] && [ "$(snapshot)" = "$cc_base" ] && [ "$(sql "select count(*) from $CONTROL")" = "$cc_changesets" ]; echo $?)"
