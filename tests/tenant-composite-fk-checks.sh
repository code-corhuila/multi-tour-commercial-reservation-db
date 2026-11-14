#!/usr/bin/env bash
# Sourced by db-ci.sh after rescheduling-proposed-notice-checks.sh, on the same disposable PostgreSQL instance, with every changeset that exists before the slice (counted at run time); the slice is three changesets, 049, 050 and 060 (the indexes).
# DD-11 of the HU-COM-011 db spec and DD-7 / DP-D9-12 of the HU-COM-009 db spec: the foreign keys between tables that both carry tenant_id did not include it, so the engine admitted a child of one tenant that points at the
# parent of another. 049 adds UNIQUE (tenant_id, key) to the ten referenced parents and 050 makes the 48 keys composite, with the same names (NOT VALID, then VALIDATE); 060 gives each key an index that starts with tenant_id and the column unless one exists. No column, row or grant changes.
# The probes run as the superuser, so the foreign key triggers fire exactly as for the application. The changesets are labelled fk-tenant-composite. Probes are written first: red before the changesets, green after (Annex J.1).
tk_ta="$tenant"; tk_tb="00000000-0000-0000-0000-000000000002"
tk_cust_a="$(aid 9501)"; tk_cust_b="$(aid 9502)"; tk_svc_a="$(aid 9503)"; tk_svc_b="$(aid 9504)"; tk_res_a="$(aid 9511)"; tk_res_b="$(aid 9512)"; tk_bad="$(aid 9521)"
tk_sql() { sql "$1" 2>/dev/null || true; }
# A foreign key between two tables that both have tenant_id, whose columns leave tenant_id out: the hole of DD-11.
tk_gap_sql="select count(*) from pg_constraint c where c.contype = 'f' and c.connamespace = '$SCHEMA'::regnamespace
  and exists (select 1 from pg_attribute a where a.attrelid = c.conrelid and a.attname = 'tenant_id' and not a.attisdropped)
  and exists (select 1 from pg_attribute a where a.attrelid = c.confrelid and a.attname = 'tenant_id' and not a.attisdropped)
  and not exists (select 1 from pg_attribute a where a.attrelid = c.conrelid and a.attname = 'tenant_id' and a.attnum = any (c.conkey))"
# A foreign key of a tenant-scoped table that no full index serves: one that starts with tenant_id and the first key column that is not tenant_id.
tk_unindexed_sql="select count(*) from pg_constraint c, lateral (select attnum as t from pg_attribute where attrelid = c.conrelid and attname = 'tenant_id' and not attisdropped) ct
  where c.contype = 'f' and c.connamespace = '$SCHEMA'::regnamespace
  and exists (select 1 from pg_attribute a where a.attrelid = c.confrelid and a.attname = 'tenant_id' and not a.attisdropped)
  and exists (select 1 from unnest(c.conkey) k where k <> ct.t)
  and not exists (select 1 from pg_index i where i.indrelid = c.conrelid and i.indpred is null and i.indexprs is null and i.indkey[0] = ct.t
    and i.indkey[1] = (select k from unnest(c.conkey) with ordinality u(k, o) where k <> ct.t order by o limit 1))"
tk_index_names() { tk_sql "select coalesce(string_agg(indexrelid::regclass::text, ',' order by indexrelid::regclass::text), '') from pg_index where indrelid in (select oid from pg_class where relnamespace = '$SCHEMA'::regnamespace)"; }
tk_customer() { echo "insert into $SCHEMA.customer (customer_id, tenant_id, full_name, created_at, document_number, birth_date_or_age, contact_info, status, terms_accepted, terms_accepted_at) values ('$1', '$2', 'Tenant key probe', now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE', true, now())"; }
tk_service() { echo "insert into $SCHEMA.catalog_service (service_id, tenant_id, service_type, commercial_name, catalog_status, base_rate_cents, base_operational_cost_cents, configured_capacity, transport_required, high_risk, created_at, updated_at) values ('$1', '$2', 'TOUR', 'Tenant key probe tour', 'ACTIVE', 150000, 90000, 12, false, false, now(), now())"; }
tk_reservation() { # reservation id, tenant, customer, service
  echo "insert into $SCHEMA.reservation (reservation_id, tenant_id, customer_id, salida_id, service_id, party_size, projected_value_cents, final_value_cents, pending_balance_cents, credit_balance_cents, reservation_status, payment_status, payment_type, payment_method, created_by, created_at) values ('$1', '$2', '$3', gen_random_uuid(), '$4', 2, 300000, 270000, 270000, 0, 'PENDING_PAYMENT', 'NO_PAYMENT', 'DEPOSIT', 'TRANSFER', '$actor', now())"; }
