# Changelog

All notable changes of `multi-tour-commercial-reservation-db` (Commercial and Reservations schema (Liquibase)) are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [3.0.0] - 2026-11-14

Cut 3 release. Every entry below is a pull request merged into `qa` and re-applied to `release/3.0.0` with `git cherry-pick -x`; the heading of each group is the user story named in the pull request, and the entry is the title of the pull request without its type. The frozen head of `qa` is `b04e0ea7d058816fdcbdf05e9f858649ff774ab4`.

### Added

#### HU-COM-006 - Browse the offer from the digital channel

- The vehicle total of a departure on the capacity row ([PR 134](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/134))

#### HU-COM-013 - Cancel a reservation at the customer's request

- The cancellation penalty policy table of HU-COM-013 ([PR 123](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/123))

#### HU-COM-015 - Notify the Final Customer

- The rescheduling proposal notice trigger code ([PR 121](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/121))

### Changed

#### HU-COM-001 - Manage the operational catalog

- Hu-com-001 catalog schema ([PR 7](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/7))

#### HU-COM-002 - Manage associated establishments

- Hu-com-002 associated establishments and outbox ([PR 10](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/10))
- The establishment contact and change log ([PR 119](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/119))

#### HU-COM-003 - Manage discount rules

- The discount rule table and its outbox events ([PR 12](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/12))
- The index changeset fix ([PR 14](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/14))
- The fix of the discount rule checks ([PR 16](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/16))
- The discount rule codes and audit columns ([PR 30](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/30))
- The stackable flag of the discount rule ([PR 84](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/84))

#### HU-COM-004 - View and apply current discounts

- The reservation additional discount table ([PR 27](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/27))
- The outbox widening and authorizable reasons ([PR 31](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/31))

#### HU-COM-005 - Register the lead customer and companions

- The customer and companion tables ([PR 26](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/26))
- The customer columns and sensitive tables ([PR 28](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/28))

#### HU-COM-006 - Browse the offer from the digital channel

- The last event marker of the departure mirror ([PR 101](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/101))

#### HU-COM-007 - Create a reservation and calculate its value

- The reservation tables and the fixed discount lines ([PR 78](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/78))
- The reservation outbox, the customer key and the payment attempt ([PR 79](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/79))

#### HU-COM-008 - Reserve from the digital channel

- The db CI record of HU-COM-008 ([PR 91](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/91))

#### HU-COM-009 - Register a payment or a partial payment

- The capacity allocation and the payment parameters ([PR 80](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/80))
- The PaymentParametersChanged event of the outbox ([PR 111](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/111))

#### HU-COM-010 - Validate or reject a payment proof

- The payment proof review, the customer search and the transport rate ([PR 81](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/81))
- The proof id in the payment review events ([PR 97](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/97))

#### HU-COM-011 - Manage the reservations pending payment

- The payment follow-up schema ([PR 83](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/83))

#### HU-COM-012 - Modify a reservation before execution

- The reservation modification schema ([PR 87](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/87))
- The amount rewrite of the discount lines ([PR 93](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/93))

#### HU-COM-013 - Cancel a reservation at the customer's request

- The cancellation settlement ([PR 85](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/85))

#### HU-COM-014 - Consult my reservations and my supports

- The consultation read probes ([PR 86](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/86))
- The tenant B seeds of the consultation probe ([PR 133](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/133))

#### HU-COM-015 - Notify the Final Customer

- The ClientNotified notice in the outbox ([PR 88](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/88))
- The outbox delivery columns and the relay read index ([PR 92](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/92))

#### HU-COM-016 - Authorize and execute a refund

- The financial decision and refund authorization tables ([PR 89](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/89))
- The guards, indexes and outbox of the refund tables ([PR 90](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/90))
- The db-ci probe exclusion chains after HU-COM-016 ([PR 139](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/139))

#### HU-COM-017 - Record and apply a credit balance

- The credit balance tables ([PR 94](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/94))
- The credit balance guards and events ([PR 95](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/95))

#### HU-COM-018 - Reschedule an affected reservation

- The rescheduling episode and proposal tables ([PR 98](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/98))
- The rescheduling record and its outbox event ([PR 99](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/99))

#### HU-COM-019 - Delete sensitive data one year after the service

- The sensitive data deletion record ([PR 96](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/96))

#### HU-COM-020 - Handle the obligations of an inactive tenant

- The tenant suspension history and the resumed decision due ([PR 100](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/100))
- The accumulated frozen total of the rescheduling episode ([PR 105](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/105))
- The envelope reason of the restricted action outbox ([PR 116](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/116))

#### HU-CSH-003 - Consult the monthly report and the cash consolidation

- The commercial value key of ReservationConfirmed ([PR 109](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/109))

#### HU-SEC-005 - Manage the tenant's internal users

- The account session cutoff table of commercial reservation ([PR 113](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/113))

#### HU-SEC-007 - Exceptional and emergency access of the Platform Administrator

- The exceptional access use event of the outbox ([PR 104](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/104))
- The usedAt of the exceptional access event ([PR 107](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/107))

#### HU-WRK-007 - Relay events between domains

- The tenant status copy table ([PR 57](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/57))

#### Cross-cutting: CI, test fixes and alignment promotions (no single story is named in the PR title, branch or body)

- Close the DP-03 limitation message in the T-06 step ([PR 35](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/35))
- Add the departure state, processed events and the offer indexes ([PR 36](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/36))
- Store the terms acceptance of the customer ([PR 37](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/37))
- The db-ci timeout of the complete suite ([PR 126](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/126))
- The exact changeset counts of the older probes ([PR 132](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/132))
- The probe exclusion of the vehicle total slice ([PR 135](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/135))
- The checks on pull requests to main ([PR 137](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/137))
- Run the test workflow only on pull requests to develop and qa ([PR 141](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/141))

### Fixed

#### HU-COM-011 - Manage the reservations pending payment

- The tenant composite foreign keys ([PR 131](https://github.com/code-corhuila/multi-tour-commercial-reservation-db/pull/131))

[Unreleased]: https://github.com/code-corhuila/multi-tour-commercial-reservation-db/compare/v3.0.0...HEAD
[3.0.0]: https://github.com/code-corhuila/multi-tour-commercial-reservation-db/releases/tag/v3.0.0
