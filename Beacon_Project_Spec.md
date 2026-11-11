# Beacon: project specification

Version 2.1, 11 November 2026. Author: Gabriel Enache.

Beacon checks websites and APIs from the outside on a schedule, opens an incident
when one stops answering, sends an alert, and publishes a public status page.

## 0. How to use this document

- Sections 1-4 say **what** Beacon does. Sections 5-14 say **how**, down to the
  SQL and JSON. Sections 15-20 cover quality, layout, milestones and defaults.
- "Must" is a requirement. "Default" is a choice already made for you so that
  you are never blocked; change it if you have a reason and note it in the README.
- Every requirement has an ID (FR, SEC, FE). Put the ID in commit messages and
  tickets.
- Section 21 lists the parts that are hard. Expect to spend real time there.

---

## 1. Goals and non-goals

### Goals

1. Detect that a monitored HTTP endpoint is down within three minutes.
2. Alert the owner when it goes down and when it recovers.
3. Show live state and history in a dashboard.
4. Publish a public status page that needs no sign-in.
5. Run the whole system with one command: `docker compose up`.
6. Give you real answers to interview questions on Go concurrency, Kafka
   delivery guarantees, PostgreSQL modelling, Next.js rendering and client
   state with Zustand.

### Non-goals for version 1

- Checks from several regions.
- Teams, roles, billing.
- SMS or phone alerts.
- Protocols other than HTTP and HTTPS.
- Email verification and password reset by email.
- Per-monitor alert routing (every channel gets every alert).
- Kubernetes. One server and Docker Compose are enough.
- A mobile app.

---

## 2. Users and stories

One kind of user: the owner of a few websites or APIs.

| ID | As the owner I want to | So that |
| --- | --- | --- |
| US-1 | add a URL with an interval and a healthy status code | Beacon starts checking it |
| US-2 | see every monitor's state on one screen, updating live | I know at a glance what is down |
| US-3 | get an email, Slack or Discord message when a monitor goes down | I find out before my customers |
| US-4 | get one message when it recovers, with the outage length | I know it is over |
| US-5 | see response times and past incidents for a monitor | I can spot a service getting slower |
| US-6 | pause a monitor | planned maintenance does not page me |
| US-7 | share a public status page | customers can check for themselves |

A visitor (no account) can open the public status page and nothing else.

---

## 3. Glossary

| Term | Meaning |
| --- | --- |
| Monitor | One URL to check, with its settings |
| Check | One scheduled attempt to reach a monitor, including its one immediate retry |
| Check result | The outcome of a check: ok or failed, with status code, time and error |
| Incident | A period during which a monitor is considered down |
| Alert channel | A destination for alerts: an email address or a webhook |
| Notification | One alert to one channel about one incident transition |
| Rollup | Check results summed per minute or per day |
| Display state | What the UI shows: Up, Down, Checking or Paused (section 10) |

---

## 4. Functional requirements

### Accounts

- FR-1. Register and sign in with email and password. Password: at least 12
  characters. Stored with argon2id.
- FR-2. Sessions are rows in the database, referenced by an opaque random
  token in an `HttpOnly`, `Secure`, `SameSite=Lax` cookie. Sessions last 30
  days from last use. Sign-out deletes the row.
- FR-3. Every monitor, channel and incident belongs to exactly one user. Every
  query filters by the signed-in user. A request for another user's object
  returns 404, not 403.
- FR-3a. A signed-in user can change their password by giving the current one.

### Monitors

- FR-4. A monitor has: name (1-80 characters), URL (up to 2,000 characters),
  interval (30, 60 or 300 seconds), timeout (1-30 s, default 5), expected
  status code (100-599, default 200), failure threshold (1-10, default 3), a
  paused flag and a "show on status page" flag.
- FR-5. Only `http` and `https` URLs are accepted. The host must resolve to a
  public address at creation time and at every check (section 13).
- FR-6. A user may have at most 50 monitors.
- FR-7. Create, edit, pause, resume and delete are available in the dashboard.
  Deleting a monitor deletes its history.
- FR-7a. Editing the URL, expected status or threshold resets the monitor's
  state to "unknown" and its counters to zero. An open incident is resolved
  with cause `edited`, without an alert. History is kept.

### Checks

- FR-8. The checker issues a `GET` to each active monitor once per interval,
  within 5 seconds of the scheduled time.
- FR-9. A check fails when the request errors, the timeout passes, the address
  is blocked, or the status code differs from the expected one.
- FR-10. A failed check is retried once immediately. Only the final outcome is
  published, with `attempts` set to 2.
- FR-11. Redirects are followed, at most 5. Every hop is validated against the
  address rules in section 13.
- FR-12. Every check produces exactly one `check.results` event. If Kafka is
  unreachable for 30 seconds, the result is dropped and counted in a metric;
  scheduling never blocks.

### Incidents

- FR-13. An incident opens when a monitor reaches its failure threshold of
  consecutive failed checks. Its start time is the time of the **first** failed
  check in that run.
- FR-14. An incident resolves after 2 consecutive successful checks. Its end
  time is the time of the second one.
- FR-15. A monitor has at most one open incident.
- FR-16. An incident records start, end, cause (the error of the first failed
  check) and duration.
- FR-17. Pausing a monitor with an open incident resolves it with cause
  `paused` and sends no alert. Resuming starts from state "unknown".

### Alerts

- FR-18. Channel types: email, Slack, Discord and custom webhook. Slack and
  Discord channels store an incoming-webhook URL and receive that service's
  message format. A custom webhook receives Beacon's JSON (section 12).
- FR-18a. Each channel has a label, can be paused and re-enabled, and can be
  removed. Webhook URLs are returned masked by the API after saving.
- FR-18b. Every enabled channel of the user receives every alert.
- FR-19. One notification per channel when an incident opens and one when it
  resolves. A duplicate Kafka delivery must never cause a second alert. The one
  accepted duplicate: a crash in the instant between sending and recording.
  Beacon prefers a rare duplicate over a missed alert.
- FR-20. A failed delivery is retried after 1, 5 and 25 minutes, then parked
  in a dead-letter topic and marked `dead`.
- FR-21. "Send test alert" works for a saved channel and for an unsaved one
  from the add-channel form. It sends immediately and reports success or the
  error.
