# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This App Is

Citable is a WhatsApp-based appointment booking SaaS for Mexican service businesses (salons, etc.). Businesses get a subdomain (e.g., `ana.citable.mx`), define services and staff schedules, and customers book via a public `/reservar` page. The system sends WhatsApp confirmations and reminders via Twilio. Customers reply "1" to confirm or "2" to cancel. Free accounts get 100 WhatsApp messages/month; Pro gets 1000.

## Tech Stack

- **Rails 8.1.3**, Ruby 3.3.6, PostgreSQL
- **Frontend**: Hotwire (Turbo + Stimulus), Tailwind CSS, Importmap (no Node)
- **Auth**: Devise (users), acts_as_tenant (multi-tenancy by subdomain)
- **Background jobs**: Solid Queue (runs inside Puma)
- **External services**: Twilio (WhatsApp), Stripe (deposits), Resend (email fallback)
- **Money**: money-rails, default currency MXN, stored as integer cents
- **Locale/TZ**: `es-MX`, `America/Mexico_City`

## Commands

```bash
bin/setup          # First-time setup
bin/dev            # Start dev server (web + Tailwind CSS watcher via foreman)
bin/rspec          # Run all tests
bundle exec rspec spec/path/to/file_spec.rb  # Single file
bundle exec rspec spec/path/to/file_spec.rb:42  # Single example by line
bin/rubocop        # Lint
bin/brakeman --no-pager  # Security scan
bin/bundler-audit  # Gem vulnerability audit
bin/rails db:migrate
bin/rails db:seed
bin/ci             # Runs full CI locally (security + lint + tests)
```

CI runs: Brakeman → bundler-audit → importmap audit → Rubocop → RSpec with `bin/rails db:test:prepare`.

## Architecture

### Multi-tenancy

`ApplicationController` resolves the tenant from the subdomain via `acts_as_tenant`. All models with tenant scope (`Account`) automatically filter queries. `Dashboard::BaseController` enforces both authentication (Devise) and tenant presence.

### Two Namespaces

- **`/dashboard/*`** — Authenticated owner/staff interface (nested under `Dashboard::` controllers)
- **`/reservar`** — Public customer booking form (Spanish URL, `Public::BookingsController`), scoped to the subdomain's account

### Webhooks (no CSRF / no auth)

- **`/webhooks/twilio`** — Receives WhatsApp replies; "1" confirms a booking, "2" cancels it. Logs to `MessageLog`.
- **`/webhooks/stripe`** — Payment events for deposit handling.

### Background Jobs (Solid Queue)

- **`WhatsappSendJob`** — Sends a WhatsApp message via Twilio REST API, writes a `MessageLog` record, and decrements the account's `whatsapp_quota_used`. Checks quota before sending.
- **`ReminderJob`** — Sends 24h and 2h pre-booking reminders. Falls back to email (Resend) if WhatsApp quota is exhausted.
- **`GoogleCalendarSyncJob`** — Partially implemented; creates/updates Google Calendar events for staff.

### Key Models

| Model | Role |
|---|---|
| `Account` | SaaS tenant root — subdomains, plan, WhatsApp quota |
| `User` | Owner or staff; Devise auth; holds Google OAuth tokens |
| `Booking` | Core entity; statuses: `pending / confirmed / cancelled / completed / no_show` |
| `Customer` | Client contact with phone, tags, custom fields |
| `Service` | Offered service — duration, price (cents), optional deposit, `requires_address` |
| `RecurrenceRule` | Weekly/biweekly/monthly recurrence for bookings |
| `ReminderSchedule` | Reminder timing config per account |
| `StaffAvailability` | Per-user daily working hours |
| `MessageLog` | Audit trail for all WhatsApp/email messages (inbound + outbound) |

### Routes (notable)

Devise is mounted at `/dashboard/auth` with Spanish paths (`entrar`, `salir`, `registrarse`). Routes use Spanish slugs throughout the public-facing side.

## Testing

RSpec with Factory Bot, Capybara (system specs), shoulda-matchers, and database_cleaner (non-transactional — required because system specs use a real browser). SimpleCov tracks coverage but has no enforced minimum.

Spec types are inferred from file paths (`spec/models/` → `:model`, etc.).

## Deployment

Kamal with Docker. Production uses a multi-database PostgreSQL setup: separate databases for the primary app, Solid Cache, Solid Queue, and Solid Cable. Secrets come from `.kamal/secrets`. `RAILS_MASTER_KEY` is required.
