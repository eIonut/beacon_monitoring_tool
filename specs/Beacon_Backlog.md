# Beacon backlog

66 tickets in 7 milestones, written against `Beacon_Project_Spec.md` v2.0.
Section numbers and requirement IDs (FR, SEC, FE) refer to that spec.

## How to work the board

1. Take the lowest-numbered ticket whose dependencies are done.
2. Branch `bcn-<number>-<short-name>`, open a pull request, let CI pass, merge.
3. A ticket is done when every acceptance box is ticked, not when the code runs once.
4. Estimates are focused hours without help from an AI coding tool.

## Size, honestly

| Milestone                       | Tickets | Estimate    |
| ------------------------------- | ------- | ----------- |
| M0 Setup                        | 4       | 6 h         |
| M1 Checker and database         | 9       | 19 h        |
| M2 Kafka and rollups            | 8       | 17.5 h      |
| M3 Incidents and alerts         | 10      | 24.5 h      |
| M4 API, dashboard, first deploy | 17      | 49.5 h      |
| M5 Settings and status page     | 8       | 20 h        |
| M6 Hardening and presentation   | 10      | 22 h        |
| **Total**                       | **66**  | **158.5 h** |

Priority `P1` means needed for a working, demoable product. `P2` can wait until
after you start applying. P1 alone is about 142 hours.

---

## M0 Setup

### BCN-01 Create the repository skeleton

`P1` · 1 h · Depends on: none
Go module, the folder layout from spec section 16, a Makefile with empty `up`, `down`, `test`, `lint` targets, `.env.example`, README stub.

- [x] `go build ./...` succeeds with three empty `cmd/` programs
- [x] `.gitignore` excludes `.env`

### BCN-02 PostgreSQL and migrations in Docker Compose

`P1` · 2 h · Depends on: BCN-01
Compose file with `postgres` and a one-shot `migrate` service running goose.

- [x] `make up` starts PostgreSQL with a health check
- [x] `make migrate` applies an empty first migration and is safe to run twice

### BCN-03 Continuous integration for Go

`P1` · 1.5 h · Depends on: BCN-01
GitHub Actions workflow: build, `go vet`, linter, tests, on every push and pull request.

- [ ] A failing test fails the workflow
- [ ] Workflow finishes in under five minutes

### BCN-04 Fake target server

`P1` · 1.5 h · Depends on: BCN-01
`scripts/fake-target`: a tiny HTTP server whose status code and delay you can change at runtime (for example `POST /_control {"status":503,"delay_ms":0}`).

- [ ] Runs as a Compose service
- [ ] Switching to 503 and back takes effect on the next request
- [ ] Can simulate a timeout and a redirect

---

## M1 Checker and database

### BCN-05 Schema: users, monitors, monitor_state

`P1` · 1.5 h · Depends on: BCN-02
Migration with the three tables and indexes from spec section 7. A `monitor_state` row is created whenever a monitor is.

- [ ] Constraints reject an interval of 45 and a timeout of 0
- [ ] Deleting a monitor deletes its state row

### BCN-06 Seed data

`P1` · 0.5 h · Depends on: BCN-05
`scripts/seed.sql`: one user, one monitor on the fake target, one on gabrielenache.com. `make seed`.

- [ ] Running the seed twice does not duplicate rows

### BCN-07 Address validation

`P1` · 3 h · Depends on: BCN-01 · SEC-1, SEC-2, FR-5
Package `internal/check`: accept only http and https, ports 80 and 443, and public addresses.

- [ ] Table tests cover loopback, private, link-local, carrier-grade NAT, multicast, unspecified, IPv6 and IPv4-mapped IPv6
- [ ] `http://169.254.169.254` and `http://[::1]` are rejected

### BCN-08 Safe dialer and redirect policy

`P1` · 3 h · Depends on: BCN-07 · SEC-1, FR-11
Validate inside the dialer and connect to the validated address. Follow at most 5 redirects, validating each hop.

- [ ] A redirect from the fake target to `127.0.0.1` is refused with `blocked_address`
- [ ] A sixth redirect yields `too_many_redirects`

### BCN-09 One check

`P1` · 3 h · Depends on: BCN-08 · FR-9, FR-10, SEC-3, SEC-4
The function from spec section 8.2: timeout, 64 KB cap, `response_ms`, error classification, one immediate retry.