tk_followup() { # tenant, reservation, optional id (a SQL literal)
  echo "insert into $SCHEMA.payment_followup (payment_followup_id, tenant_id, reservation_id, contacted_by, contacted_at, note) values (${3:-gen_random_uuid()}, '$1', '$2', '$actor', now(), 'The customer will pay on Friday')"; }
tk_deadline() { echo "insert into $SCHEMA.payment_deadline (payment_deadline_id, tenant_id, reservation_id, deadline_kind, due_at) values (gen_random_uuid(), '$1', '$2', 'INITIAL_PAYMENT', now() + interval '24 hours')"; }
tk_attempt() { echo "insert into $SCHEMA.payment_attempt (payment_attempt_id, tenant_id, reservation_id, payment_method, received_amount_cents, validation_status, payment_status_snapshot, registered_by, registered_at) values (gen_random_uuid(), '$1', '$2', 'TRANSFER', 100000, 'IN_VALIDATION', 'NO_PAYMENT', '$actor', now())"; }
tk_refusal() { # SQL, text of the engine answer, description
  local answer
  answer="$(engine "begin; $1; rollback;" postgres 2>&1 || true)"; printf '%s\n' "$answer"
  check "DD-11 db: $3 is refused by $2" "$(printf '%s\n' "$answer" | grep -q "violates foreign key constraint \"$2\""; echo $?)"
}
tk_accepted() { # SQL, description
  local status=0
  engine "begin; $1; rollback;" postgres >/dev/null || status=$?
  check "DD-11 db: $2 is accepted" "$status"
}

echo 'DD-11 db tenant composite keys - base: every changeset that exists before the slice'
liquibase rollback-count 999 >/dev/null
db_labels='!fk-tenant-composite and !vehicle-total-capacity'
liquibase update >/dev/null
tk_base="$(snapshot)"
tk_n0="$(sql "select count(*) from $CONTROL")"
check "the base holds every changeset except the three of the slice ($tk_n0)" "$([ "$tk_n0" -gt 0 ] && [ "$(sql "select count(*) from $CONTROL where labels ilike '%fk-tenant-composite%'")" = 0 ]; echo $?)"
tk_fks0="$(tk_sql "select count(*) from pg_constraint where contype = 'f' and connamespace = '$SCHEMA'::regnamespace")"
sql "$(tk_customer "$tk_cust_a" "$tk_ta"); $(tk_customer "$tk_cust_b" "$tk_tb"); $(tk_service "$tk_svc_a" "$tk_ta"); $(tk_service "$tk_svc_b" "$tk_tb");
     $(tk_reservation "$tk_res_a" "$tk_ta" "$tk_cust_a" "$tk_svc_a"); $(tk_reservation "$tk_res_b" "$tk_tb" "$tk_cust_b" "$tk_svc_b")" >/dev/null 2>&1 || true
