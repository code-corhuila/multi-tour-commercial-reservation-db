#!/usr/bin/env bash
# Sourced by db-ci.sh after client-notice-delivery-checks.sh, on the same disposable PostgreSQL instance.
# HU-COM-015 -db (issue multi-tour-docs#181), plan D-05 and D-06, slice (c): the partial index of the relay's read of pending events
# (idx_outbox_event_pending_delivery, changeset ddl-indexes-037, labels HU-COM-015, client-notice-delivery and client-notice-relay-index) and the proof
# that a notice is never read across tenants. Probes are written first: red before the changeset, green after (Annex J.1).
rl_ob="$SCHEMA.outbox_event"; rl_tenant_b="00000000-0000-0000-0000-000000000002"
rl_cust="$(aid 4401)"; rl_cust_b="$(aid 4402)"; rl_svc="$(aid 4403)"; rl_res="$(aid 4410)"; rl_res_b="$(aid 4412)"
rl_ea="$(aid 4421)"; rl_eb="$(aid 4422)"
rl_sql() { sql "$1" 2>/dev/null || true; }
rl_read() { # tenant, event id: the read of one notice by tenant and event id, as the content route does
  echo "select count(*) from $rl_ob where tenant_id = '$1' and outbox_event_id = '$2' and event_type = 'ClientNotified'"
}

echo 'HU-COM-015 relay - base: the 127 changesets that exist before the relay index'
liquibase rollback-count 999 >/dev/null
db_labels='!client-notice-relay-index and !HU-COM-017 and !HU-COM-019 and !HU-COM-018 and !HU-COM-020 and !decision-resume and !episode-frozen-total and !departure-order and !exceptional-access-use and !reservation-confirmed-value and !payment-parameters-changed and !account-session-cutoff and !restricted-access-reason and !rescheduling-proposed-notice'
liquibase update >/dev/null
rl_base="$(snapshot)"
check 'base holds exactly 127 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 127 ]; echo $?)"
sql "insert into $SCHEMA.customer (customer_id, tenant_id, full_name, created_at, document_number, birth_date_or_age, contact_info, status, terms_accepted, terms_accepted_at) values ('$rl_cust', '$tenant', 'Relay probe A', now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE', true, now()), ('$rl_cust_b', '$rl_tenant_b', 'Relay probe B', now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE', true, now());
     insert into $SCHEMA.catalog_service (service_id, tenant_id, service_type, commercial_name, catalog_status, base_rate_cents, base_operational_cost_cents, configured_capacity, transport_required, high_risk, created_at, updated_at) values ('$rl_svc', '$tenant', 'TOUR', 'Relay probe tour', 'ACTIVE', 150000, 90000, 12, false, false, now(), now())" >/dev/null 2>&1 || true
engine "$(rs_row reservation_id "'$rl_res'" customer_id "'$rl_cust'" service_id "'$rl_svc'"); $(rs_row reservation_id "'$rl_res_b'" tenant_id "'$rl_tenant_b'" customer_id "'$rl_cust_b'" service_id "'$rl_svc'");" >/dev/null || true
# one million published notices, then a few pending ones; the volume is loaded by the owner of the table, as a purge job would
sql "insert into $rl_ob (outbox_event_id, tenant_id, event_type, reservation_id, actor_id, occurred_at, published_at, payload)
     select gen_random_uuid(), '$tenant', 'ClientNotified', '$rl_res', '$actor', now() - interval '2 days' + (g * interval '1 millisecond'), now() - interval '1 day',
            jsonb_build_object('customerId', '$rl_cust', 'notificationType', 'PROOF_APPROVED', 'triggeringEventType', 'PaymentValidated', 'triggeringEventId', 'bulk-' || g)
     from generate_series(1, 1000000) g" >/dev/null 2>&1 || true
check 'the base holds one million published notices' "$([ "$(rl_sql "select count(*) from $rl_ob where published_at is not null")" = 1000000 ]; echo $?)"
sql "insert into $rl_ob (outbox_event_id, tenant_id, event_type, reservation_id, actor_id, occurred_at, payload) values
       ('$rl_ea', '$tenant', 'ClientNotified', '$rl_res', '$actor', now(), jsonb_build_object('customerId', '$rl_cust', 'notificationType', 'PROOF_APPROVED', 'triggeringEventType', 'PaymentValidated', 'triggeringEventId', 'pending-a')),
       ('$rl_eb', '$rl_tenant_b', 'ClientNotified', '$rl_res_b', '$actor', now(), jsonb_build_object('customerId', '$rl_cust_b', 'notificationType', 'PROOF_REJECTED', 'triggeringEventType', 'PaymentRejected', 'triggeringEventId', 'pending-b'))" >/dev/null 2>&1 || true
