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

`deploy/compose.yml` holds only the migration runner, `commercial-reservation-db-migrate`. The
PostgreSQL instance is not here: it is defined by `multi-tour-infra-postgres`, whose root compose
file includes this one (clone both as siblings) and provides the `postgres` service the runner waits
for. From that repository, with its environment file:

```bash
docker compose --profile tooling run --rm commercial-reservation-db-migrate
```

The runner reads `PG_DATABASE`, `PG_ADMIN_USER` and `PG_ADMIN_PASSWORD` (listed in `.env.example`, all required,
none with a default). The user needs permission to create the schema and the roles. The runner also
needs the application user `commercial_reservation_app` and the `pgcrypto` extension to exist: the
infrastructure creates both (Annex J.7). `db-ci.yml` creates them in its throwaway database, which
needs only Docker. `.env` is never versioned.

## Where its data is

Schema `commercial_reservation` in the platform instance, with its own control table,
`databasechangelog_commercial_reservation`. Nothing of this domain lives in `public`. The logical
model is in `06-data/models.md` of `multi-tour-docs`.

## How to test

```bash
bash tests/check-structure.sh      # the tree, the master changelog and the common files
```

```bash
bash tests/db-ci.sh                # the four steps plus the roles, the tables and compose.yml; needs Docker
```

`db-ci.yml` builds everything from an empty PostgreSQL, applies it a second time (zero changesets),
rolls it all back to an empty database and builds it again (Annex A).

## What is missing

The catalog table (T-08), the reconstruction record (T-09) and the capacity entity (T-10). The
runner has been run only against the throwaway database of `db-ci.yml`, not yet against the
instance composed by `multi-tour-infra-postgres`.

## Branching

`develop` receives `feat/…` branches; `qa` receives `qa/…` by `git cherry-pick -x`; `main` receives
`release/…` with the teacher's approval. No permanent branch accepts a direct commit. Policy:
`00-governance/git-conventions.md` in `multi-tour-docs`.