check 'the probe parents exist on the base: two customers, two tours, one reservation of each tenant' "$([ "$(tk_sql "select count(*) from $SCHEMA.reservation where reservation_id in ('$tk_res_a','$tk_res_b')")" = 2 ]; echo $?)"
# the five rows of the hole: a child of one tenant that points at the parent of another
tk_cross_followup="$(tk_followup "$tk_tb" "$tk_res_a")"; tk_cross_deadline="$(tk_deadline "$tk_tb" "$tk_res_a")"; tk_cross_attempt="$(tk_attempt "$tk_tb" "$tk_res_a")"
tk_cross_res_customer="$(tk_reservation "$(aid 9531)" "$tk_tb" "$tk_cust_a" "$tk_svc_b")"; tk_cross_res_service="$(tk_reservation "$(aid 9532)" "$tk_tb" "$tk_cust_b" "$tk_svc_a")"
echo 'theHoleOfDD11OnTheBase: a child of one tenant that points at the parent of another is accepted'
tk_accepted "$tk_cross_followup" 'on the base, a follow-up of tenant B on the reservation of tenant A (the hole)'
tk_accepted "$tk_cross_deadline" 'on the base, a deadline of tenant B on the reservation of tenant A (the hole)'
tk_accepted "$tk_cross_attempt" 'on the base, a payment attempt of tenant B on the reservation of tenant A (the hole)'
tk_accepted "$tk_cross_res_customer" 'on the base, a reservation of tenant B for the customer of tenant A (the hole)'
tk_accepted "$tk_cross_res_service" 'on the base, a reservation of tenant B for the tour of tenant A (the hole)'
tk_gap0="$(tk_sql "$tk_gap_sql")"
tk_unindexed0="$(tk_sql "$tk_unindexed_sql")"; tk_idx_base="$(tk_index_names)"
check "on the base, 33 foreign keys have no index that starts with tenant_id and the key column ($tk_unindexed0)" "$([ "$tk_unindexed0" = 33 ]; echo $?)"
check "the inventory of the hole on the base is the 48 foreign keys of the schema that leave tenant_id out ($tk_gap0)" "$([ "$tk_gap0" = 48 ]; echo $?)"

echo 'aRowThatAlreadyCrossesTenantsStopsTheChangesetAndIsNeverDeleted'
engine "$(tk_followup "$tk_tb" "$tk_res_a" "'$tk_bad'");" postgres >/dev/null || true
db_labels='fk-tenant-composite'
tk_stopped_status=0; tk_stopped="$(liquibase update 2>&1)" || tk_stopped_status=$?
printf '%s\n' "$tk_stopped" | tail -12
check 'the update stops with an error' "$([ "$tk_stopped_status" -ne 0 ]; echo $?)"
check 'the error names the key that the stored row breaks' "$(printf '%s\n' "$tk_stopped" | grep -q 'fk_payment_followup_reservation'; echo $?)"
check 'the stored row is still there: the changeset never deletes or rewrites data' "$([ "$(tk_sql "select count(*) from $SCHEMA.payment_followup where payment_followup_id = '$tk_bad'")" = 1 ]; echo $?)"
check 'the failed changeset left no key half built: the gap is as on the base' "$([ "$(tk_sql "$tk_gap_sql")" = "$tk_gap0" ]; echo $?)"
sql "delete from $SCHEMA.payment_followup where payment_followup_id = '$tk_bad'" >/dev/null 2>&1 || true
db_labels='fk-tenant-composite'
liquibase update >/dev/null
check 'once the owner has removed the row, the three changesets of the slice apply (049, 050, 060)' "$([ "$(sql "select count(*) from $CONTROL")" = "$((tk_n0 + 3))" ]; echo $?)"

echo 'theEngineRefusesAChildOfAnotherTenant (DD-11, DD-7, DP-D9-12)'
tk_refusal "$tk_cross_followup" 'fk_payment_followup_reservation' 'a follow-up of tenant B on the reservation of tenant A'
tk_refusal "$tk_cross_deadline" 'fk_payment_deadline_reservation' 'a deadline of tenant B on the reservation of tenant A'
tk_refusal "$tk_cross_attempt" 'fk_payment_attempt_reservation' 'a payment attempt of tenant B on the reservation of tenant A'
tk_refusal "$tk_cross_res_customer" 'fk_reservation_customer' 'a reservation of tenant B for the customer of tenant A'
tk_refusal "$tk_cross_res_service" 'fk_reservation_service' 'a reservation of tenant B for the tour of tenant A'
echo 'theSameTenantStillWorks'
tk_accepted "$(tk_followup "$tk_ta" "$tk_res_a")" 'a follow-up of tenant A on the reservation of tenant A'
tk_accepted "$(tk_deadline "$tk_tb" "$tk_res_b")" 'a deadline of tenant B on the reservation of tenant B'
tk_accepted "$(tk_attempt "$tk_ta" "$tk_res_a")" 'a payment attempt of tenant A on the reservation of tenant A'
tk_accepted "$(tk_reservation "$(aid 9533)" "$tk_tb" "$tk_cust_b" "$tk_svc_b")" 'a reservation of tenant B for the customer and the tour of tenant B'
tk_refusal "$(tk_followup "$tk_ta" "$(aid 9599)")" 'fk_payment_followup_reservation' 'a follow-up of a reservation that does not exist (the orphan stays refused)'