- [ ] Each `error` value in spec section 6 is produced by a test
- [ ] A failed-then-ok check reports ok with `attempts: 2`

### BCN-10 Scheduler claim loop

`P1` · 2 h · Depends on: BCN-05 · FR-8
The SQL from spec section 8.1, run every second.

- [ ] A monitor is claimed once per interval
- [ ] After the checker has been stopped for ten minutes, each monitor is checked once, not ten times

### BCN-11 Worker pool with per-host limit

`P1` · 2.5 h · Depends on: BCN-09
Bounded pool (default 50) and at most 2 concurrent checks per host.

- [ ] 100 monitors on one slow host never exceed 2 in flight
- [ ] A full queue slows the scheduler; nothing is dropped

### BCN-12 Checker program

`P1` · 2 h · Depends on: BCN-10, BCN-11
`cmd/checker`: configuration from environment, JSON logs, graceful shutdown, results logged.

- [ ] `make up` logs one result per seeded monitor per interval
- [ ] SIGTERM lets in-flight checks finish, then exits within 10 s

### BCN-13 Two checkers, no double checks

`P2` · 1.5 h · Depends on: BCN-12
Test with two checker containers.

- [ ] Over five minutes no monitor is checked twice within one interval

---

## M2 Kafka and rollups

### BCN-14 Kafka in Docker Compose

`P1` · 2 h · Depends on: BCN-02
One broker in KRaft mode, auto-create off, a `kafka-init` service that creates the topics in spec section 6.

- [ ] `make up` creates all six topics with the listed partitions
- [ ] The broker has a health check that other services wait on

### BCN-15 Event types and producer helper

`P1` · 2 h · Depends on: BCN-14
`internal/events`: Go types for the three payloads, JSON encoding with `schema_version`, a producer with idempotence and `acks=all`.

- [ ] Encoding then decoding returns the same value for every type
- [ ] An unknown `schema_version` is rejected by the decoder

### BCN-16 Checker publishes results

`P1` · 2 h · Depends on: BCN-12, BCN-15 · FR-12
Publish one `check.results` event per check, keyed by `monitor_id`.

- [ ] Events for one monitor always land on one partition
- [ ] With Kafka stopped, the checker keeps scheduling and counts dropped results

### BCN-17 Consumer helper

`P1` · 3 h · Depends on: BCN-15
Shared loop: manual commit after the handler succeeds, skip and count unparseable messages, graceful shutdown.

- [ ] A handler error leaves the offset uncommitted
- [ ] A malformed message is skipped and the next one is processed

### BCN-18 Schema: rollups and processed events

`P1` · 1 h · Depends on: BCN-05
Migration for `rollups_minute`, `rollups_day`, `processed_events`.

- [ ] Primary keys match spec section 7

### BCN-19 Rollup writer

`P1` · 3 h · Depends on: BCN-17, BCN-18
Consumer `beacon.rollup`, steps from spec section 8.3.

- [ ] `sum_ms` and `max_ms` count successful checks only
- [ ] The same event delivered twice changes the tables once

### BCN-20 Integration test harness

`P1` · 3 h · Depends on: BCN-17
Tests start real Kafka and PostgreSQL in containers and tear them down.

- [ ] One command runs the integration tests locally and in CI

### BCN-21 Replay test

`P2` · 1.5 h · Depends on: BCN-19, BCN-20
Reset the `beacon.rollup` group to the start and replay.

- [ ] Table contents are identical before and after

---

## M3 Incidents and alerts

### BCN-22 Schema: incidents, outbox, channels, notifications

`P1` · 1 h · Depends on: BCN-05
Migration from spec section 7, including the partial unique index for one open incident.

- [ ] Inserting a second open incident for a monitor fails

### BCN-23 Incident state machine

`P1` · 3 h · Depends on: BCN-01 · FR-13 to FR-16
A pure function: current state plus event gives new state plus actions. Table from spec section 8.4.

- [ ] Every row of the table has a test
- [ ] Threshold 1 opens on the first failure
- [ ] `started_at` is the first failed check, not the one that crossed the threshold

### BCN-24 Incident detector

