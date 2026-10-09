# multi-tour-commercial-reservation-db

Migrations of the schema `commercial_reservation` of the Commercial and Reservations macrodomain
(Multitour), written with Liquibase for the single PostgreSQL instance of the platform.

## What it is

The owner of the structure of this domain's data: schema, tables, constraints, roles and their
grants, one migration per change, each with its reversal. It starts with **HU-COM-001, manage the
operational catalog** (`code-corhuila/multi-tour-docs#167`).

It is **not** the database instance, its volume, its extensions or its users: those belong to
`multi-tour-infra-postgres` (Annex J). It is not the API, and it holds no application code.

## How to start

The migration runner is added by task T-05 (`deploy/compose.yml`). Until then the migrations are
built and checked by `db-ci.yml`, which needs only Docker. Copy `.env.example` to `.env` and fill
it in; `.env` is never versioned.

## Where its data is

Schema `commercial_reservation` in the platform instance, with its own control table,
`databasechangelog_commercial_reservation`. Nothing of this domain lives in `public`. The logical
model is in `06-data/models.md` of `multi-tour-docs`.

## How to test

```bash
bash tests/check-structure.sh      # the tree, the master changelog and the common files
```

`db-ci.yml` builds everything from an empty PostgreSQL, applies it a second time (zero changesets),
rolls it all back to an empty database and builds it again (Annex A).

## What is missing

Everything beyond the tree: `db-ci.yml` (T-02), the schema (T-03), the control table (T-04), the
runner (T-05), roles and grants (T-06), idempotency and outbox tables (T-07), the catalog table
(T-08), the reconstruction record (T-09) and the capacity entity (T-10).

## Branching

`develop` receives `feat/…` branches; `qa` receives `qa/…` by `git cherry-pick -x`; `main` receives
`release/…` with the teacher's approval. No permanent branch accepts a direct commit. Policy:
`00-governance/git-conventions.md` in `multi-tour-docs`.