echo 'noKeyOfTheSchemaLeavesTenantOut'
check 'no foreign key between two tenant-scoped tables leaves tenant_id out' "$([ "$(tk_sql "$tk_gap_sql")" = 0 ]; echo $?)"
check 'the schema has the same number of foreign keys as the base (none lost, none added)' "$([ "$(tk_sql "select count(*) from pg_constraint where contype = 'f' and connamespace = '$SCHEMA'::regnamespace")" = "$tk_fks0" ]; echo $?)"
check 'every foreign key of the schema is validated' "$([ "$(tk_sql "select count(*) from pg_constraint where contype = 'f' and connamespace = '$SCHEMA'::regnamespace and not convalidated")" = 0 ]; echo $?)"
tk_parents="'$SCHEMA.customer','$SCHEMA.catalog_service','$SCHEMA.discount_rule','$SCHEMA.reservation','$SCHEMA.reservation_companion','$SCHEMA.payment_attempt','$SCHEMA.financial_decision','$SCHEMA.credit_balance','$SCHEMA.rescheduling_episode','$SCHEMA.associated_establishment'"
check 'the ten referenced parents carry UNIQUE (tenant_id, key) with tenant_id first' "$([ "$(tk_sql "select count(*) from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1] where c.contype = 'u' and c.conname like 'uq\_%\_tenant\_id\_%' and cardinality(c.conkey) = 2 and a.attname = 'tenant_id' and c.conrelid::regclass::text in ($tk_parents)")" = 10 ]; echo $?)"
check 'every foreign key of a tenant-scoped table has a full index that starts with tenant_id and its key column' "$([ "$(tk_sql "$tk_unindexed_sql")" = 0 ]; echo $?)"
tk_new_sql="from pg_index i where (select relname from pg_class where oid = i.indexrelid) like 'idx\_%' and i.indexrelid::regclass::text <> all (string_to_array('$tk_idx_base', ',')) and i.indrelid in (select oid from pg_class where relnamespace = '$SCHEMA'::regnamespace)"
check 'the slice adds exactly 33 indexes' "$([ "$(tk_sql "select count(*) $tk_new_sql")" = 33 ]; echo $?)"
check 'none of the new indexes duplicates an existing one (no other full index starts with the same two columns)' "$([ "$(tk_sql "select count(*) $tk_new_sql and exists (select 1 from pg_index j where j.indrelid = i.indrelid and j.indexrelid <> i.indexrelid and j.indpred is null and j.indexprs is null and j.indkey[0] = i.indkey[0] and j.indkey[1] = i.indkey[1])")" = 0 ]; echo $?)"

echo 'onlyTheKeysChangeSecondRunAppliesZeroAndRevertLeavesNoTrace'
check 'nothing new appears in public' "$([ "$(sql "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p','v','m','S','f') and c.relname not like 'databasecha%'")" = 0 ]; echo $?)"
tk_second="$(liquibase update 2>&1)"; printf '%s\n' "$tk_second"
check 'a second update applies zero changesets' "$(printf '%s\n' "$tk_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
tk_n="$(sql "select count(*) from $CONTROL where labels ilike '%fk-tenant-composite%'" 2>/dev/null || echo 0)"
liquibase rollback-count "$tk_n"
tk_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$tk_base" "$tk_reverted"
check 'the revert restores columns, constraints, indexes and privileges exactly and leaves the base changesets' "$([ -n "$tk_base" ] && [ "$tk_reverted" = "$tk_base" ] && [ "$(sql "select count(*) from $CONTROL")" = "$tk_n0" ]; echo $?)"
check 'after the revert the 48 keys are simple again and the 33 indexes are gone (the gap and the unindexed keys are back)' "$([ "$(tk_sql "$tk_gap_sql")" = "$tk_gap0" ] && [ "$(tk_sql "$tk_unindexed_sql")" = "$tk_unindexed0" ]; echo $?)"
db_labels='fk-tenant-composite'
liquibase update >/dev/null
check 'the three changesets of the slice reapply' "$([ "$(sql "select count(*) from $CONTROL")" = "$((tk_n0 + 3))" ]; echo $?)"
