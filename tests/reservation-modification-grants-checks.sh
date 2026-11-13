#!/usr/bin/env bash
# Sourced by db-ci.sh after the modification checks, on the same disposable PostgreSQL instance and with the 128 changesets of the earlier stories applied.
# HU-COM-012 -db, slice 2 (issue multi-tour-docs#178), plan D-08, DP-D12-4 and DP-D12-5: what the -api needs to store a modified reservation. The writer
# (and so the application user) may UPDATE only the three amount columns of a discount line, never its type, value or rule copy, and may DELETE the rows of
# the companions so a reservation can replace them. Two changesets, labelled HU-COM-012 and reservation-modification-grants. Probes first: red, then green.
mg_fd="$SCHEMA.reservation_fixed_discount"; mg_c="$SCHEMA.reservation_companion"; mg_s="$SCHEMA.reservation_companion_sensitive_data"
mg_tenant_b="00000000-0000-0000-0000-000000000002"
mg_cust="$(aid 4301)"; mg_svc="$(aid 4302)"; mg_res="$(aid 4303)"; mg_rule="$(aid 4304)"; mg_comp="$(aid 4305)"
mg_amount_cols='base_cents amount_cents subtotal_cents'
mg_fixed_cols='reservation_fixed_discount_id tenant_id reservation_id line_order discount_rule_id rule_name discount_type discount_percentage_bp discount_amount_cents calculation_base cap_cents'
mg_sql() { sql "$1" 2>/dev/null || true; }
mg_can_update() { # role, column
  mg_sql "select has_column_privilege('$1', '$mg_fd', '$2', 'UPDATE')"
}
mg_delete_tables() { mg_sql "select count(*) from information_schema.role_table_grants where table_schema = '$SCHEMA' and grantee = '$writer' and privilege_type = 'DELETE'"; }

echo 'HU-COM-012 db slice 2 - base: the 128 changesets that exist before the grants'
liquibase rollback-count 999 >/dev/null
db_labels='!reservation-modification-grants and !HU-COM-017 and !HU-COM-019 and !HU-COM-018 and !HU-COM-020 and !decision-resume and !episode-frozen-total and !departure-order and !exceptional-access-use and !reservation-confirmed-value and !payment-parameters-changed and !account-session-cutoff and !restricted-access-reason and !establishment-contact-log and !rescheduling-proposed-notice and !fk-tenant-composite and !cancellation-penalty-policy'
liquibase update >/dev/null
mg_base="$(snapshot)"
mg_base_delete="$(mg_delete_tables)"
check 'base holds exactly 128 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 128 ]; echo $?)"
sql "insert into $SCHEMA.customer (customer_id, tenant_id, full_name, created_at, document_number, birth_date_or_age, contact_info, status, terms_accepted, terms_accepted_at) values ('$mg_cust', '$tenant', 'Grants probe', now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE', true, now());
     insert into $SCHEMA.catalog_service (service_id, tenant_id, service_type, commercial_name, catalog_status, base_rate_cents, base_operational_cost_cents, configured_capacity, transport_required, high_risk, created_at, updated_at) values ('$mg_svc', '$tenant', 'TOUR', 'Grants probe tour', 'ACTIVE', 150000, 90000, 12, false, false, now(), now());
     insert into $SCHEMA.discount_rule (discount_rule_id, tenant_id, name, starts_on, ends_on, priority, calculation_base, discount_type, discount_percentage_bp, discount_amount_cents, status, covers_all_services, created_at, updated_at) values ('$mg_rule', '$tenant', 'Grants probe rule', current_date, current_date + 90, 1, 'ORIGINAL_VALUE', 'PERCENTAGE', 1000, NULL, 'ACTIVE', true, now(), now())" >/dev/null 2>&1 || true
engine "$(rs_row reservation_id "'$mg_res'" customer_id "'$mg_cust'" service_id "'$mg_svc'");" >/dev/null || true
sql "insert into $mg_fd (reservation_fixed_discount_id, tenant_id, reservation_id, line_order, discount_rule_id, rule_name, discount_type, discount_percentage_bp, discount_amount_cents, calculation_base, base_cents, amount_cents, subtotal_cents, cap_cents) values (gen_random_uuid(), '$tenant', '$mg_res', 1, '$mg_rule', 'Grants probe rule', 'PERCENTAGE', 1000, NULL, 'ORIGINAL_VALUE', 300000, 30000, 270000, NULL);
     insert into $mg_c (reservation_companion_id, tenant_id, reservation_id, full_name, document_number, birth_date_or_age) values ('$mg_comp', '$tenant', '$mg_res', 'Grants probe companion', 'CC4305', 'A:25')" >/dev/null 2>&1 || true
check 'the probe line and the probe companion exist on the base' "$([ "$(mg_sql "select (select count(*) from $mg_fd where reservation_id = '$mg_res') + (select count(*) from $mg_c where reservation_id = '$mg_res')")" = 2 ]; echo $?)"

echo 'HU-COM-012 db slice 2 - probes written first: red before the changesets, green after'
check 'RED the writer cannot yet update an amount column of a discount line' "$([ "$(mg_can_update "$writer" base_cents)" = f ]; echo $?)"
check 'RED the writer cannot yet delete a companion' "$([ "$(mg_sql "select has_table_privilege('$writer', '$mg_c', 'DELETE')")" = f ]; echo $?)"
db_labels='reservation-modification-grants'
liquibase update >/dev/null
check 'the two changesets of the slice bring the control table to 130' "$([ "$(sql "select count(*) from $CONTROL")" = 130 ]; echo $?)"

