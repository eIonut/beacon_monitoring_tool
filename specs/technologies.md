- POSTGRESQL
- Go

- React
- Zustand
- Zod
- Tanstack Query
- React Hook Form
- React Router
- Lucide React

- Docker
- Redis
- Kafka

- Resend

- Playwright
- Vitest

## 20. Defaults already chosen

Check that each library is still maintained before you commit to it.

| Area                     | Default                                     | Why                                                           |
| ------------------------ | ------------------------------------------- | ------------------------------------------------------------- |
| Go Kafka client          | franz-go                                    | Pure Go, supports manual commits and partition pausing        |
| Go HTTP router           | Standard library `net/http`                 | Method and path patterns are built in                         |
| Database access          | `pgx` with `sqlc`                           | You write SQL, it generates typed Go                          |
| Migrations               | goose                                       | Plain SQL files                                               |
| Password hashing         | argon2id                                    | Current recommended default                                   |
| Event encoding           | JSON with `schema_version`                  | Readable; mention Protobuf as the next step                   |
| Reliable publish         | Outbox table                                | Simpler to explain than Kafka transactions                    |
| Email                    | SMTP                                        | Works with a local catcher and any provider                   |
| Styling                  | Tailwind CSS                                | You already use it                                            |
| Forms                    | React Hook Form and Zod                     | You already use them                                          |
| Server state             | TanStack Query                              | Clear split from the Zustand store                            |
| Charts                   | Hand-drawn SVG                              | A stronger frontend story than a chart library                |
| Unit and component tests | Vitest with Testing Library                 | Fast feedback while developing                                |
| Browser tests            | Playwright (`@playwright/test`)             | Real browser against the real stack; traces to debug failures |
| Status page caching      | Next.js server caching with a 30 s lifetime | Read the current Next.js caching docs before implementing     |
| Reverse proxy            | Caddy                                       | Automatic HTTPS                                               |

---
