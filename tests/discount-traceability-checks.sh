#!/usr/bin/env bash
# Sourced by db-ci.sh after the HU-COM-008 checks, on the same disposable PostgreSQL instance, over the full schema.
# HU-COM-004 -db (spec 004-hu-com-004-view-and-apply-current-discounts): T-04 and T-07, the two tasks that had no probe.
#  T-04: EXPLAIN of the lookup of the additional discount of a reservation and of the enabled reasons of a tenant, on tables with
#        enough rows to make a scan the alternative. The tasks.md names idx_authorizable_reason_tenant_status; the built partial
#        index is idx_authorizable_reason_tenant_enabled (10_indexes/011), so the probe judges the built name.
#  T-07: the additional line joins to the fixed lines of HU-COM-007 by reservation and tenant, in application order, each with its base.
# This slice creates no changeset: it only judges objects that already exist. NOT judged here, because the documents leave it open:
# the tenant-aware (composite) key from the discount to the reservation (T-06, DP-D7-4).
dt_tenant_b="00000000-0000-0000-0000-000000000002"
dt_customer="$(aid 5101)"; dt_customer_b="$(aid 5102)"; dt_svc="$(aid 5103)"; dt_rule="$(aid 5104)"; dt_rule2="$(aid 5105)"
dt_res="$(aid 5110)"; dt_res_b="$(aid 5111)"; dt_salida="$(aid 5120)"
dt_ad="$SCHEMA.reservation_additional_discount"; dt_ar="$SCHEMA.authorizable_reason"; dt_fd="$SCHEMA.reservation_fixed_discount"
dt_sql() { sql "$1" 2>/dev/null || true; }
dt_explain() { printf '%s\n' 'set enable_seqscan = off;' "explain $1;" | docker exec -i -e PGPASSWORD "$container" psql -X -U postgres -d postgres 2>&1 || true; }
dt_explain_plain() { printf '%s\n' "explain $1;" | docker exec -i -e PGPASSWORD "$container" psql -X -U postgres -d postgres 2>&1 || true; }

echo 'HU-COM-004 T-04 and T-07 - rows for two tenants on the full schema (superuser, so the probes judge the plans, not the grants)'
sql "insert into $SCHEMA.customer (customer_id, tenant_id, full_name, created_at, document_number, birth_date_or_age, contact_info, status, terms_accepted, terms_accepted_at) values ('$dt_customer', '$tenant', 'Traceability probe A', now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE', true, now()), ('$dt_customer_b', '$dt_tenant_b', 'Traceability probe B', now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE', true, now());
     insert into $SCHEMA.catalog_service (service_id, tenant_id, service_type, commercial_name, catalog_status, base_rate_cents, base_operational_cost_cents, configured_capacity, transport_required, high_risk, created_at, updated_at) values ('$dt_svc', '$tenant', 'TOUR', 'Traceability probe tour', 'ACTIVE', 150000, 90000, 12, false, false, now(), now());
     insert into $SCHEMA.discount_rule (discount_rule_id, tenant_id, name, starts_on, ends_on, priority, calculation_base, discount_type, discount_percentage_bp, discount_amount_cents, status, covers_all_services, created_at, updated_at) values ('$dt_rule', '$tenant', 'Season offer', current_date, current_date + 90, 1, 'ORIGINAL_VALUE', 'PERCENTAGE', 1000, NULL, 'ACTIVE', true, now(), now()), ('$dt_rule2', '$tenant', 'Fixed offer', current_date, current_date + 90, 2, 'PREVIOUS_SUBTOTAL', 'FIXED_AMOUNT', NULL, 5000, 'ACTIVE', true, now(), now())" >/dev/null 2>&1 || true