# a backlog of fifty thousand notices waiting for their next attempt: the relay must read the first hundred in order without sorting them all
sql "insert into $rl_ob (outbox_event_id, tenant_id, event_type, reservation_id, actor_id, occurred_at, attempts, next_attempt_at, payload)
     select gen_random_uuid(), '$tenant', 'ClientNotified', '$rl_res', '$actor', now() - interval '1 hour' + (g * interval '1 millisecond'), 1, now() + (g * interval '1 second'),
            jsonb_build_object('customerId', '$rl_cust', 'notificationType', 'PROOF_APPROVED', 'triggeringEventType', 'PaymentValidated', 'triggeringEventId', 'backlog-' || g)
     from generate_series(1, 50000) g" >/dev/null 2>&1 || true
check 'fifty thousand and two pending notices exist, two of them never tried' "$([ "$(rl_sql "select count(*) from $rl_ob where published_at is null")" = 50002 ]; echo $?)"

echo 'HU-COM-015 relay - probes written first: red before the changeset, green after'
db_labels='client-notice-relay-index'
liquibase update >/dev/null
check 'the one changeset brings the control table to 128' "$([ "$(sql "select count(*) from $CONTROL")" = 128 ]; echo $?)"
sql "analyze $rl_ob" >/dev/null 2>&1 || true

echo 'thePendingReadUsesThePartialIndex (AC-D15.10)'
check 'AC-D15.10 idx_outbox_event_pending_delivery is a valid partial index on (next_attempt_at NULLS FIRST, occurred_at) for unpublished and unfailed rows' "$([ "$(rl_sql "select count(*) from pg_index i join pg_class c on c.oid = i.indexrelid where c.relname = 'idx_outbox_event_pending_delivery' and i.indisvalid and not i.indisunique")" = 1 ] && [ "$(rl_sql "select count(*) from pg_indexes where schemaname='$SCHEMA' and indexname='idx_outbox_event_pending_delivery' and indexdef like '%next_attempt_at NULLS FIRST, occurred_at%' and indexdef like '%published_at IS NULL%' and indexdef like '%failed_at IS NULL%'")" = 1 ]; echo $?)"
rl_plan="$(printf '%s\n' "explain select outbox_event_id from $rl_ob where published_at is null and failed_at is null and (next_attempt_at is null or next_attempt_at <= now()) order by next_attempt_at nulls first, occurred_at limit 100;" | docker exec -i -e PGPASSWORD "$container" psql -X -U postgres -d postgres 2>&1 || true)"
printf '%s\n' "$rl_plan"
check 'AC-D15.10 the read of the relay with one million published rows behind it uses the partial index and does not scan or sort the table' "$(printf '%s\n' "$rl_plan" | grep -q 'idx_outbox_event_pending_delivery' && ! printf '%s\n' "$rl_plan" | grep -Eq 'Seq Scan|Sort'; echo $?)"
check 'AC-D15.10 the index stays small: it holds the pending rows only, a few MB against the million published' "$([ "$(rl_sql "select pg_relation_size('$SCHEMA.idx_outbox_event_pending_delivery') < 8000000")" = t ]; echo $?)"

echo 'aNoticeOfOneTenantIsNeverReadByAnother (AC-D15.11)'
check 'AC-D15.11 a notice read with its own tenant and id is returned' "$([ "$(rl_sql "$(rl_read "$tenant" "$rl_ea")")" = 1 ] && [ "$(rl_sql "$(rl_read "$rl_tenant_b" "$rl_eb")")" = 1 ]; echo $?)"
check 'AC-D15.11 a notice of tenant A asked with the tenant B is not returned, and the other way round' "$([ "$(rl_sql "$(rl_read "$rl_tenant_b" "$rl_ea")")" = 0 ] && [ "$(rl_sql "$(rl_read "$tenant" "$rl_eb")")" = 0 ]; echo $?)"

echo 'secondRunAppliesZeroAndTheRevertRestoresTheSchema (AC-D15.12, AC-D15.13)'
rl_second="$(liquibase update 2>&1)"; printf '%s\n' "$rl_second"
check 'AC-D15.12 a second update applies zero changesets' "$(printf '%s\n' "$rl_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
sql "delete from $rl_ob where event_type = 'ClientNotified' and published_at is not null; delete from $rl_ob where event_type = 'ClientNotified'; delete from $SCHEMA.reservation where reservation_id in ('$rl_res','$rl_res_b'); delete from $SCHEMA.catalog_service where service_id = '$rl_svc'; delete from $SCHEMA.customer where customer_id in ('$rl_cust','$rl_cust_b')" >/dev/null 2>&1 || true
check 'the notices of the probes are gone before the revert' "$([ "$(sql "select count(*) from $rl_ob")" = 0 ]; echo $?)"
liquibase rollback-count 1
rl_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$rl_base" "$rl_reverted"
check 'AC-D15.13 the one-change revert restores columns, constraints, indexes and privileges exactly and leaves 127 changesets' "$([ -n "$rl_base" ] && [ "$rl_reverted" = "$rl_base" ] && [ "$(sql "select count(*) from $CONTROL")" = 127 ]; echo $?)"
db_labels='client-notice-relay-index'
liquibase update >/dev/null
check 'AC-D15.13 the changeset reapplies to 128 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 128 ]; echo $?)"
