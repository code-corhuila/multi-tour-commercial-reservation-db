#!/usr/bin/env bash
# Sourced by db-ci.sh after the discount-rule codes checks, on the same disposable PostgreSQL instance.
# HU-COM-004 -db, "Closing decisions (2026-10-28)" (issue multi-tour-docs#170): ONE widening of outbox_event
# for ReservationModified (HU-COM-004), CustomerRegistered and SensitiveDataAccessed (HU-COM-005).
# Changeset ddl-alter-010, label outbox-widening. reservation_id has no foreign key (the reservations table
# is HU-COM-007); customer_id references customer. The payload carries no sensitive data.
ow_table="$SCHEMA.outbox_event"
ow_customer="$(aid 1601)"
ow_payload="'{\"reason\":\"x\"}'::jsonb"
ow_event() { # type, aggregate column, aggregate value, actor, payload, previous catalog status, new catalog status (SQL literals; empty = default)
  local payload="${5:-$ow_payload}"
  echo "insert into $ow_table (tenant_id, event_type, ${2:-reservation_id}, previous_catalog_status, new_catalog_status, actor_id, occurred_at, payload) values ('$tenant', ${1:-'ReservationModified'}, ${3:-'$(aid 1611)'}, ${6:-NULL}, ${7:-NULL}, ${4:-'$actor'}, now(), $payload)"
}
ow_refusal() { # SQL, text of the engine answer, description
  local answer
  answer="$(engine "$1" 2>&1 || true)"; printf '%s\n' "$answer"
  check "HU-COM-004 outbox: $3 is refused by $2" "$(printf '%s\n' "$answer" | grep -q "$2"; echo $?)"
}
ow_accepted() { # SQL, description
  local status=0
  engine "begin; $1; rollback;" || status=$?
  check "HU-COM-004 outbox: $2 is accepted" "$status"
}
ow_catalog() { # actor literal, payload column and value (optional): a catalog event as it was before
  echo "insert into $ow_table (tenant_id, event_type, service_id, previous_catalog_status, new_catalog_status, actor_id, occurred_at${2:+, payload}) values ('$tenant', 'CatalogServiceInactivated', '$(aid 1621)', 'ACTIVE', 'INACTIVE', $1, now()${2:+, $2})"
}

echo 'HU-COM-004 outbox - base: the 40 changesets before the HU-COM-004 additions'
liquibase rollback-count 999 >/dev/null
db_labels='!outbox-widening and !authorizable-reason and !additional-discount-immutable and !HU-COM-006 and !customer-terms and !HU-WRK-007 and !HU-COM-007 and !HU-COM-008 and !HU-COM-009 and !HU-COM-010'
liquibase update >/dev/null
ow_base="$(snapshot)"
check 'base holds exactly 40 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 40 ]; echo $?)"
sql "insert into $SCHEMA.customer (customer_id, tenant_id, full_name, created_at, document_number, birth_date_or_age, contact_info, status) values ('$ow_customer', '$tenant', 'Outbox probe', now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE')" >/dev/null 2>&1 || true
sql "insert into $SCHEMA.catalog_service (service_id, tenant_id, service_type, commercial_name, catalog_status, base_rate_cents, base_operational_cost_cents, configured_capacity, transport_required, high_risk, created_at, updated_at) values ('$(aid 1621)', '$tenant', 'TOUR', 'Outbox probe', 'ACTIVE', 1, 1, 1, false, false, now(), now())" >/dev/null 2>&1 || true

echo 'HU-COM-004 outbox - probes written first: red before the changeset, green after'
db_labels='outbox-widening'
liquibase update >/dev/null
check 'ddl-alter-010 brings the control table to 41 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 41 ]; echo $?)"
check 'outbox_event gains reservation_id uuid NULL, customer_id uuid NULL and payload jsonb NULL' "$([ "$(sql "select string_agg(column_name || ' ' || data_type || ' ' || is_nullable, ',' order by column_name) from information_schema.columns where table_schema='$SCHEMA' and table_name='outbox_event' and column_name in ('reservation_id','customer_id','payload')")" = 'customer_id uuid YES,payload jsonb YES,reservation_id uuid YES' ]; echo $?)"
check 'customer_id has fk_outbox_event_customer ON DELETE RESTRICT and reservation_id has no foreign key (HU-COM-007)' "$([ "$(sql "select count(*) from pg_constraint where conrelid=to_regclass('$ow_table') and contype='f' and conname='fk_outbox_event_customer' and confdeltype='r' and confrelid=to_regclass('$SCHEMA.customer')")" = 1 ] && [ "$(sql "select count(*) from pg_constraint where conrelid=to_regclass('$ow_table') and contype='f' and pg_get_constraintdef(oid) like '%reservation_id%'")" = 0 ]; echo $?)"
check 'actor_id, service_id and the two catalog status columns are nullable' "$([ "$(sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='outbox_event' and column_name in ('actor_id','previous_catalog_status','new_catalog_status','service_id') and is_nullable='NO'")" = 0 ]; echo $?)"

