# Active Context

## Current Focus

Google OAuth2 + Calendar sync feature complete. Next phase is Twilio WhatsApp, Stripe deposits, and production readiness.

## What Was Just Built (Foundation)

### Migrations (db/migrate/)
11 migrations total:
1. `create_accounts` — tenant root
2. `devise_create_users` — auth + custom fields
3. `create_services`
4. `create_staff_availabilities`
5. `create_customers` — JSONB custom_fields, text[] tags, GIN indexes
6. `create_recurrence_rules`
7. `create_bookings` — full state + deposit tracking
8. `create_message_logs` — append-only audit trail
9. `create_reminder_schedules` — unique per booking+kind
10. `add_google_watch_fields_to_users` — adds google_token_expires_at, google_channel_id, google_channel_expires_at, google_sync_token
11. `add_google_token_expires_at_to_users` — duplicate of column in migration 10; **bug: will fail on fresh db:migrate**

### Models (app/models/)
- `Account` — validations, free/pro tier logic, quota check
- `User` — Devise, owner/staff enum, google_connected?
- `Service` — monetize price + deposit, duration_label
- `StaffAvailability` — day_of_week 0-6, time range validation
- `Customer` — phone validation, tag scopes, normalized_phone
- `RecurrenceRule` — weekly/biweekly/monthly, next_occurrence_after
- `Booking` — full state machine, confirm!/cancel!, auto set_ends_at
- `MessageLog` — channel/direction/status validations, scopes
- `ReminderSchedule` — kind 24h/2h, unique per booking, mark_sent!

### Controllers
- `ApplicationController` — subdomain-based tenant resolution
- `Dashboard::BaseController` — authenticate_user! + tenant guard
- `Dashboard::BookingsController` — full CRUD + confirm/cancel actions
- `Dashboard::CustomersController` — full CRUD + search + tag filter
- `Dashboard::ServicesController` — full CRUD + toggle_active
- `Dashboard::StaffController` — owner-only, full CRUD
- `Dashboard::SettingsController` — owner-only account settings
- `Public::BookingsController` — public booking page (new/create/confirmation)
- `Webhooks::TwilioController` — inbound WhatsApp reply handler (1=confirm, 2=cancel)
- `Webhooks::StripeController` — payment_intent.succeeded → deposit_paid + confirm

### Jobs (app/jobs/)
- `ReminderJob` — routes to WhatsApp or email fallback, marks sent
- `WhatsappSendJob` — Twilio integration, MessageLog creation, quota increment
- `GoogleCalendarSyncJob` — full implementation; called on booking create/update/cancel via after_create_commit/after_update_commit callbacks
- `RenewGoogleWatchJob` — daily recurring; renews Google push notification channels before 7-day expiry

### Config
- `config/initializers/devise.rb` — standard Devise config, es-MX mailer
- `config/initializers/acts_as_tenant.rb` — require_tenant = true
- `config/initializers/money.rb` — MXN default currency
- `config/queue.yml` — 3 named queues: reminders, notifications, default
- `config/recurring.yml` — `RenewGoogleWatchJob` runs daily at 2am
- `config/application.rb` — timezone=Mexico_City, locale=es-MX
- `config/routes.rb` — dashboard namespace, public booking, webhooks, Devise, Google OAuth

### Seeds (db/seeds.rb)
Creates: Account "Estudio de Ana" (subdomain: ana), owner user ana@example.com, staff maria@example.com, 3 services, staff availabilities Mon-Sat, 2 customers, 1 sample booking.

## Next Steps

### Immediate (to boot and test)
1. Run in terminal: `rails db:create db:migrate db:seed` (if not done)
2. `bin/dev` — Rails + TailwindCSS watcher
3. Visit `http://ana.localhost:3000/dashboard/auth/entrar`

### Near-term (integrations)
- Add Google credentials (`rails credentials:edit`: `google.client_id`, `google.client_secret`, `google.webhook_token`)
- Configure Google Cloud Project: enable Calendar API, add OAuth redirect URIs
- Add Twilio WhatsApp credentials + test message templates
- Add Stripe Mexico credentials + test deposit flow
- Add Resend email credentials

### Design system notes
- **Palette**: forest `#1B3532` (sidebar), brand `#C4522A` (CTA/terracotta), cream `#FAF7F2` (bg), amber `#E8A838` (pending)
- **Fonts**: Fraunces italic (display/brand), Plus Jakarta Sans (UI) — loaded via Google Fonts
- **Custom Tailwind classes**: `bg-brand`, `text-forest`, `bg-cream`, `font-fraunces`, `font-jakarta`, etc. (defined in `@theme`)

### Before Production
- Add Stripe credentials: `rails credentials:edit`
- Add Twilio credentials
- Add Resend credentials
- Submit WhatsApp message templates to Meta for approval
- Set up Stripe Mexico account
- Configure subdomain routing (Cloudflare or DNS)
- Set up Google OAuth for Calendar sync
- Write RSpec tests, especially cross-tenant isolation tests

## Active Decisions

- **Email for `User` must be unique globally**, not just per-tenant. Devise requires this. Users can belong to one account only.
- **`deposit_state` enum** uses prefixed values (`deposit_pending`, `deposit_paid`, `deposit_refunded`) to avoid conflict with `:pending` status enum on same model.
- **Public booking page** uses subdomain tenant resolution (same as dashboard) but has no auth requirement.
- **`Customer.find_or_create_by!(phone:)`** in the public flow — phone is the customer identifier since they come from WhatsApp.
- **Google OAuth uses manual Signet controller** (no OmniAuth gem) — `Dashboard::GoogleOauthController` handles connect/callback/disconnect. OAuth redirect URI is `/dashboard/google_oauth/callback` (fixed host, no subdomain).
- **Google OAuth state** is HMAC-SHA256 signed with `secret_key_base` to prevent CSRF on the callback.
- **Google Calendar sync is per-staff**, not per-account. Each staff member connects their own Google account.
- **`Booking#skip_google_sync`** attr_accessor prevents infinite loop when the webhook controller updates a booking time received from Google.
- **Google tokens encrypted** at rest via `encrypts :google_oauth_token`, `:google_refresh_token`, `:google_sync_token` — requires `active_record.encryption.*` keys in credentials.

## Google Calendar — Out of Scope (v1)

- Importing existing Google Calendar events into Citable
- Syncing recurring bookings as Google recurring events (synced as individual events)
- Customer receiving a Google Calendar invite
- Conflict detection against non-Citable events on the Google Calendar