- FR-21a. Incidents with cause `paused` or `edited` never notify.

### Dashboard

- FR-22. Monitor list: display state, name, URL, time of last check, last
  response time, 30-day uptime, and a strip of the last 24 minutes.
- FR-23. The list updates without reload when a check arrives. An indicator
  shows whether the live connection is open.
- FR-24. Monitor detail: response-time chart for the last 60 minutes and the
  last 24 hours, settings, and incident history.
- FR-25. Summary counts: monitors, up, down, open incidents.
- FR-25a. Incidents page: all incidents, filter by all, open or resolved, with
  the alerts sent for each.

### Public status page

- FR-26. Served at `/status/<slug>` without sign-in.
- FR-27. Shows an overall banner, each selected monitor's state, a 90-day
  strip, 90-day uptime, and incidents from the last 30 days.
- FR-28. Shows monitor names only, never URLs or error details beyond the
  texts in section 10.
- FR-29. Rendered on the server and cached for 30 seconds.

---

## 5. Architecture

```
 browser ──HTTPS──> reverse proxy ──/api/*──> api (Go) ──> PostgreSQL
                         │                      │  ^
                         └──everything else──>  │  └── SSE to browser
                              web (Next.js) ────┘  (server-side fetches to api)

 checker (Go) ──check.results──> Kafka ──> worker: rollup writer ──> PostgreSQL
                                       ├──> worker: incident detector ──> PostgreSQL (+ outbox)
                                       └──> api: live gateway ──> SSE
 worker: outbox relay ──incident.events──> Kafka ──> worker: notifier ──> email / webhooks
                                                └──> api: live gateway ──> SSE
```

### Services

| Service | Language | Port | Responsibility |
| --- | --- | --- | --- |
| `checker` | Go | none | Scheduler plus bounded worker pool; publishes check results |
| `worker` | Go | none | Rollup writer, incident detector, outbox relay, notifier, retention job |
| `api` | Go | 8080 | REST API, sessions, live gateway (Server-Sent Events) |
| `web` | Next.js 16, TypeScript | 3000 | Dashboard and public status page |
| `postgres` | PostgreSQL 16+ | 5432 | System of record |
| `kafka` | Apache Kafka, KRaft mode, one broker | 9092 | Event log |
| `mail` (dev only) | Local SMTP catcher | 1025 | Shows outgoing email in a browser |
| `proxy` (prod only) | Caddy | 443 | HTTPS, routes `/api/*` to `api`, the rest to `web` |

`checker`, `worker` and `api` share one Go module with three `cmd/` entry points.

### Same origin everywhere

The browser always talks to one origin. In production the proxy routes
`/api/*` to `api`. In development a Next.js rewrite does the same. This keeps
the session cookie first-party and avoids CORS. If the development rewrite
buffers the event stream, point the stream URL directly at `api` and allow
that origin with credentials in development only.

### Why Kafka here, stated honestly

At this size PostgreSQL alone would do. Kafka is used because it gives
independent consumers, per-monitor ordering and replay, and because learning it
is a goal. The README must say this.

---

## 6. Kafka

### Topics

Auto-creation is off. A one-shot `kafka-init` container creates the topics.

| Topic | Key | Partitions | Retention | Producer | Consumers |
| --- | --- | --- | --- | --- | --- |
| `check.results` | `monitor_id` | 6 | 7 days | checker | rollup writer, incident detector, live gateway |
| `incident.events` | `monitor_id` | 3 | 7 days | outbox relay | notifier, live gateway |
| `notify.retry.1m` | `notification_id` | 1 | 7 days | outbox relay | notifier |
| `notify.retry.5m` | `notification_id` | 1 | 7 days | outbox relay | notifier |
| `notify.retry.25m` | `notification_id` | 1 | 7 days | outbox relay | notifier |
| `notify.dead` | `notification_id` | 1 | 30 days | outbox relay | nobody; inspected by hand |

One retry topic per delay keeps messages in due order, so the consumer may
wait on the first message without blocking a later one that is due sooner.

### Consumer groups

| Group | Topic | Start offset when new |
| --- | --- | --- |
| `beacon.rollup` | `check.results` | earliest |
| `beacon.incident` | `check.results` | earliest |
| `beacon.notifier` | `incident.events` and the three retry topics | earliest |
| `beacon.live.<random id per api process>` | `check.results`, `incident.events` | latest |

### `check.results` value

```json
{
  "schema_version": 1,
  "event_id": "8f2c1c5e-6c1b-4d0b-9a55-3b0d3b6f2f10",
  "monitor_id": "0b9a7a52-0a5e-4f39-8a0e-2d7d7c0f6a11",
  "checked_at": "2027-01-04T02:10:00Z",
  "ok": false,
  "status_code": 503,
  "response_ms": 412,
  "error": "status_mismatch",
  "attempts": 2
}
```

`error` is `null` when `ok` is true, otherwise one of `timeout`, `dns`,
`connection`, `tls`, `status_mismatch`, `blocked_address`, `too_many_redirects`.
`status_code` and `response_ms` are `null` when no response arrived.
`checked_at` is the scheduled start of the check, in UTC.

### `incident.events` value

```json
{
  "schema_version": 1,
  "event_id": "c1d3a6de-7b54-4c8a-b0f1-0d8d6a5e9b22",
  "incident_id": "5a0c2d3e-1f4b-4e6a-9c7d-8b9a0c1d2e3f",
  "monitor_id": "0b9a7a52-0a5e-4f39-8a0e-2d7d7c0f6a11",
  "user_id": "3d1f0c1a-2b3c-4d5e-8f90-a1b2c3d4e5f6",
  "type": "opened",
  "at": "2027-01-04T02:12:00Z",
  "started_at": "2027-01-04T02:10:00Z",
  "cause": "status_mismatch",
  "duration_s": null
}
```

`type` is `opened` or `resolved`. On `resolved`, `duration_s` is set and
`cause` may also be `paused` or `edited`.

### Retry message value

```json
{ "notification_id": "…", "attempt": 2, "not_before": "2027-01-04T02:14:00Z" }
```

### Delivery rules

- Producers: idempotence on, `acks=all`.
- Consumers: auto-commit off. Commit an offset only after the database
  transaction for that message has committed.