echo 'the three new events'
ow_accepted "$(ow_event)" 'ReservationModified with its reservation, actor and payload'
ow_accepted "$(ow_event "'CustomerRegistered'" customer_id "'$ow_customer'" NULL)" 'CustomerRegistered with its customer and no actor'
ow_accepted "$(ow_event "'SensitiveDataAccessed'" customer_id "'$ow_customer'")" 'SensitiveDataAccessed with customer and actor'
ow_refusal "$(ow_event "'ReservationModified'" reservation_id NULL);" chk_outbox_event_exactly_one_aggregate 'ReservationModified without an aggregate'
ow_refusal "$(ow_event "'ReservationModified'" customer_id "'$ow_customer'");" chk_outbox_event_exactly_one_aggregate 'ReservationModified pointing at a customer'
ow_refusal "$(ow_event "'CustomerRegistered'" reservation_id "'$(aid 1611)'");" chk_outbox_event_exactly_one_aggregate 'CustomerRegistered pointing at a reservation'
ow_refusal "$(ow_event "'SensitiveDataAccessed'" reservation_id "'$(aid 1611)'");" chk_outbox_event_exactly_one_aggregate 'SensitiveDataAccessed pointing at a reservation'
ow_refusal "insert into $ow_table (tenant_id, event_type, reservation_id, customer_id, actor_id, occurred_at, payload) values ('$tenant', 'ReservationModified', '$(aid 1611)', '$ow_customer', '$actor', now(), '{}'::jsonb);" chk_outbox_event_exactly_one_aggregate 'two aggregates at once'
ow_refusal "$(ow_event "'ReservationModified'" reservation_id "'$(aid 1611)'" '' '' "'ACTIVE'" "'INACTIVE'");" chk_outbox_event_exactly_one_aggregate 'a catalog status on a reservation event'
ow_refusal "$(ow_event "'ReservationModified'" reservation_id "'$(aid 1611)'" NULL);" chk_outbox_event_actor_required 'ReservationModified without actor'
ow_refusal "$(ow_event "'SensitiveDataAccessed'" customer_id "'$ow_customer'" NULL);" chk_outbox_event_actor_required 'SensitiveDataAccessed without actor'
ow_refusal "$(ow_event "'CustomerRegistered'" customer_id "'$(aid 1699)'" NULL);" fk_outbox_event_customer 'CustomerRegistered for a customer that does not exist'
ow_refusal "$(ow_event "'ReservationCancelled'");" chk_outbox_event_event_type 'an event outside the decided list'

echo 'payload: present for the new events, absent for the old ones, no sensitive keys'
ow_refusal "$(ow_event "'ReservationModified'" reservation_id "'$(aid 1611)'" '' NULL);" chk_outbox_event_payload 'a new event without payload'
ow_refusal "$(ow_event "'ReservationModified'" reservation_id "'$(aid 1611)'" '' "'[1]'::jsonb");" chk_outbox_event_payload 'a payload that is not an object'
ow_refusal "$(ow_event "'SensitiveDataAccessed'" customer_id "'$ow_customer'" '' "'{\"medicalInformation\":\"x\"}'::jsonb");" chk_outbox_event_payload_no_sensitive_keys 'a payload with a medical key'
ow_refusal "$(ow_event "'CustomerRegistered'" customer_id "'$ow_customer'" NULL "'{\"document_number\":\"1\"}'::jsonb");" chk_outbox_event_payload_no_sensitive_keys 'a payload with a document key'
ow_refusal "$(ow_catalog "'$actor'" "'{}'::jsonb");" chk_outbox_event_payload 'a payload on a catalog event'
ow_accepted "$(ow_catalog "'$actor'")" 'a catalog event as before'
ow_refusal "$(ow_catalog NULL);" chk_outbox_event_actor_required 'a catalog event without actor'

echo 'DELETE stays the technical privilege of the outbox; idempotence, protected rollback, exact revert and reapply'
check 'the application user keeps DELETE on outbox_event (relay purge, ADR-004 D10)' "$([ "$(sql "select has_table_privilege('$app','$ow_table','DELETE')")" = t ]; echo $?)"
ow_second="$(liquibase update 2>&1)"; printf '%s\n' "$ow_second"
check 'a second update applies zero changesets' "$(printf '%s\n' "$ow_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
engine "insert into $ow_table (tenant_id, event_type, customer_id, actor_id, occurred_at, payload) values ('$tenant', 'CustomerRegistered', '$ow_customer', NULL, now(), '{}'::jsonb);" >/dev/null || true
ow_protected="$(liquibase rollback-count 1 2>&1 || true)"; printf '%s\n' "$ow_protected"
check 'the rollback refuses while events of the new types remain' "$(printf '%s\n' "$ow_protected" | grep -q 'Cannot revert outbox widening while'; echo $?)"
check 'the refused rollback keeps the event and the 41 changesets' "$([ "$(sql "select count(*) from $ow_table where event_type='CustomerRegistered'")" = 1 ] && [ "$(sql "select count(*) from $CONTROL")" = 41 ]; echo $?)"
engine "delete from $ow_table where event_type in ('ReservationModified','CustomerRegistered','SensitiveDataAccessed');" >/dev/null || true
liquibase rollback-count 1
ow_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$ow_base" "$ow_reverted"
check 'the revert restores columns, constraints, indexes and privileges exactly' "$([ -n "$ow_base" ] && [ "$ow_reverted" = "$ow_base" ] && [ "$(sql "select count(*) from $CONTROL")" = 40 ]; echo $?)"
liquibase update >/dev/null
check 'the widening reapplies to 41 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 41 ]; echo $?)"
