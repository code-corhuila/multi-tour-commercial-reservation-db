#!/usr/bin/env bash
# Sourced by db-ci.sh after the transport-rate checks, on the same disposable PostgreSQL instance.
# HU-COM-011 -db (issue multi-tour-docs#177), plan D-02 to D-06: the append-only follow-up table, the extension and freeze columns of
# payment_deadline, the due and history indexes. Eleven changesets in all, every one labelled HU-COM-011 (the second file of probes,
# reservation-cancellation-checks.sh, covers the cancellation columns, the outbox key list and the revert). Probes are written first:
# red before the changesets, green after (Annex J.1).
fu_t="$SCHEMA.payment_followup"; fu_dl="$SCHEMA.payment_deadline"; fu_ob="$SCHEMA.outbox_event"
fu_tenant_b="00000000-0000-0000-0000-000000000002"
fu_cust="$(aid 3101)"; fu_cust_b="$(aid 3102)"; fu_svc="$(aid 3103)"
fu_res1="$(aid 3110)"; fu_res2="$(aid 3111)"; fu_res_b="$(aid 3112)"
fu_dl1="$(aid 3120)"; fu_dl_bal="$(aid 3121)"; fu_dl2="$(aid 3122)"
fu_sql() { sql "$1" 2>/dev/null || true; }
fu_refusal() { # SQL, text of the engine answer, description
  local answer
  answer="$(engine "$1" 2>&1 || true)"; printf '%s\n' "$answer"
  check "HU-COM-011 db: $3 is refused by $2" "$(printf '%s\n' "$answer" | grep -q "$2"; echo $?)"
}
fu_accepted() { # SQL, description
  local status=0
  engine "$1" >/dev/null || status=$?
  check "HU-COM-011 db: $2 is accepted" "$status"
}
fu_followup() { # column/value pairs (SQL literals) that replace the defaults of a valid follow-up of the first reservation
  local -A v=([payment_followup_id]="gen_random_uuid()" [tenant_id]="'$tenant'" [reservation_id]="'$fu_res1'" [contacted_by]="'$actor'" [contacted_at]="now()" [note]="'The customer will pay on Friday'")
  while [ $# -ge 2 ]; do v[$1]="$2"; shift 2; done
  echo "insert into $fu_t (payment_followup_id, tenant_id, reservation_id, contacted_by, contacted_at, note) values (${v[payment_followup_id]}, ${v[tenant_id]}, ${v[reservation_id]}, ${v[contacted_by]}, ${v[contacted_at]}, ${v[note]})"
}
fu_deadline() { # column/value pairs (SQL literals) that replace the defaults of an initial deadline
  local -A v=([payment_deadline_id]="gen_random_uuid()" [tenant_id]="'$tenant'" [reservation_id]="'$fu_res1'" [deadline_kind]="'INITIAL_PAYMENT'" [due_at]="now() + interval '24 hours'")
  while [ $# -ge 2 ]; do v[$1]="$2"; shift 2; done
  echo "insert into $fu_dl (payment_deadline_id, tenant_id, reservation_id, deadline_kind, due_at) values (${v[payment_deadline_id]}, ${v[tenant_id]}, ${v[reservation_id]}, ${v[deadline_kind]}, ${v[due_at]})"
}
fu_ext() { # deadline id, hours, granted at, granted by (SQL literals)
  echo "update $fu_dl set extension_hours = $2, extension_granted_at = $3, extension_granted_by = $4 where payment_deadline_id = '$1'"
}
fu_explain() { printf '%s\n' 'set enable_seqscan = off;' "explain $1;" | docker exec -i -e PGPASSWORD "$container" psql -X -U postgres -d postgres 2>&1 || true; }

echo 'HU-COM-011 db - base: the 87 changesets that exist before the story'
liquibase rollback-count 999 >/dev/null
db_labels='!HU-COM-011 and !discount-rule-stackable and !HU-COM-013 and !HU-COM-012'
liquibase update >/dev/null
fu_base="$(snapshot)"
fu_base_objects="$(sql "select (select count(*) from pg_tables where schemaname='$SCHEMA') || '|' || (select count(*) from pg_proc where pronamespace='$SCHEMA'::regnamespace) || '|' || (select count(*) from pg_trigger where not tgisinternal and tgrelid in (select oid from pg_class where relnamespace='$SCHEMA'::regnamespace))" 2>/dev/null || true)"
check 'base holds exactly 87 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 87 ]; echo $?)"
sql "insert into $SCHEMA.customer (customer_id, tenant_id, full_name, created_at, document_number, birth_date_or_age, contact_info, status, terms_accepted, terms_accepted_at) values ('$fu_cust', '$tenant', 'Follow-up probe A', now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE', true, now()), ('$fu_cust_b', '$fu_tenant_b', 'Follow-up probe B', now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE', true, now());
     insert into $SCHEMA.catalog_service (service_id, tenant_id, service_type, commercial_name, catalog_status, base_rate_cents, base_operational_cost_cents, configured_capacity, transport_required, high_risk, created_at, updated_at) values ('$fu_svc', '$tenant', 'TOUR', 'Follow-up probe tour', 'ACTIVE', 150000, 90000, 12, false, false, now(), now())" >/dev/null 2>&1 || true
engine "$(rs_row reservation_id "'$fu_res1'" customer_id "'$fu_cust'" service_id "'$fu_svc'"); $(rs_row reservation_id "'$fu_res2'" customer_id "'$fu_cust'" service_id "'$fu_svc'"); $(rs_row reservation_id "'$fu_res_b'" tenant_id "'$fu_tenant_b'" customer_id "'$fu_cust_b'" service_id "'$fu_svc'");" >/dev/null || true
engine "$(fu_deadline payment_deadline_id "'$fu_dl1'"); $(fu_deadline payment_deadline_id "'$fu_dl_bal'" deadline_kind "'BALANCE'"); $(fu_deadline payment_deadline_id "'$fu_dl2'" reservation_id "'$fu_res2'");" >/dev/null || true
check 'the probe reservations and deadlines exist on the base' "$([ "$(fu_sql "select count(*) from $SCHEMA.reservation where reservation_id in ('$fu_res1','$fu_res2','$fu_res_b')")" = 3 ] && [ "$(fu_sql "select count(*) from $fu_dl where payment_deadline_id in ('$fu_dl1','$fu_dl_bal','$fu_dl2')")" = 3 ]; echo $?)"

echo 'HU-COM-011 db - probes written first: red before the changesets, green after'
db_labels='HU-COM-011'
liquibase update >/dev/null
check 'the eleven changesets of the story bring the control table to 98' "$([ "$(sql "select count(*) from $CONTROL")" = 98 ]; echo $?)"

echo 'followupRequiresReservationAuthorTimeAndNote (AC-D11.2)'
fu_refusal "$(fu_followup reservation_id NULL);" 'null value in column "reservation_id".*not-null constraint' 'a follow-up without reservation'
fu_refusal "$(fu_followup tenant_id NULL);" 'null value in column "tenant_id".*not-null constraint' 'a follow-up without tenant'
fu_refusal "$(fu_followup contacted_by NULL);" 'null value in column "contacted_by".*not-null constraint' 'a follow-up without author'
fu_refusal "$(fu_followup contacted_at NULL);" 'null value in column "contacted_at".*not-null constraint' 'a follow-up without time'
fu_refusal "$(fu_followup note NULL);" 'null value in column "note".*not-null constraint' 'a follow-up without note'
fu_refusal "$(fu_followup note "'   '");" chk_payment_followup_note 'a follow-up with a blank note'
fu_refusal "$(fu_followup reservation_id "'$(aid 3199)'");" fk_payment_followup_reservation 'a follow-up of a reservation that does not exist'
fu_f1="$(aid 3130)"
fu_accepted "$(fu_followup payment_followup_id "'$fu_f1'")" 'a complete follow-up'
check 'AC-D11.2 no column of payment_followup has a DEFAULT' "$([ "$(fu_sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='payment_followup' and column_default is not null")" = 0 ]; echo $?)"

echo 'followupCannotBeUpdatedOrDeleted (AC-D11.3)'
fu_refusal "update $fu_t set note = 'edited' where payment_followup_id = '$fu_f1';" 'permission denied for table payment_followup' 'an UPDATE of a follow-up as the application user'
fu_refusal "delete from $fu_t where payment_followup_id = '$fu_f1';" 'permission denied for table payment_followup' 'a DELETE of a follow-up as the application user'
check 'AC-D11.3 the writer and the application user hold SELECT and INSERT on the follow-up, not UPDATE or DELETE; the reader reads' "$([ "$(sql "select has_table_privilege('$writer','$fu_t','SELECT') and has_table_privilege('$writer','$fu_t','INSERT') and has_table_privilege('$app','$fu_t','INSERT') and not has_table_privilege('$writer','$fu_t','UPDATE') and not has_table_privilege('$app','$fu_t','UPDATE') and not has_table_privilege('$writer','$fu_t','DELETE') and not has_table_privilege('$app','$fu_t','DELETE') and has_table_privilege('$reader','$fu_t','SELECT')")" = t ]; echo $?)"

echo 'extensionIsWholeBoundedAndOnlyOnTheInitialKind (AC-D11.4)'
fu_refusal "update $fu_dl set extension_hours = 24 where payment_deadline_id = '$fu_dl1';" chk_payment_deadline_extension_complete 'an extension with only its duration'
fu_refusal "update $fu_dl set extension_granted_at = now() where payment_deadline_id = '$fu_dl1';" chk_payment_deadline_extension_complete 'an extension with only its instant'
fu_refusal "update $fu_dl set extension_granted_by = '$actor' where payment_deadline_id = '$fu_dl1';" chk_payment_deadline_extension_complete 'an extension with only its grantor'
fu_refusal "$(fu_ext "$fu_dl1" 0 'now()' "'$actor'");" chk_payment_deadline_extension_hours 'an extension of zero hours'
fu_refusal "$(fu_ext "$fu_dl1" 721 'now()' "'$actor'");" chk_payment_deadline_extension_hours 'an extension of 721 hours'
fu_refusal "$(fu_ext "$fu_dl_bal" 24 'now()' "'$actor'");" chk_payment_deadline_extension_kind 'an extension on a balance deadline'
fu_accepted "$(fu_ext "$fu_dl1" 24 'now()' "'$actor'")" 'a whole extension of 24 hours on the initial deadline'

echo 'anExtensionCannotBeChangedOrWrittenTwice (AC-D11.5)'
fu_refusal "$(fu_ext "$fu_dl1" 48 'now()' "'$actor'");" trg_payment_deadline_extension_guard 'a second extension on the same deadline'
fu_refusal "$(fu_ext "$fu_dl1" 24 "now() + interval '1 hour'" "'$actor'");" trg_payment_deadline_extension_guard 'the extension instant rewritten'
fu_refusal "$(fu_ext "$fu_dl1" NULL NULL NULL);" trg_payment_deadline_extension_guard 'the extension cleared'
fu_accepted "update $fu_dl set due_at = due_at + interval '1 hour' where payment_deadline_id = '$fu_dl1'" 'an update that leaves the extension as it is'

echo 'aFreezeNeedsBothColumnsAndANonNegativeRemaining (AC-D11.6)'
fu_refusal "update $fu_dl set frozen_at = now() where payment_deadline_id = '$fu_dl2';" chk_payment_deadline_freeze_complete 'a freeze without the remaining time'
fu_refusal "update $fu_dl set remaining_at_freeze_minutes = 60 where payment_deadline_id = '$fu_dl2';" chk_payment_deadline_freeze_complete 'a remaining time without the freeze instant'
fu_refusal "update $fu_dl set frozen_at = now(), remaining_at_freeze_minutes = -1 where payment_deadline_id = '$fu_dl2';" chk_payment_deadline_remaining 'a negative remaining time'
fu_accepted "update $fu_dl set frozen_at = now(), remaining_at_freeze_minutes = 90 where payment_deadline_id = '$fu_dl2'" 'a freeze with both columns'
fu_accepted "update $fu_dl set frozen_at = NULL, remaining_at_freeze_minutes = NULL where payment_deadline_id = '$fu_dl2'" 'a resume that clears both columns'

echo 'followupsAndDueDeadlinesNeverCrossTenants (AC-D11.9)'
engine "$(fu_followup reservation_id "'$fu_res_b'" tenant_id "'$fu_tenant_b'" note "'Tenant B call'");" >/dev/null || true
engine "$(fu_deadline reservation_id "'$fu_res_b'" tenant_id "'$fu_tenant_b'" due_at "now() - interval '1 hour'");" >/dev/null || true
check 'AC-D11.9 the history of tenant A holds one row and never the row of tenant B' "$([ "$(fu_sql "select count(*) from $fu_t where tenant_id='$tenant'")" = 1 ] && [ "$(fu_sql "select count(*) from $fu_t where tenant_id='$tenant' and note='Tenant B call'")" = 0 ]; echo $?)"
check 'AC-D11.9 the due list of tenant A never carries the deadline of tenant B, which is already due' "$([ "$(fu_sql "select count(*) from $fu_dl where tenant_id='$tenant' and reservation_id='$fu_res_b'")" = 0 ] && [ "$(fu_sql "select count(*) from $fu_dl where tenant_id='$fu_tenant_b' and due_at < now() and frozen_at is null")" = 1 ]; echo $?)"

echo 'dueListAndHistoryUseTheirIndexes (AC-D11.10)'
sql "insert into $fu_t (payment_followup_id, tenant_id, reservation_id, contacted_by, contacted_at, note) select gen_random_uuid(), '$tenant', '$fu_res1', '$actor', now() - (n || ' minutes')::interval, 'Bulk call ' || n from generate_series(1, 3000) n;
     insert into $fu_dl (payment_deadline_id, tenant_id, reservation_id, deadline_kind, due_at, frozen_at, remaining_at_freeze_minutes) select gen_random_uuid(), '$tenant', '$fu_res1', 'PENDING_DIFFERENCE', now() + (n || ' minutes')::interval, case when n % 10 = 0 then now() end, case when n % 10 = 0 then 30 end from generate_series(1, 3000) n;
     analyze $fu_t; analyze $fu_dl" >/dev/null 2>&1 || true
fu_plan_h="$(fu_explain "select * from $fu_t where tenant_id='$tenant' and reservation_id='$fu_res1' order by contacted_at desc limit 20")"; printf '%s\n' "$fu_plan_h"
check 'AC-D11.10 the history of one reservation uses idx_payment_followup_tenant_reservation_contacted_at' "$(printf '%s\n' "$fu_plan_h" | grep -q 'idx_payment_followup_tenant_reservation_contacted_at'; echo $?)"
fu_plan_d="$(fu_explain "select * from $fu_dl where tenant_id='$tenant' and frozen_at is null and due_at <= now() + interval '1 day' order by due_at limit 100")"; printf '%s\n' "$fu_plan_d"
check 'AC-D11.10 the due list of the job uses idx_payment_deadline_tenant_due_at' "$(printf '%s\n' "$fu_plan_d" | grep -q 'idx_payment_deadline_tenant_due_at'; echo $?)"
check 'AC-D11.10 both indexes lead with tenant_id and the due one is partial on frozen_at IS NULL' "$([ "$(fu_sql "select count(*) from pg_indexes where schemaname='$SCHEMA' and ((indexname='idx_payment_followup_tenant_reservation_contacted_at' and indexdef like '%(tenant_id, reservation_id, contacted_at DESC)%') or (indexname='idx_payment_deadline_tenant_due_at' and indexdef like '%(tenant_id, due_at) WHERE (frozen_at IS NULL)%'))")" = 2 ]; echo $?)"

echo 'theSameKeyTwiceIsRefusedPerTenant (AC-D11.12)'
fu_key() { echo "insert into $SCHEMA.idempotency_key (key, tenant_id, resource_type, resource_id) values ('$1', '$2', 'payment_followup', '$fu_f1')"; }
fu_accepted "$(fu_key followup-key-1 "$tenant")" 'a follow-up key'
fu_refusal "$(fu_key followup-key-1 "$tenant");" pk_idempotency_key 'the same key twice in one tenant'
fu_accepted "$(fu_key followup-key-1 "$fu_tenant_b")" 'the same key in another tenant'