- Every consumer must reach the same result when it sees a message twice.
- A message that cannot be parsed, or that refers to a monitor that no longer
  exists, is logged, counted and skipped. It must never stop the partition.

---

## 7. Data model (PostgreSQL)

All timestamps are `timestamptz` in UTC. All IDs are UUIDs.

```sql
CREATE TABLE users (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email         text NOT NULL UNIQUE,          -- stored lower-cased
  password_hash text NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE sessions (
  token_hash   bytea PRIMARY KEY,              -- SHA-256 of the cookie token
  user_id      uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at   timestamptz NOT NULL DEFAULT now(),
  last_used_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE monitors (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name              text NOT NULL,
  url               text NOT NULL,
  interval_s        int  NOT NULL CHECK (interval_s IN (30, 60, 300)),
  timeout_s         int  NOT NULL DEFAULT 5 CHECK (timeout_s BETWEEN 1 AND 30),
  expected_status   int  NOT NULL DEFAULT 200 CHECK (expected_status BETWEEN 100 AND 599),
  failure_threshold int  NOT NULL DEFAULT 3 CHECK (failure_threshold BETWEEN 1 AND 10),
  paused            boolean NOT NULL DEFAULT false,
  on_status_page    boolean NOT NULL DEFAULT true,
  next_check_at     timestamptz NOT NULL DEFAULT now(),
  created_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX monitors_due ON monitors (next_check_at) WHERE NOT paused;
CREATE INDEX monitors_by_user ON monitors (user_id);

-- One row per monitor, created with the monitor, owned by the incident detector.
CREATE TABLE monitor_state (
  monitor_id            uuid PRIMARY KEY REFERENCES monitors(id) ON DELETE CASCADE,
  state                 text NOT NULL DEFAULT 'unknown'
                          CHECK (state IN ('unknown', 'up', 'down')),
  consecutive_failures  int  NOT NULL DEFAULT 0,
  consecutive_successes int  NOT NULL DEFAULT 0,
  first_failure_at      timestamptz,           -- start of the current failing run
  first_failure_cause   text,
  last_checked_at       timestamptz,
  last_ok               boolean,
  last_status_code      int,
  last_response_ms      int,
  last_event_id         uuid
);

CREATE TABLE incidents (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  monitor_id  uuid NOT NULL REFERENCES monitors(id) ON DELETE CASCADE,
  started_at  timestamptz NOT NULL,
  resolved_at timestamptz,
  cause       text NOT NULL,                   -- error of the first failed check
  resolution  text                             -- NULL, 'recovered', 'paused' or 'edited'
);
CREATE UNIQUE INDEX incidents_one_open ON incidents (monitor_id)
  WHERE resolved_at IS NULL;                   -- FR-15
CREATE INDEX incidents_by_monitor ON incidents (monitor_id, started_at DESC);

CREATE TABLE rollups_minute (
  monitor_id uuid NOT NULL REFERENCES monitors(id) ON DELETE CASCADE,
  minute     timestamptz NOT NULL,
  checks     int NOT NULL,
  failures   int NOT NULL,
  sum_ms     bigint NOT NULL,                  -- over successful checks only
  max_ms     int NOT NULL,                     -- over successful checks only
  PRIMARY KEY (monitor_id, minute)
);

CREATE TABLE rollups_day (
  monitor_id uuid NOT NULL REFERENCES monitors(id) ON DELETE CASCADE,
  day        date NOT NULL,                    -- UTC day
  checks     int NOT NULL,
  failures   int NOT NULL,
  PRIMARY KEY (monitor_id, day)
);

-- Lets a consumer ignore an event it has already applied.
CREATE TABLE processed_events (
  consumer text NOT NULL,
  event_id uuid NOT NULL,
  seen_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (consumer, event_id)
);

-- Events to publish, written in the same transaction as the change they describe.
CREATE TABLE outbox (
  id           bigserial PRIMARY KEY,
  topic        text NOT NULL,
  key          text NOT NULL,
  payload      jsonb NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now(),
  published_at timestamptz
);
CREATE INDEX outbox_unpublished ON outbox (id) WHERE published_at IS NULL;

CREATE TABLE alert_channels (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind       text NOT NULL CHECK (kind IN ('email', 'slack', 'discord', 'webhook')),
  label      text NOT NULL,
  target     text NOT NULL,                    -- email address or webhook URL
  enabled    boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE notifications (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  incident_id uuid NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
  channel_id  uuid NOT NULL REFERENCES alert_channels(id) ON DELETE CASCADE,
  kind        text NOT NULL CHECK (kind IN ('opened', 'resolved')),
  status      text NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending', 'sent', 'dead')),
  attempts    int NOT NULL DEFAULT 0,
  last_error  text,
  sent_at     timestamptz,
  UNIQUE (incident_id, channel_id, kind)       -- the idempotency key for FR-19
);

CREATE TABLE status_pages (
  user_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  slug    text NOT NULL UNIQUE,                -- ^[a-z0-9][a-z0-9-]{2,39}$
  title   text NOT NULL
);
```

---

## 8. Component behaviour, step by step

### 8.1 Checker: scheduling

Every second, claim up to 100 due monitors and advance their next run in one
statement. `SKIP LOCKED` makes it safe to run two checkers.

```sql
WITH due AS (
  SELECT id FROM monitors
  WHERE NOT paused AND next_check_at <= now()
  ORDER BY next_check_at
  LIMIT 100
  FOR UPDATE SKIP LOCKED
)
UPDATE monitors m
SET next_check_at = CASE
      WHEN m.next_check_at + make_interval(secs => m.interval_s) > now()
        THEN m.next_check_at + make_interval(secs => m.interval_s)
      ELSE now() + make_interval(secs => m.interval_s)   -- fell behind: no burst
    END
FROM due
WHERE m.id = due.id
RETURNING m.id, m.url, m.timeout_s, m.expected_status;
```

Send each returned monitor to the worker pool. Defaults: 50 workers, at most
2 concurrent checks per host. If the pool's queue is full, the scheduler waits;
it never drops a claimed monitor silently.

### 8.2 Checker: one check

1. Record `checked_at` = now, truncated to the second.
2. Validate and resolve the address (section 13). Blocked: result
   `blocked_address`, no request made.