dt_resv() { # reservation id, tenant, customer
  echo "insert into $SCHEMA.reservation (reservation_id, tenant_id, customer_id, salida_id, service_id, party_size, projected_value_cents, final_value_cents, pending_balance_cents, credit_balance_cents, reservation_status, payment_status, payment_type, payment_method, created_by, created_at) values ('$1', '$2', '$3', '$dt_salida', '$dt_svc', 2, 300000, 270000, 270000, 0, 'PENDING_PAYMENT', 'NO_PAYMENT', 'DEPOSIT', 'TRANSFER', '$actor', now())"
}
check 'T-07 precondition: reservation_fixed_discount, reservation_additional_discount and authorizable_reason exist' "$([ "$(dt_sql "select count(*) from pg_tables where schemaname='$SCHEMA' and tablename in ('reservation','reservation_fixed_discount','reservation_additional_discount','authorizable_reason')")" = 4 ]; echo $?)"
sql "$(dt_resv "$dt_res" "$tenant" "$dt_customer"); $(dt_resv "$dt_res_b" "$dt_tenant_b" "$dt_customer_b")" >/dev/null 2>&1 || true
sql "insert into $SCHEMA.reservation (reservation_id, tenant_id, customer_id, salida_id, service_id, party_size, projected_value_cents, final_value_cents, pending_balance_cents, credit_balance_cents, reservation_status, payment_status, payment_type, payment_method, created_by, created_at)
     select gen_random_uuid(), t, case when t = '$tenant' then '$dt_customer'::uuid else '$dt_customer_b'::uuid end, '$dt_salida', '$dt_svc', 2, 300000, 270000, 270000, 0, 'PENDING_PAYMENT', 'NO_PAYMENT', 'DEPOSIT', 'TRANSFER', '$actor', now() - n * interval '1 minute'
     from unnest(array['$tenant', '$dt_tenant_b']::uuid[]) t, generate_series(1, 2500) n" >/dev/null 2>&1 || true
sql "insert into $dt_ad (additional_discount_id, tenant_id, reservation_id, discount_percentage_bp, reason, applied_by, applied_at, previous_value_cents, amount_cents)
     select gen_random_uuid(), tenant_id, reservation_id, 1000, 'Fidelizacion', '$actor', now(), 100000, 10000 from $SCHEMA.reservation where salida_id = '$dt_salida' and reservation_id not in ('$dt_res', '$dt_res_b')" >/dev/null 2>&1 || true
sql "insert into $dt_ar (authorizable_reason_id, tenant_id, reason, status, created_at, updated_at)
     select gen_random_uuid(), '$tenant', 'Probe reason ' || n, case when n <= 8 then 'ENABLED' else 'DISABLED' end, now(), now() from generate_series(1, 3000) n;
     insert into $dt_ar (authorizable_reason_id, tenant_id, reason, status, created_at, updated_at)
     select gen_random_uuid(), '$dt_tenant_b', 'Probe reason ' || n, 'ENABLED', now(), now() from generate_series(1, 3000) n;
     analyze $SCHEMA.reservation; analyze $dt_ad; analyze $dt_ar" >/dev/null 2>&1 || true
check 'T-04 the probe tables hold enough rows to make a scan the alternative (5000 discounts, 6000 reasons)' "$([ "$(dt_sql "select count(*) from $dt_ad")" -ge 4900 ] && [ "$(dt_sql "select count(*) from $dt_ar")" = 6000 ]; echo $?)"

echo 'theDiscountOfAReservationAndTheEnabledReasonsUseTheirIndex (AC-D4.11, T-04)'
check 'AC-D4.11 both indexes exist: the unique on reservation_id and the partial on (tenant_id) where status = ENABLED' "$([ "$(dt_sql "select count(*) from pg_indexes where schemaname='$SCHEMA' and ((indexname='idx_authorizable_reason_tenant_enabled' and indexdef like '%(tenant_id) WHERE (status = ''ENABLED''::text)') or (tablename='reservation_additional_discount' and indexname='uq_reservation_additional_discount_reservation' and indexdef like '%UNIQUE%(reservation_id)'))")" = 2 ]; echo $?)"
dt_plan="$(dt_explain "select additional_discount_id, discount_percentage_bp, amount_cents from $dt_ad where reservation_id = '$dt_res'")"; printf '%s\n' "$dt_plan"
check 'AC-D4.11 the discount of a reservation uses uq_reservation_additional_discount_reservation' "$(printf '%s\n' "$dt_plan" | grep -q 'uq_reservation_additional_discount_reservation'; echo $?)"
dt_plan="$(dt_explain_plain "select authorizable_reason_id, reason from $dt_ar where tenant_id = '$tenant' and status = 'ENABLED' order by reason")"; printf '%s\n' "$dt_plan"
check 'AC-D4.11 the enabled reasons of a tenant use idx_authorizable_reason_tenant_enabled without disabling sequential scans' "$(printf '%s\n' "$dt_plan" | grep -q 'idx_authorizable_reason_tenant_enabled'; echo $?)"
check 'T-04 the enabled reasons of a tenant are 8 of its 3000, and tenant B holds its own 3000 apart' "$([ "$(dt_sql "select count(*) from $dt_ar where tenant_id='$tenant' and status='ENABLED'")" = 8 ] && [ "$(dt_sql "select count(*) from $dt_ar where tenant_id='$dt_tenant_b'")" = 3000 ]; echo $?)"