`P1` · 3 h · Depends on: BCN-17, BCN-22, BCN-23
Consumer `beacon.incident`: row lock on `monitor_state`, apply the machine, write incident and outbox row in one transaction.

- [ ] Stale and duplicate events are ignored
- [ ] Events for a paused or deleted monitor are skipped

### BCN-25 Outbox relay

`P1` · 2.5 h · Depends on: BCN-22, BCN-15
Loop from spec section 8.5.

- [ ] Rows are published in `id` order and marked only after the broker acknowledges
- [ ] Killing the relay mid-batch loses nothing

### BCN-26 Alert message templates

`P1` · 2 h · Depends on: BCN-01
Email, Slack, Discord and custom bodies from spec section 12, for opened, resolved and test.

- [ ] Golden-file tests for all twelve combinations

### BCN-27 Senders

`P1` · 2.5 h · Depends on: BCN-08, BCN-26 · SEC-6, SEC-9
SMTP sender and webhook sender (5 s timeout, safe dialer, 2xx is success).

- [ ] A webhook to a private address is refused
- [ ] Webhook URLs never appear in logs

### BCN-28 Local mail catcher and seeded channel

`P1` · 0.5 h · Depends on: BCN-06, BCN-22
Add the mail catcher to Compose; seed one email channel.

- [ ] A sent email is visible in the catcher's web page

### BCN-29 Notifier

`P1` · 3 h · Depends on: BCN-25, BCN-27 · FR-18b, FR-19, FR-21a
Consumer `beacon.notifier` on `incident.events`, steps 1-7 of spec section 8.6.

- [ ] One email on open and one on resolve
- [ ] The same incident event delivered twice sends one email
- [ ] `paused` and `edited` resolutions send nothing

### BCN-30 Retry tiers and dead letter

`P1` · 4 h · Depends on: BCN-29 · FR-20
Three retry topics, partition pause while waiting, dead-letter after the fourth failure.

- [ ] A webhook to a closed port is retried at about 1, 5 and 25 minutes
- [ ] It ends with status `dead` and a message in `notify.dead`
- [ ] The consumer stays in its group throughout the 25-minute wait

### BCN-31 Failure-mode tests

`P1` · 3 h · Depends on: BCN-24, BCN-29, BCN-20
Duplicate delivery, out-of-order events, and killing each consumer mid-message.

- [ ] No lost incident, no second alert from redelivery

---

## M4 API, dashboard, first deploy

### BCN-32 Schema: sessions and status pages

`P1` · 0.5 h · Depends on: BCN-05

- [ ] Session tokens are stored hashed

### BCN-33 API skeleton

`P1` · 2 h · Depends on: BCN-01
`cmd/api`: router, JSON error format and codes from spec section 9, origin check, request logging, `/healthz`.

- [ ] Unknown routes return the JSON 404
- [ ] A state-changing request with a foreign `Origin` returns 403

### BCN-34 Accounts and sessions

`P1` · 4 h · Depends on: BCN-32, BCN-33 · FR-1 to FR-3a, SEC-5, SEC-8
Register, login, logout, change password, session middleware, rate limit.

- [ ] Cookie is `HttpOnly`, `SameSite=Lax`, and `Secure` when configured
- [ ] Wrong password and unknown email give the same response
- [ ] The sixth login attempt in a minute returns 429

### BCN-35 Monitor endpoints

`P1` · 4 h · Depends on: BCN-34, BCN-07 · FR-4 to FR-7a, FR-17
List, create, read, edit, delete, pause, resume, with the monitor object from spec section 9.

- [ ] Field errors come back under `error.fields`
- [ ] A second account gets 404 for the first account's monitor
- [ ] The 51st monitor returns `limit_reached`
- [ ] Pausing with an open incident resolves it without an alert

### BCN-36 Read endpoints

`P1` · 3 h · Depends on: BCN-35
`/summary`, `/monitors/{id}/rollups` for `60m` and `24h`, incident lists with their notifications.

- [ ] `60m` returns 60 points, `24h` returns 96, empty buckets included
- [ ] Uptime matches the definition in spec section 10

### BCN-37 Live gateway

`P1` · 4 h · Depends on: BCN-34, BCN-17
`/stream` from spec section 8.7.