3. `GET` with the monitor's timeout covering connect, TLS, headers and body
   read. Read at most 64 KB, then discard.
4. `response_ms` = time from sending the request to receiving the headers.
5. `ok` = no error and `status_code == expected_status`.
6. If not ok and this was attempt 1, repeat steps 2-5 once, immediately.
7. Publish one event keyed by `monitor_id`.

### 8.3 Rollup writer

For each `check.results` message, in one transaction:

1. `INSERT INTO processed_events ('rollup', event_id) ON CONFLICT DO NOTHING`.
   If no row was inserted, the event was already counted: stop.
2. Upsert `rollups_minute` for `date_trunc('minute', checked_at)`: `checks + 1`,
   `failures + 1` if not ok; if ok, add `response_ms` to `sum_ms` and raise
   `max_ms`.
3. Upsert `rollups_day` for the UTC date the same way.
4. Commit, then commit the Kafka offset.

### 8.4 Incident detector

For each `check.results` message, in one transaction:

1. `SELECT … FROM monitor_state WHERE monitor_id = $1 FOR UPDATE`. No row:
   the monitor was deleted; skip.
2. If the monitor is paused, skip.
3. If `event_id = last_event_id`, or `checked_at <= last_checked_at`, skip.
4. Apply the table below.
5. Always set `last_checked_at`, `last_ok`, `last_status_code`,
   `last_response_ms`, `last_event_id`.
6. Commit, then commit the Kafka offset.

| State | Event | Action | Next state |
| --- | --- | --- | --- |
| unknown, up | ok | failures = 0, clear `first_failure_*` | up |
| unknown, up | failed, failures + 1 < threshold | failures + 1; on the first failure set `first_failure_at` and `first_failure_cause` | unchanged |
| unknown, up | failed, failures + 1 = threshold | insert incident (`started_at = first_failure_at`, `cause = first_failure_cause`); insert outbox `opened`; successes = 0 | down |
| down | failed | successes = 0 | down |
| down | ok, successes + 1 < 2 | successes + 1 | down |
| down | ok, successes + 1 = 2 | set `resolved_at = checked_at`, `resolution = 'recovered'`; insert outbox `resolved`; failures = 0, clear `first_failure_*` | up |

With a threshold of 1, the first failure opens the incident directly.

### 8.5 Outbox relay

Every 500 ms: select up to 100 unpublished rows ordered by `id` with
`FOR UPDATE SKIP LOCKED`, produce each to its topic, wait for the broker's
acknowledgement, set `published_at`, commit. A crash after producing and before
commit republishes the row; consumers already tolerate duplicates.

The API uses the same outbox when it resolves an incident on pause or edit
(FR-7a, FR-17).

### 8.6 Notifier

For each `incident.events` message:

1. If `cause` is `paused` or `edited` and `type` is `resolved`, skip.
2. Load the user's enabled channels.
3. For each channel:
   `INSERT INTO notifications (incident_id, channel_id, kind) … ON CONFLICT DO NOTHING`.
4. Load the notification row. If `status = 'sent'` or `'dead'`, or
   `attempts > 0`, skip it: it is already handled or already in the retry flow.
5. Send (section 12). Timeout 5 s. Success is any 2xx for webhooks, or SMTP
   acceptance for email.
6. Success: `status = 'sent'`, `sent_at = now()`, `attempts = attempts + 1`.
7. Failure: `attempts = attempts + 1`, store `last_error`, and write a retry
   message for `notify.retry.1m` (`not_before = now() + 1 minute`) to the
   outbox in the same transaction, so a crash cannot strand the notification.

For each retry message:

1. If `now() < not_before`, pause the partition and keep polling until the
   time arrives, then resume. Do not sleep inside the poll loop for longer than
   the consumer's maximum poll interval.
2. Load the notification. If `status` is not `pending`, skip.
3. Send. On success mark `sent`.
4. On failure, again through the outbox: after attempt 2 publish to
   `notify.retry.5m`; after attempt 3 to `notify.retry.25m`; after attempt 4
   publish to `notify.dead` and set `status = 'dead'`.

### 8.7 Live gateway (inside `api`)

- Keeps an in-memory map `monitor_id -> user_id`, loaded at start, refreshed
  every 30 seconds, with a database lookup on a miss.
- Keeps a registry of open connections per user.
- For each consumed event, finds the user and appends the event to each of
  that user's connection buffers.
- Each connection flushes its buffer once a second as one write.
- A buffer over 500 events means a slow client: close the connection. The
  client reconnects and reloads.
- Sends a `heartbeat` event every 15 seconds.

### 8.8 Retention job (inside `worker`)

Once a day at 03:00 UTC: delete `rollups_minute` older than 7 days,
`processed_events` older than 2 days, published `outbox` rows older than 2
days, and `sessions` unused for 30 days.

---

## 9. HTTP API

Base path `/api/v1`. JSON in and out. UTF-8. Times are RFC 3339 in UTC.

### Conventions

- Auth: the session cookie `beacon_session`. Routes marked public need none.
- State-changing requests must carry `Content-Type: application/json` and an
  `Origin` header matching the site; otherwise 403.
- Lists that can grow are cursor-paginated: `?limit=50&cursor=…`, response
  `{ "items": […], "next_cursor": "…" | null }`.
- Errors:

```json
{ "error": { "code": "validation_failed", "message": "Check the highlighted fields.",
             "fields": { "url": "Private and local addresses are not allowed." } } }
```

| HTTP | `code` | When |
| --- | --- | --- |
| 400 | `bad_request` | Body is not valid JSON |
| 401 | `unauthenticated` | No valid session |
| 403 | `forbidden_origin` | Origin check failed |
| 404 | `not_found` | Missing, or belongs to another user |
| 409 | `limit_reached` | 50 monitors already |
| 409 | `conflict` | Email or slug already taken |
| 422 | `validation_failed` | Field errors, in `fields` |
| 429 | `rate_limited` | Too many attempts |
| 500 | `internal` | Anything else; details only in logs |

### Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| POST | `/auth/register` | Create account, start session (public) |
| POST | `/auth/login` | Start session (public) |
| POST | `/auth/logout` | End session |
| POST | `/auth/password` | Change password: `current`, `new` |
| GET | `/me` | Current user: `id`, `email` |
| GET | `/monitors` | All monitors with state (no pagination; at most 50) |
| POST | `/monitors` | Create |
| GET | `/monitors/{id}` | One monitor with state |
| PATCH | `/monitors/{id}` | Edit any settable field |
| DELETE | `/monitors/{id}` | Delete with history |
| POST | `/monitors/{id}/pause` | Pause (FR-17) |
| POST | `/monitors/{id}/resume` | Resume; sets `next_check_at = now()` |
| GET | `/monitors/{id}/rollups?window=60m` | Chart data; `60m` or `24h` |
| GET | `/monitors/{id}/incidents` | Incident history, newest first |
| GET | `/incidents?status=open` | Incidents across monitors; `open`, `resolved` or omitted |
| GET | `/summary` | Counts for the dashboard cards |
| GET | `/alert-channels` | List channels |
| POST | `/alert-channels` | Add channel |
| PATCH | `/alert-channels/{id}` | Change `label` or `enabled` |
| DELETE | `/alert-channels/{id}` | Remove |
| POST | `/alert-channels/{id}/test` | Test a saved channel |
| POST | `/alert-channels/test` | Test an unsaved one: `kind`, `target` |
| GET | `/status-page` | Settings: `title`, `slug`, `monitor_ids` |
| PUT | `/status-page` | Save settings; sets each monitor's `on_status_page` |
| GET | `/public/status/{slug}` | Status page data (public) |
| GET | `/stream` | Server-Sent Events |
| GET | `/healthz` | Liveness (public) |

`/metrics` is served on a separate internal port, never through the proxy.

### Monitor object

```json
{
  "id": "0b9a7a52-0a5e-4f39-8a0e-2d7d7c0f6a11",
  "name": "Client API",
  "url": "https://api.example.com/health",
  "interval_s": 60,
  "timeout_s": 5,
  "expected_status": 200,
  "failure_threshold": 3,
  "paused": false,
  "on_status_page": true,
  "created_at": "2026-12-01T09:00:00Z",
  "state": "down",
  "last_checked_at": "2027-01-04T02:24:00Z",
  "last_ok": false,
  "last_status_code": 503,
  "last_response_ms": 412,
  "uptime_30d": 99.21,
  "open_incident": { "id": "5a0c…", "started_at": "2027-01-04T02:10:00Z" },
  "recent": [ { "minute": "2027-01-04T02:01:00Z", "checks": 1, "failures": 0, "avg_ms": 198 } ]
}
```

`recent` holds the last 24 minute rollups, oldest first. `uptime_30d` is `null`
before the first check. `open_incident` is `null` when none is open.

### Create or edit a monitor

```json
{ "name": "Client API", "url": "https://api.example.com/health", "interval_s": 60,
  "timeout_s": 5, "expected_status": 200, "failure_threshold": 3, "on_status_page": true }
```

Only `name` and `url` are required on create. `PATCH` accepts any subset.
Response: the monitor object, 201 on create.

### Rollups

```json
{ "window": "60m", "bucket_s": 60,
  "points": [ { "t": "2027-01-04T01:25:00Z", "checks": 1, "failures": 0, "avg_ms": 190, "max_ms": 190 } ] }
```

`60m` returns 60 one-minute points. `24h` returns 96 fifteen-minute points,
summed on the server. A bucket with no checks is still returned, with
`checks: 0` and `avg_ms: null`.

### Incident object

```json
{ "id": "5a0c…", "monitor_id": "0b9a…", "monitor_name": "Client API",
  "started_at": "2027-01-04T02:10:00Z", "resolved_at": null, "duration_s": null,
  "cause": "status_mismatch", "resolution": null,
  "notifications": [ { "channel_label": "Ops team", "channel_kind": "slack",
                       "kind": "opened", "status": "sent", "sent_at": "2027-01-04T02:13:00Z" } ] }
```

### Alert channel object

```json
{ "id": "…", "kind": "slack", "label": "Ops team",
  "target_masked": "https://hooks.slack.com/services/…a1B2", "enabled": true,
  "last_sent_at": "2027-01-04T02:13:00Z" }
```

Create body: `kind`, `label`, `target`. Email targets must be valid addresses.
Webhook targets must be `https` and pass section 13. Slack targets must start
with `https://hooks.slack.com/`; Discord targets with
`https://discord.com/api/webhooks/`.

### Public status response

```json
{ "title": "Example Co. status", "updated_at": "2027-01-04T02:24:08Z",
  "overall": "down", "down_count": 1,
  "services": [ { "name": "Client API", "state": "down", "uptime_90d": 99.21,
                  "days": [ { "day": "2026-10-07", "status": "ok" } ] } ],
  "incidents": [ { "title": "Client API is not responding",
                   "started_at": "2027-01-04T02:10:00Z", "resolved_at": null, "duration_s": null } ] }
```

`days` has exactly 90 entries, oldest first; `status` is `ok`, `incident` or
`none` (before the monitor existed, or no checks that day). `overall` is
`operational` when no listed service is down.

### Live stream

`GET /api/v1/stream` returns `text/event-stream`.

```
event: checks
data: [{"monitor_id":"…","checked_at":"…","ok":true,"status_code":200,"response_ms":182}]

event: incident
data: {"incident_id":"…","monitor_id":"…","type":"opened","started_at":"…","at":"…"}

event: heartbeat
data: {}
```

`checks` carries the whole one-second batch as an array. On every (re)connect
the client refetches `/monitors` and `/summary`, then applies the stream.

---

## 10. Definitions of computed values

| Value | Definition |
| --- | --- |
| Display state | `Paused` if `paused`; else `Checking` if state is `unknown`; else `Up` or `Down` |
| Uptime over N days | `100 x (checks - failures) / checks` summed over `rollups_day` for the last N UTC days including today; two decimals; `null` if no checks |
| Average response, 24 h | `sum(sum_ms) / sum(checks - failures)` over `rollups_minute` for the last 24 hours |
| Last-24 strip | The last 24 minute rollups; a minute is "failed" if `failures > 0` |
| Incident duration | `resolved_at - started_at`; while open, `now - started_at` computed in the client |
| 90-day cell | `incident` if any incident with resolution other than `paused` or `edited` overlaps that UTC day |
| Summary counts | Monitors = all; Up and Down by display state; Open incidents = unresolved incidents |

