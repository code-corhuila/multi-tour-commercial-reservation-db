#!/usr/bin/env bash
# Sourced by db-ci.sh after the HU-COM-004 traceability checks, on the same disposable PostgreSQL instance.
# HU-COM-005 -db (spec 005-hu-com-005-register-the-lead-customer-and-companions): T-10 for the one search that is decided.
# The name search of a tenant is served by idx_customer_tenant_full_name on (tenant_id, lower(full_name) text_pattern_ops)
# (10_indexes/025, labels HU-COM-005 and customer-name-search; plan D-12, PROPUESTO). Built CONCURRENTLY as the only statement of its
# changeset and outside a transaction, so writes to customer are not blocked (norm 5.2.7).
# NOT built, because the documents leave it open (DP-D5-2, DP-D5-3): the document search (keyed hash) and the e-mail search
# (normalized e-mail), so no EXPLAIN probe exists for them. Probes are written first: red before the changeset, green after (Annex J.1).
cs_cust="$SCHEMA.customer"; cs_tenant_b="00000000-0000-0000-0000-000000000002"
cs_sql() { sql "$1" 2>/dev/null || true; }
cs_explain_plain() { printf '%s\n' "explain $1;" | docker exec -i -e PGPASSWORD "$container" psql -X -U postgres -d postgres 2>&1 || true; }

echo 'HU-COM-005 customer name search - base: the 85 changesets before the index'
liquibase rollback-count 999 >/dev/null
db_labels='!customer-name-search and !transport-rate and !HU-COM-011 and !discount-rule-stackable and !HU-COM-013 and !HU-COM-012 and !HU-COM-015 and !HU-COM-016'
liquibase update >/dev/null
cs_base="$(snapshot)"
check 'base holds exactly 85 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 85 ]; echo $?)"
check 'on that base the name index does not exist' "$([ "$(cs_sql "select count(*) from pg_indexes where schemaname='$SCHEMA' and indexname='idx_customer_tenant_full_name'")" = 0 ]; echo $?)"

echo 'HU-COM-005 customer name search - probes written first: red before the changeset, green after'
db_labels='customer-name-search'
liquibase update >/dev/null
check 'the name index brings the control table to 86 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 86 ]; echo $?)"

echo 'theNameSearchOfATenantUsesItsIndex (AC-D5.11, T-10)'
check 'AC-D5.11 idx_customer_tenant_full_name is on (tenant_id, lower(full_name) text_pattern_ops), valid, and not unique' "$([ "$(cs_sql "select indexdef from pg_indexes where schemaname='$SCHEMA' and indexname='idx_customer_tenant_full_name'")" = "CREATE INDEX idx_customer_tenant_full_name ON $SCHEMA.customer USING btree (tenant_id, lower(full_name) text_pattern_ops)" ] && [ "$(cs_sql "select indisvalid and not indisunique from pg_index where indexrelid='$SCHEMA.idx_customer_tenant_full_name'::regclass")" = t ]; echo $?)"
sql "insert into $cs_cust (customer_id, tenant_id, full_name, created_at, document_number, birth_date_or_age, contact_info, status, terms_accepted, terms_accepted_at)
     select gen_random_uuid(), t, case when n <= 6 then 'Zelda Search ' || n else 'Customer ' || n end, now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE', true, now()
     from unnest(array['$tenant', '$cs_tenant_b']::uuid[]) t, generate_series(1, 3000) n; analyze $cs_cust" >/dev/null 2>&1 || true
check 'AC-D5.11 there are enough customers for the planner to choose from (6000, two tenants)' "$([ "$(cs_sql "select count(*) from $cs_cust")" = 6000 ]; echo $?)"
cs_plan="$(cs_explain_plain "select customer_id, full_name from $cs_cust where tenant_id='$tenant' and lower(full_name) like 'zelda%' order by lower(full_name)")"; printf '%s\n' "$cs_plan"
check 'AC-D5.11 the prefix search by name inside a tenant uses idx_customer_tenant_full_name without disabling sequential scans' "$(printf '%s\n' "$cs_plan" | grep -q 'idx_customer_tenant_full_name'; echo $?)"
check 'AC-D5.5 the same search scoped to tenant A returns its six customers and never a row of tenant B' "$([ "$(cs_sql "select count(*) from $cs_cust where tenant_id='$tenant' and lower(full_name) like 'zelda%'")" = 6 ] && [ "$(cs_sql "select count(*) from $cs_cust where tenant_id='$tenant' and lower(full_name) like 'zelda%' and tenant_id <> '$tenant'")" = 0 ]; echo $?)"
check 'RNF-D5 the index changeset is one CONCURRENTLY statement outside a transaction (runInTransaction false)' "$([ "$(awk '/id: ddl-indexes-025/{f=1} f&&/runInTransaction: false/{n++;f=0} END{print n+0}' 01_ddl/10_indexes/changelog.yaml)" = 1 ] && [ "$(grep -cE '^CREATE INDEX CONCURRENTLY' 01_ddl/10_indexes/025_create_customer_name_search_index.sql)" = 1 ]; echo $?)"
check 'AC-D5.11 the document and e-mail searches have no index yet: their decision is open (DP-D5-2, DP-D5-3)' "$([ "$(cs_sql "select count(*) from pg_indexes where schemaname='$SCHEMA' and tablename='customer' and (indexname like '%document%' or indexname like '%email%')")" = 0 ]; echo $?)"

echo 'theIndexRevertsAndReapplies (AC-D5.13)'
sql "delete from $cs_cust" >/dev/null 2>&1 || true
check 'the rows of the probes are gone before the revert' "$([ "$(sql "select count(*) from $cs_cust")" = 0 ]; echo $?)"
liquibase rollback-count 1
cs_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$cs_base" "$cs_reverted"
check 'AC-D5.13 the revert removes the index and leaves columns, constraints, indexes and privileges as the base had them' "$([ -n "$cs_base" ] && [ "$cs_reverted" = "$cs_base" ] && [ "$(sql "select count(*) from $CONTROL")" = 85 ]; echo $?)"
db_labels=''
liquibase update >/dev/null
check 'the changeset reapplies to 126 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 126 ]; echo $?)"
liquibase rollback-count 999 >/dev/null
liquibase update >/dev/null
liquibase validate >/dev/null
check 'a full build from empty without any label filter applies exactly 126 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 126 ]; echo $?)"