- [ ] A user receives only their own monitors' events
- [ ] Events arrive in batches at most once a second; heartbeat every 15 s
- [ ] A stalled client is disconnected, others are unaffected

### BCN-38 Next.js scaffold

`P1` · 3 h · Depends on: BCN-33
App in `web/`: Tailwind with the tokens from spec section 11, layout and navigation, `/api` rewrite, redirect to `/login` when signed out.

- [ ] Navigation matches the design canvas at desktop and phone width
- [ ] `web` runs in Compose

### BCN-39 Sign-in and register screens

`P1` · 2 h · Depends on: BCN-34, BCN-38
Screen 9.

- [ ] API errors appear under the right field
- [ ] Successful sign-in lands on the dashboard

### BCN-40 API client and server-state setup

`P1` · 2 h · Depends on: BCN-38
Typed client, TanStack Query, server-side fetch that forwards the session cookie.

- [ ] The dashboard's first paint has data with no client request

### BCN-41 Live store and stream client

`P1` · 3 h · Depends on: BCN-37, BCN-40 · FE-1 to FE-4
Zustand store from spec section 11; stream client with reconnect backoff.

- [ ] Unit tests for `seed`, `applyBatch` and `applyIncident`
- [ ] Stopping the API shows "Reconnecting"; restart reseeds the store

### BCN-42 Dashboard

`P1` · 4 h · Depends on: BCN-41, BCN-36 · FR-22, FR-23, FR-25
Screen 1: summary cards, monitor table with strip, live indicator.

- [ ] Loading, empty, Checking and Paused states match the spec table
- [ ] The profiler shows one row re-rendering per incoming check

### BCN-43 Add and edit monitor form

`P1` · 2.5 h · Depends on: BCN-35, BCN-40 · FE-5
Screen 4, shared by create and edit.

- [ ] A private address shows the server's message under the URL field

### BCN-44 Monitor detail

`P1` · 4 h · Depends on: BCN-36, BCN-41 · FR-24
Screen 2: hand-drawn SVG chart with a 60-minute and 24-hour switch, settings, incident history, pause and resume.

- [ ] Failed minutes are marked differently from response bars
- [ ] The chart has a text alternative

### BCN-45 Component tests with Vitest

`P1` · 2.5 h · Depends on: BCN-42
Vitest and Testing Library for what is cheap to test without a browser: the monitor row in each display state, form validation, the chart's bar maths. Run in watch mode while developing. Browser flows belong to Playwright.

- [ ] The monitor row has a test for Up, Down, Checking and Paused
- [ ] CI runs Vitest and the type check

### BCN-46 First deployment

`P1` · 3 h · Depends on: BCN-42
Production Compose file, Caddy with HTTPS, deploy to a server, nightly database dump.

- [ ] The site loads over HTTPS on your domain
- [ ] The event stream works through the proxy
- [ ] Beacon monitors gabrielenache.com and its own `/healthz`

### BCN-64 Playwright setup

`P1` · 3 h · Depends on: BCN-39, BCN-04
Add `@playwright/test` to `web/`; config in `web/playwright.config.ts`, specs in `web/e2e/`. Tests run against the real Compose stack. Sign in once in a setup project and reuse the session. Trace on first retry, screenshot on failure. CI job starts the stack, runs the tests, uploads report and traces.

- [ ] `make e2e` runs the suite locally against the running stack
- [ ] One smoke test passes: sign in and see the dashboard
- [ ] A failing test in CI leaves a trace you can download and open
- [ ] Locators use roles and labels, not CSS classes

### BCN-65 Playwright: monitor flows

`P1` · 3 h · Depends on: BCN-64, BCN-43, BCN-44
Add a monitor on the fake target and watch it go from Checking to Up; a private address shows the field error; edit; pause shows Paused; delete removes the row.

- [ ] The tests pass three times in a row with no retries
- [ ] Each test creates its own account or data and does not depend on test order
- [ ] No fixed sleeps; tests wait on visible state

---

## M5 Settings and status page

### BCN-47 Alert channel endpoints

`P1` · 3 h · Depends on: BCN-34, BCN-27 · FR-18 to FR-21, SEC-9
List, create, patch, delete, test saved, test unsaved.

- [ ] Slack and Discord targets are validated by prefix
- [ ] Targets come back masked
- [ ] A test alert returns success or the delivery error