### Texts for causes

| `cause` | Dashboard text | Status page incident title |
| --- | --- | --- |
| `timeout` | Timed out after N seconds | NAME was slow to respond |
| `dns` | Address could not be found | NAME could not be reached |
| `connection` | Connection failed | NAME could not be reached |
| `tls` | Secure connection failed | NAME could not be reached |
| `status_mismatch` | HTTP CODE, expected EXPECTED | NAME returned errors |
| `blocked_address` | Address is not allowed | NAME could not be reached |
| `too_many_redirects` | Too many redirects | NAME could not be reached |

---

## 11. Frontend

### Routes

| Route | Screen in the design canvas | Rendering |
| --- | --- | --- |
| `/login`, `/register` | 9. Sign in or create account | Client form |
| `/` | 1. Dashboard | Server fetch for first paint, then live client list |
| `/monitors/new`, `/monitors/[id]/edit` | 4. Add monitor form | Client form |
| `/monitors/[id]` | 2. Monitor detail | Server fetch, client chart |
| `/incidents` | 8. Incidents list | Server fetch, client filter |
| `/settings` | 5. Settings | Client |
| `/settings/channels/new` | 6. Add alert channel | Client form |
| `/status/[slug]` | 3. Public status page | Server-rendered, cached 30 s |

Screen 7 in the canvas shows the alert messages of section 12; it is not a page.

Signed-out visitors to any route except `/login`, `/register` and
`/status/*` are redirected to `/login`.

### Data and state

- **Server state** (monitors, summary, rollups, incidents, channels): fetched
  from the API and cached with TanStack Query. Server-rendered pages fetch on
  the server, forwarding the session cookie, and hand the data to the client
  cache so there is no second request on load.
- **Live client state**: one Zustand store, fed by the stream.

```ts
type ConnectionStatus = 'connecting' | 'open' | 'reconnecting' | 'closed';

interface LiveCheck {
  checkedAt: string;
  ok: boolean;
  statusCode: number | null;
  responseMs: number | null;
}

interface LiveStore {
  connection: ConnectionStatus;
  latestByMonitor: Record<string, LiveCheck>;
  stripByMonitor: Record<string, { minute: string; failed: boolean }[]>; // 24, oldest first
  openIncidentByMonitor: Record<string, { id: string; startedAt: string }>;
  filter: 'all' | 'up' | 'down';

  seed(monitors: Monitor[]): void;                 // from /monitors on (re)connect
  setConnection(status: ConnectionStatus): void;
  applyBatch(checks: Array<LiveCheck & { monitorId: string }>): void;
  applyIncident(e: { monitorId: string; incidentId: string;
                     type: 'opened' | 'resolved'; startedAt: string }): void;
  setFilter(filter: LiveStore['filter']): void;
}
```

Rules:

- FE-1. Each row subscribes with a selector for its own monitor, so one
  incoming check re-renders one row.
- FE-2. `applyBatch` applies a whole batch in one store update.
- FE-3. An `incident` event also invalidates the incidents and summary queries.
- FE-4. Reconnect with backoff: 1, 2, 5, then 10 seconds. Show "Reconnecting"
  in the live indicator meanwhile.
- FE-5. Forms use React Hook Form with a Zod schema; API field errors from
  `error.fields` are shown under their fields.
- FE-6. State is never shown by colour alone: every status has a text label.
- FE-7. Pages work at phone width; wide tables scroll sideways.
- FE-8. All controls are reachable by keyboard and have a visible focus ring.
- FE-9. Times are shown in the viewer's time zone; relative times ("12 s
  ago") update every second without refetching.

### States every screen must handle

| State | What to show | Screen in the design canvas |
| --- | --- | --- |
| Loading | Skeleton cards and rows, not a spinner over the page | 12. Dashboard loading |
| Empty | Dashboard with no monitors: one sentence and an "Add monitor" button | 11. Empty dashboard |
| Error | A message with a "Try again" button; never a blank page | 13. Dashboard could not load |
| Checking | A new monitor before its first result: grey "Checking" pill, "Not yet" for the last check, "No data" for response and uptime, flat grey strip | 10. Row states |
| Paused | Grey "Paused" pill; strip turns grey and stops; last check reads "Paused 2 h ago"; "Resume" replaces "Pause" | 10. Row states |
| Stream closed | Live indicator reads "Reconnecting"; data stays visible | 10. Row states |
| Form rejected | A summary above the form and one message under each wrong field (FE-5); the typed values stay | 14. Add monitor form with errors |
| Test alert result | A green "Test alert sent" or an orange "Test alert failed" banner with the reason, above the buttons | 15. Test alert results |
| Destructive action | A dialog naming the item, what is lost, and that it cannot be undone; "Cancel" is the default button | 16. Confirm delete dialog |

The same loading, empty and error treatment applies to the monitor detail,
incidents and settings pages; only the dashboard versions are drawn.

### Design tokens

| Token | Value | Use |
| --- | --- | --- |
| Ground | `#F5F6F8` | Page background |
| Surface | `#FFFFFF` | Cards |
| Ink | `#111827` | Text |
| Muted | `#4B5563` | Secondary text |
| Border | `#E2E5EA` | Card and row borders |
| Accent | `#1D4ED8` | Primary buttons, links, active nav |
| Up text / fill / bar | `#0F5F59` / `#E3F3F0` / `#7CC5BB` | Up state |
| Down text / fill / bar | `#9A3412` / `#FDEBDD` / `#C2410C` | Down state |
| Neutral text / fill | `#374151` / `#EEF0F3` | Paused and Checking |
| Type | Inter for text, Space Grotesk for headings | |
| Radius | 12 px cards, 8 px controls, full for pills | |
| Minimum target | 44 px | Buttons, links, inputs |

---

## 12. Alert messages