echo 'theAdditionalLineJoinsTheFixedLinesInApplicationOrder (AC-D4.10, T-07)'
sql "insert into $dt_fd (reservation_fixed_discount_id, tenant_id, reservation_id, line_order, discount_rule_id, rule_name, discount_type, discount_percentage_bp, discount_amount_cents, calculation_base, base_cents, amount_cents, subtotal_cents, cap_cents) values
       (gen_random_uuid(), '$tenant', '$dt_res', 1, '$dt_rule', 'Season offer', 'PERCENTAGE', 1000, NULL, 'ORIGINAL_VALUE', 300000, 30000, 270000, NULL),
       (gen_random_uuid(), '$tenant', '$dt_res', 2, '$dt_rule2', 'Fixed offer', 'FIXED_AMOUNT', NULL, 5000, 'PREVIOUS_SUBTOTAL', 270000, 5000, 265000, NULL);
     insert into $dt_ad (additional_discount_id, tenant_id, reservation_id, discount_percentage_bp, reason, applied_by, applied_at, previous_value_cents, amount_cents) values
       (gen_random_uuid(), '$tenant', '$dt_res', 1000, 'Cliente frecuente', '$actor', now(), 265000, 26500)" >/dev/null 2>&1 || true
dt_trace() { # tenant, reservation: fixed lines then the additional line, in application order, each with its base
  echo "select string_agg(kind || ':' || position || ':' || base_cents || ':' || amount_cents, '|' order by position) from (
          select 'fixed' as kind, f.line_order as position, f.base_cents, f.amount_cents from $dt_fd f where f.tenant_id = '$1' and f.reservation_id = '$2'
          union all
          select 'additional', (select coalesce(max(f.line_order), 0) + 1 from $dt_fd f where f.tenant_id = a.tenant_id and f.reservation_id = a.reservation_id), a.previous_value_cents, a.amount_cents
            from $dt_ad a where a.tenant_id = '$1' and a.reservation_id = '$2') lines"
}
dt_got="$(dt_sql "$(dt_trace "$tenant" "$dt_res")")"; printf 'trace of the reservation: %s\n' "$dt_got"
check 'AC-D4.10 one read by reservation returns the two fixed lines and then the additional line, each with its base' "$([ "$dt_got" = 'fixed:1:300000:30000|fixed:2:270000:5000|additional:3:265000:26500' ]; echo $?)"
check 'AC-D4.10 the base of the additional line is the subtotal that the last fixed line left' "$([ "$(dt_sql "select a.previous_value_cents = f.subtotal_cents from $dt_ad a join $dt_fd f on f.tenant_id = a.tenant_id and f.reservation_id = a.reservation_id where a.reservation_id = '$dt_res' and f.line_order = (select max(line_order) from $dt_fd where reservation_id = '$dt_res')")" = t ]; echo $?)"
check 'AC-D4.10 a read scoped to tenant B for that reservation returns nothing (the tenant scope of the join)' "$([ -z "$(dt_sql "$(dt_trace "$dt_tenant_b" "$dt_res")")" ]; echo $?)"
check 'AC-D4.10 a reservation with an additional discount and no fixed line reads the additional line alone, in position 1' "$([ "$(dt_sql "$(dt_trace "$tenant" "$(dt_sql "select reservation_id from $dt_ad where tenant_id='$tenant' and reservation_id <> '$dt_res' limit 1")")")" = 'additional:1:100000:10000' ]; echo $?)"