### BCN-48 Settings screen

`P1` · 3 h · Depends on: BCN-47
Screen 5: channel list with Send test, Pause or Enable, Remove; account block.

- [ ] Removing asks for confirmation

### BCN-49 Add alert channel form

`P1` · 2 h · Depends on: BCN-47
Screen 6 with the type picker.

- [ ] Fields and help text change with the type
- [ ] "Send test alert" works before saving

### BCN-50 Incidents page

`P2` · 2 h · Depends on: BCN-36 · FR-25a
Screen 8 with the all, open, resolved filter.

- [ ] Each row lists the alerts sent and their status

### BCN-51 Status page API

`P1` · 3 h · Depends on: BCN-36 · FR-26 to FR-28
`GET` and `PUT /status-page`, `GET /public/status/{slug}`.

- [ ] The public response contains no URLs
- [ ] `days` always has 90 entries

### BCN-52 Status page settings

`P1` · 1.5 h · Depends on: BCN-51, BCN-48
The status page block of screen 5.

- [ ] A taken slug shows a field error

### BCN-53 Public status page

`P1` · 3 h · Depends on: BCN-51 · FR-29
Screen 3, server-rendered, cached for 30 seconds.

- [ ] Loads signed-out
- [ ] A second request within 30 seconds does not hit the API

### BCN-66 Playwright: alert channels and status page

`P1` · 2.5 h · Depends on: BCN-64, BCN-49, BCN-52, BCN-53
Add an email channel and send a test alert; switching the channel type changes the fields; set the status page address, then open the page in a signed-out browser context.

- [ ] The test alert email is asserted through the mail catcher's HTTP API
- [ ] The status page test runs in a signed-out browser context
- [ ] The status page text contains no monitor URL

---

## M6 Hardening and presentation

### BCN-54 Retention job

`P2` · 1.5 h · Depends on: BCN-19
Spec section 8.8.

- [ ] Old rows are removed; recent ones are untouched

### BCN-55 Metrics

`P2` · 2.5 h · Depends on: BCN-37
Prometheus endpoint on the internal port with the metrics in spec section 15.

- [ ] Consumer lag is visible per group

### BCN-56 Graceful shutdown audit

`P1` · 2 h · Depends on: BCN-37
All three Go services.

- [ ] Each exits within 10 s of SIGTERM with no half-processed message

### BCN-57 End-to-end outage scenario with Playwright

`P1` · 3 h · Depends on: BCN-64, BCN-42, BCN-29, BCN-28
One Playwright spec: add a monitor on the fake target (30-second interval, threshold 1); switch the target to 503; the row turns Down without a reload and an incident appears; the "down" email arrives in the mail catcher; switch back; the row turns Up and the "recovered" email arrives. Give it a longer timeout.

- [ ] Runs green in CI
- [ ] Finishes in under four minutes
- [ ] The run records a trace you can replay step by step

### BCN-58 Load test

`P2` · 2 h · Depends on: BCN-46
200 monitors for 15 minutes with your Go Load Tester as the target load.

- [ ] Results recorded: check lag, consumer lag, memory

### BCN-59 Accessibility and phone-width pass

`P2` · 2 h · Depends on: BCN-53, BCN-64 · FE-6 to FE-8
Add a Playwright project with a 390 px phone viewport and run the suite in it. Add one keyboard-only test for the main flow. Fix what fails.

- [ ] Every screen is usable by keyboard alone
- [ ] No screen scrolls sideways at 390 px except inside table boxes
- [ ] The phone project runs in CI

### BCN-60 Error states

`P1` · 2 h · Depends on: BCN-42
The Error row of the states table on every screen.

- [ ] With the API stopped, no screen is blank

### BCN-61 README

`P1` · 2.5 h · Depends on: BCN-46
Problem, architecture diagram, one-command start, decisions and trade-offs, what you would do next.

- [ ] A person who has never seen the project can run it from the README alone

### BCN-62 Demo video

`P1` · 1.5 h · Depends on: BCN-57
Three minutes: break the fake target, show the incident, the alert and the status page.

- [ ] Linked from the README

### BCN-63 Article

`P2` · 3 h · Depends on: BCN-61
What you learned putting Kafka behind an uptime monitor.

- [ ] Published and linked from your site