echo 'theThreeAmountColumnsCanBeUpdatedAndNoOtherColumn (DP-D12-4)'
for col in $mg_amount_cols; do
  check "AC-D12.14 the writer and the application user may update $col" "$([ "$(mg_can_update "$writer" "$col")" = t ] && [ "$(mg_can_update "$app" "$col")" = t ]; echo $?)"
done
for col in $mg_fixed_cols; do
  check "AC-D12.14 the writer, the application user and the reader may not update $col" "$([ "$(mg_can_update "$writer" "$col")" = f ] && [ "$(mg_can_update "$app" "$col")" = f ] && [ "$(mg_can_update "$reader" "$col")" = f ]; echo $?)"
done
check 'AC-D12.14 the reader may not update an amount column' "$([ "$(mg_can_update "$reader" amount_cents)" = f ]; echo $?)"
mg_ok="$(mg_sql "set role $writer; with changed as (update $mg_fd set base_cents = 600000, amount_cents = 60000, subtotal_cents = 540000 where tenant_id = '$tenant' and reservation_id = '$mg_res' returning 1) select count(*) from changed")"
check 'AC-D12.14 the writer rewrites the three amounts of the line of its tenant' "$([ "$(printf '%s\n' "$mg_ok" | tail -1)" = 1 ]; echo $?)"
mg_denied="$(sql "set role $writer; update $mg_fd set discount_type = 'FIXED_AMOUNT' where reservation_id = '$mg_res'" 2>&1 || true)"; printf '%s\n' "$mg_denied"
check 'AC-D12.14 the writer is refused on the type of the line (permission denied)' "$(printf '%s\n' "$mg_denied" | grep -qi 'permission denied'; echo $?)"
mg_kept="$(mg_sql "select discount_type || ':' || rule_name || ':' || discount_percentage_bp from $mg_fd where reservation_id = '$mg_res'")"
check 'AC-D12.14 the type, the rule copy and the value of the line are as they were' "$([ "$mg_kept" = 'PERCENTAGE:Grants probe rule:1000' ]; echo $?)"

echo 'aCompanionDeleteWorksInItsTenantOnly (DP-D12-5)'
check 'AC-D12.15 the writer and the application user may delete the companions and their sensitive rows, the reader may not' "$([ "$(mg_sql "select has_table_privilege('$writer', '$mg_c', 'DELETE') and has_table_privilege('$app', '$mg_c', 'DELETE') and has_table_privilege('$writer', '$mg_s', 'DELETE') and has_table_privilege('$app', '$mg_s', 'DELETE') and not has_table_privilege('$reader', '$mg_c', 'DELETE') and not has_table_privilege('$reader', '$mg_s', 'DELETE')")" = t ]; echo $?)"
check 'AC-D12.15 exactly two tables gained DELETE and the discount lines did not' "$([ "$(mg_delete_tables)" = "$((mg_base_delete + 2))" ] && [ "$(mg_sql "select has_table_privilege('$writer', '$mg_fd', 'DELETE')")" = f ]; echo $?)"
mg_other="$(mg_sql "set role $writer; with gone as (delete from $mg_c where reservation_companion_id = '$mg_comp' and tenant_id = '$mg_tenant_b' returning 1) select count(*) from gone")"
check 'AC-D12.15 a delete scoped to another tenant removes nothing' "$([ "$(printf '%s\n' "$mg_other" | tail -1)" = 0 ] && [ "$(mg_sql "select count(*) from $mg_c where reservation_companion_id = '$mg_comp'")" = 1 ]; echo $?)"
mg_same="$(mg_sql "set role $writer; with gone as (delete from $mg_c where reservation_companion_id = '$mg_comp' and tenant_id = '$tenant' returning 1) select count(*) from gone")"
check 'AC-D12.15 a delete scoped to its own tenant removes the companion' "$([ "$(printf '%s\n' "$mg_same" | tail -1)" = 1 ] && [ "$(mg_sql "select count(*) from $mg_c where reservation_companion_id = '$mg_comp'")" = 0 ]; echo $?)"

echo 'theGrantsAreIdempotentAndTheRevertRestoresTheSnapshot'
mg_second="$(liquibase update 2>&1)"; printf '%s\n' "$mg_second"
check 'AC-D12.16 a second update applies zero changesets' "$(printf '%s\n' "$mg_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
sql "delete from $mg_fd where reservation_id = '$mg_res'; delete from $SCHEMA.reservation where reservation_id = '$mg_res'" >/dev/null 2>&1 || true
liquibase rollback-count 2
mg_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$mg_base" "$mg_reverted"
check 'AC-D12.16 the revert restores columns, constraints, indexes and privileges exactly and leaves 128 changesets' "$([ -n "$mg_base" ] && [ "$mg_reverted" = "$mg_base" ] && [ "$(sql "select count(*) from $CONTROL")" = 128 ]; echo $?)"
check 'AC-D12.16 after the revert the writer cannot update an amount column nor delete a companion' "$([ "$(mg_can_update "$writer" base_cents)" = f ] && [ "$(mg_sql "select has_table_privilege('$writer', '$mg_c', 'DELETE')")" = f ]; echo $?)"
db_labels=''
liquibase update >/dev/null
liquibase rollback-count 999 >/dev/null
liquibase update >/dev/null
liquibase validate >/dev/null
check 'a full build from empty without any label filter applies every changeset of the repository' "$([ "$(sql "select count(*) from $CONTROL")" = $all_changesets ]; echo $?)"