`NAME`, `CAUSE_TEXT` (dashboard text from section 10), `STARTED` (HH:MM UTC),
`DURATION` (for example "14 minutes") and `LINK` (the monitor's dashboard URL)
are filled in.

| Channel | Opened | Resolved |
| --- | --- | --- |
| Email subject | `Down: NAME is not responding` | `Recovered: NAME is back` |
| Email body | `NAME failed THRESHOLD checks in a row.` then Started, Last result, Address, and LINK | `It was down for DURATION, from STARTED to ENDED.` |
| Slack body | `{"text": "*Down: NAME*\nCAUSE_TEXT, since STARTED.\n<LINK|View monitor>"}` | `{"text": "*Recovered: NAME*\nBack up after DURATION."}` |
| Discord body | `{"content": "**Down: NAME**\nCAUSE_TEXT, since STARTED.\nLINK"}` | `{"content": "**Recovered: NAME**\nBack up after DURATION."}` |

Custom webhook body, `POST` with `Content-Type: application/json`:

```json
{ "type": "opened", "incident_id": "…", "monitor": "Client API",
  "cause": "status_mismatch", "started_at": "2027-01-04T02:10:00Z",
  "at": "2027-01-04T02:13:00Z", "duration_s": null }
```

A test alert uses the same formats with the name "Test monitor" and the
prefix "Test:".

---

## 13. Security requirements

- SEC-1. Before every request, and on every redirect hop, resolve the host and
  refuse loopback, private, link-local, carrier-grade NAT, multicast and
  unspecified addresses, for IPv4 and IPv6, including IPv4-mapped IPv6.
  Connect to the address you validated, not to a second lookup.
- SEC-2. Allow ports 80 and 443 only.
- SEC-3. Cap the response body read at 64 KB. The body is never stored.
- SEC-4. Send `User-Agent: BeaconBot/1.0 (+<public base URL>)`.
- SEC-5. Rate-limit `/auth/login` and `/auth/register` to 5 attempts a minute
  per address.
- SEC-6. Webhook targets pass the same address rules as monitor URLs, at save
  time and at send time.
- SEC-7. Secrets come from environment variables. Commit `.env.example`, never
  a real `.env`.
- SEC-8. The login error is the same for an unknown email and a wrong
  password.
- SEC-9. Webhook URLs are secrets: never log them, and return them masked.
- SEC-10. Point Beacon only at systems you own or have permission to check.

---

## 14. Configuration

| Variable | Used by | Example |
| --- | --- | --- |
| `DATABASE_URL` | api, worker, checker | `postgres://beacon:beacon@postgres:5432/beacon` |
| `KAFKA_BROKERS` | api, worker, checker | `kafka:9092` |
| `PUBLIC_BASE_URL` | api, worker | `https://beacon.example` |
| `SESSION_COOKIE_SECURE` | api | `true` (false only in local development) |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `SMTP_FROM` | worker, api | `mail`, `1025`, empty, empty, `alerts@beacon.example` |
| `CHECKER_WORKERS` | checker | `50` |
| `CHECKER_PER_HOST` | checker | `2` |
| `API_ADDR`, `METRICS_ADDR` | api | `:8080`, `:9090` |
| `API_INTERNAL_URL` | web | `http://api:8080` |
| `LOG_LEVEL` | all Go services | `info` |

---

## 15. Non-functional targets

Targets to test against, not measured results.

| Area | Target |
| --- | --- |
| Capacity | 200 monitors at 60 s on one server with 4 GB of memory |
| Detection | Incident opens within `threshold x interval + 30 s` of the first failure |
| Live latency | A check appears in the dashboard within 3 s of completing |
| Status page | Served from cache in under 200 ms |
| Recovery | Any service can be killed and restarted with no lost alert and no duplicate from redelivery |
| Shutdown | Services finish in-flight work and exit within 10 s of SIGTERM |

### Observability

- Structured JSON logs with `monitor_id` and `event_id` on every relevant line.
- Prometheus metrics: checks performed, check duration, failures by error,
  results dropped, consumer lag per group, outbox backlog, notifications sent,
  failed and dead, open stream connections.

---

## 16. Repository and local development

```
beacon/
  cmd/
    api/  checker/  worker/
  internal/
    check/      HTTP check, address validation
    schedule/   claim loop, worker pool
    events/     event types, producer and consumer helpers
    incident/   state machine
    rollup/     minute and day aggregation
    outbox/     relay
    notify/     senders, message templates, retry tiers
    store/      queries (generated) and migrations
    httpapi/    routes, sessions, live gateway
  web/          Next.js app
    e2e/        Playwright specs
    playwright.config.ts
  migrations/
  deploy/
    docker-compose.yml        local: everything
    docker-compose.prod.yml   production overrides
    Caddyfile
  scripts/
    seed.sql                  one user, two monitors, one email channel
    fake-target/              tiny server whose status code you can switch
  .github/workflows/ci.yml
  .env.example
  Makefile                    up, down, migrate, seed, test, lint, e2e
  README.md
```

Compose services: `postgres`, `kafka`, `kafka-init`, `migrate`, `mail`,
`checker`, `worker`, `api`, `web`. Each long-running service has a health
check. Go images are multi-stage builds on a minimal base, running as a
non-root user.

`scripts/fake-target` matters: it is how you make a monitor fail on demand in
development, tests and the demo video.

### Working method

- One branch and one pull request per ticket, even working alone.
- CI must pass before merging: Go tests, lint, Vitest, type check, and the
  Playwright suite once it exists.
- Conventional commit messages with the requirement ID, for example
  `feat(incident): open after threshold (FR-13)`.

---

## 17. Testing

| Level | What | How |
| --- | --- | --- |
| Unit | State machine, address validation, retry tiers, rollup maths, message templates | Go table-driven tests |
| Integration | Each consumer against real Kafka and PostgreSQL | Containers started by the test run |
| Duplicate delivery | Feed each consumer the same event twice | Same database state, one alert |
| Out-of-order and stale | Feed an older `checked_at` after a newer one | Ignored by the detector |
| Crash recovery | Kill a consumer mid-message, restart | No lost incident; no duplicate from redelivery |
| API | Auth, ownership (404 for others' objects), validation errors | HTTP tests against a test database |
| Frontend unit and component | Store updates, form validation, row rendering in each display state, chart maths | Vitest and Testing Library, in watch mode while developing |
| Browser | Sign-in, monitor flows, alert channels, signed-out status page, phone viewport, keyboard-only flow | Playwright against the running Compose stack |
| End to end | Add monitor on the fake target, switch it to 503, see the row turn Down live, the incident, the alert email and the recovery | One Playwright spec in CI, with a longer timeout |
| Load | 200 monitors for 15 minutes | Your Go Load Tester against the fake target |

### Playwright rules

- Tests run against the real stack started by Compose. No mocked API.
- Sign in once in a setup project and reuse the saved session.
- Find elements by role and label, never by CSS class.
- No fixed sleeps. Wait on what the user would see.
- Each test creates its own account or data and passes in any order.
- Record a trace on the first retry and a screenshot on failure; CI uploads both.
- Read mail through the mail catcher's HTTP API; switch the fake target through its control endpoint.

---

## 18. Milestones and acceptance criteria

Six milestones, matching `Beacon_Backlog.md`. The backlog estimates about 160
focused hours without AI assistance, so at 8-10 hours a week plan for about
sixteen weeks, not six. Each milestone ends with something you can show.

### Milestone 1: checker and database

- `make up` starts PostgreSQL and the checker; migrations run.
- Monitors from `seed.sql` are checked on schedule and logged.
- Running two checker containers never checks a monitor twice in one interval.
- Address validation rejects `http://127.0.0.1`, `http://10.0.0.1`,
  `http://169.254.169.254`, `http://[::1]` and a redirect to any of them.

### Milestone 2: Kafka and rollups

- Kafka runs as one KRaft broker; `kafka-init` creates the topics.
- The checker publishes `check.results`; the rollup writer fills both tables.
- Resetting the `beacon.rollup` group to the start and replaying leaves the
  tables unchanged.

### Milestone 3: incidents and alerts

- Switching the fake target to 503 opens exactly one incident after the
  threshold, with `started_at` equal to the first failed check.
- Switching it back resolves the incident after two good checks.
- The seeded email channel receives one "down" and one "recovered" message,
  visible in the local mail catcher.
- A webhook pointed at a closed port is retried at 1, 5 and 25 minutes and
  ends in `notify.dead` with status `dead`.
- Duplicate-delivery, stale-event and crash-recovery tests pass.

### Milestone 4: API and dashboard

- Register, sign in, sign out; add, edit, pause, resume and delete monitors.
- A second account cannot read the first account's monitors (404).
- The list updates live; stopping the API shows "Reconnecting" and recovery
  refreshes the data.
- React profiling shows one row re-rendering per incoming check.
- Loading, empty, Checking and Paused states match section 11.
- Vitest covers the monitor row in every display state.
- Playwright runs in CI: sign-in smoke test and the monitor flows.

### Milestone 5: settings, status page, deployment

- Add, test, pause and remove Email, Slack, Discord and custom channels.
- The incidents page lists incidents with the alerts sent.
- `/status/<slug>` renders signed-out and shows no URLs.
- Playwright covers adding a channel, a test alert and the signed-out page.
- The stack runs on a server behind HTTPS; CI runs on every push.
- Beacon monitors gabrielenache.com and its own `/healthz`.

### Milestone 6: hardening and presentation

- All three Go services shut down cleanly on SIGTERM.
- Load test run; its numbers are in the README.
- README: problem, architecture diagram, one-command start, decisions and
  trade-offs, what you would do next.
- A three-minute demo video and one written article.

---

## 19. Definition of done

- [ ] Every FR, SEC and FE requirement is met, or listed as cut with a reason.
- [ ] Every SEC requirement has a test or a written manual check.
- [ ] A stranger can clone the repository and run it with one command.
- [ ] The live deployment has run for 14 days without manual repair.
- [ ] The README states plainly where Kafka is more than this project needs,
      and why a rare duplicate alert was preferred over a missed one.

---

## 20. Defaults already chosen

Check that each library is still maintained before you commit to it.

| Area | Default | Why |
| --- | --- | --- |
| Go Kafka client | franz-go | Pure Go, supports manual commits and partition pausing |
| Go HTTP router | Standard library `net/http` | Method and path patterns are built in |
| Database access | `pgx` with `sqlc` | You write SQL, it generates typed Go |
| Migrations | goose | Plain SQL files |
| Password hashing | argon2id | Current recommended default |
| Event encoding | JSON with `schema_version` | Readable; mention Protobuf as the next step |
| Reliable publish | Outbox table | Simpler to explain than Kafka transactions |
| Email | SMTP | Works with a local catcher and any provider |
| Styling | Tailwind CSS | You already use it |
| Forms | React Hook Form and Zod | You already use them |
| Server state | TanStack Query | Clear split from the Zustand store |
| Charts | Hand-drawn SVG | A stronger frontend story than a chart library |
| Unit and component tests | Vitest with Testing Library | Fast feedback while developing |
| Browser tests | Playwright (`@playwright/test`) | Real browser against the real stack; traces to debug failures |
| Status page caching | Next.js server caching with a 30 s lifetime | Read the current Next.js caching docs before implementing |
| Reverse proxy | Caddy | Automatic HTTPS |

---

## 21. The hard parts

Plan extra time for these. Each is also an interview story.

1. **Address validation that cannot be bypassed.** Redirects, IPv6 forms and a
   DNS answer that changes between validation and connection all need
   handling. Validate inside the dialer.
2. **Exactly one incident.** The partial unique index is the safety net; the
   row lock on `monitor_state` is what makes the logic correct.
3. **Waiting in a Kafka consumer.** Retry delays longer than the poll interval
   get the consumer removed from its group unless you pause the partition and
   keep polling.
4. **The gap between sending an alert and recording it.** You cannot make an
   external call and a database write atomic. Know which failure you chose.
5. **A live list that stays cheap.** Batching on the server and selectors on
   the client are both needed; measure before and after.
6. **Server-Sent Events through proxies.** Buffering and idle timeouts will
   break the stream until you disable the first and send heartbeats for the
   second.
7. **Graceful shutdown.** Stop claiming work, finish what is in flight, commit
   offsets, close connections, in that order.

---

## 22. Stretch goals, in order

1. Per-monitor alert routing.
2. Keyword check: the response body must contain a given string.
3. TLS certificate expiry warning.
4. A replay screen for `notify.dead`.
5. Password reset by email.
6. Checks from a second region, with an incident only when both agree.
7. Maintenance windows.
