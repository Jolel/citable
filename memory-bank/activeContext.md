# Active Context

## Current Focus

WhatsApp guided booking flow implemented (staged, not yet merged). Each business now has its own `whatsapp_number` on `Account`; inbound messages map the `To` field to an account and walk the customer through service → datetime → address (if needed) → confirmation. The booking calendar (`Day` + `Week` views, drag-and-drop) was completed in the previous phase.

## What Was Just Built

### WhatsApp Guided Booking Flow (staged on main)

#### Migration (`db/migrate/20260425001000_add_whatsapp_booking_flow.rb`)
- Adds `accounts.whatsapp_number` (string, unique index) — used to route inbound `To` → `Account`.
- Creates `whatsapp_conversations` table: `account_id`, `customer_id`, `service_id`, `booking_id`, `from_phone`, `step`, `requested_starts_at`, `address`, `metadata` (jsonb), timestamps.

#### Models
- `Account` — gains `whatsapp_number` with normalization (`normalize_whatsapp_number`) and uniqueness validation. Seeds set Ana's account to `14155238886` (Twilio Sandbox).
- `WhatsappConversation` — new model; steps: `awaiting_name`, `awaiting_service`, `awaiting_datetime`, `awaiting_address`, `confirming_booking`, `completed`, `cancelled`. Expires after 30 min of inactivity (`active` + `open` scopes).

#### Services
- `TwilioWebhook::HandleReply` — rewritten. Accepts `from:`, `to:`, `body:`. Resolves account from `to`, finds customer within account, resumes or starts a conversation. Falls back to legacy confirm/cancel if customer has an active upcoming booking and no active conversation.
- `Whatsapp::MessageSender` — new service. Checks quota, sends via Twilio REST API, creates `MessageLog` outbound record, increments `whatsapp_quota_used`. Used by `HandleReply` for all outbound conversation messages.

#### Jobs
- `WhatsappSendJob` — now delegates send to `Whatsapp::MessageSender` internally (reuses the same sender path for booking confirmation/reminder templates).

### Previous Foundation (db/migrate/)
12 migrations total (1–11 as before, plus 12 = `add_whatsapp_booking_flow`).

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
- `ApplicationController` — shared browser and importmap behavior
- `Dashboard::BaseController` — authenticate_user! + tenant guard
- `Dashboard::BookingsController` — full CRUD + confirm/cancel actions
- `Dashboard::CustomersController` — full CRUD + search + tag filter
- `Dashboard::ServicesController` — full CRUD + toggle_active
- `Dashboard::StaffController` — owner-only, full CRUD
- `Dashboard::SettingsController` — owner-only account settings
- `Public::BookingsController` — public booking page (new/create/confirmation)
- `Webhooks::TwilioController` — inbound WhatsApp reply handler (1=confirm, 2=cancel)

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
Creates: Account "Estudio de Ana", owner user ana@example.com, staff maria@example.com, 3 services, staff availabilities Mon-Sat, 2 customers, 1 sample booking.

## Next Steps

### Immediate (to boot and test)
1. Run in terminal: `rails db:create db:migrate db:seed` (if not done)
2. `bin/dev` — Rails + TailwindCSS watcher
3. Visit `http://localhost:3000/dashboard/auth/entrar`

### Near-term (integrations)
- Add Google credentials (`rails credentials:edit`: `google.client_id`, `google.client_secret`, `google.webhook_token`)
- Configure Google Cloud Project: enable Calendar API, add OAuth redirect URIs
- Add Twilio WhatsApp credentials + test message templates
- Add Resend email credentials

### Design system notes
- **Palette**: forest `#1B3532` (sidebar), brand `#C4522A` (CTA/terracotta), cream `#FAF7F2` (bg), amber `#E8A838` (pending)
- **Fonts**: Fraunces italic (display/brand), Plus Jakarta Sans (UI) — loaded via Google Fonts
- **Custom Tailwind classes**: `bg-brand`, `text-forest`, `bg-cream`, `font-fraunces`, `font-jakarta`, etc. (defined in `@theme`)

### Before Production
- Add Twilio credentials
- Add Resend credentials
- Submit WhatsApp message templates to Meta for approval
- Set up Google OAuth for Calendar sync
- Write RSpec tests, especially cross-tenant isolation tests

## Active Decisions

- **Each business has its own `Account.whatsapp_number`** (normalized digits only, unique). Inbound `To` is matched against this column; unknown numbers are silently ignored (return 200).
- **WhatsApp conversation state lives in `whatsapp_conversations`**, not in `Customer` or session. Expires after 30 min inactivity. A customer can have at most one active open conversation per account.
- **Guided booking takes priority over legacy confirm/cancel** only if an active conversation already exists. If no conversation and customer has an active upcoming booking, legacy confirm/cancel still applies.
- **Staff assignment is automatic** — owner first, then by name/id. No manual selection in v1.
- **Date/time parsing is conservative** — only `YYYY-MM-DD HH:MM`, `DD/MM/YYYY HH:MM`, and `mañana HH:MM` are accepted. Unknown formats re-prompt rather than guess.
- **`Whatsapp::MessageSender`** is the single outbound path for all WhatsApp sends (conversations + `WhatsappSendJob` templates). Quota check and `MessageLog` creation happen inside it.

- **Email for `User` must be unique globally**, not just per-tenant. Devise requires this. Users can belong to one account only.
- **`deposit_state` enum** uses prefixed values (`deposit_pending`, `deposit_paid`, `deposit_refunded`) to avoid conflict with `:pending` status enum on same model.
- **Public booking page** is available at `/reservar` and has no auth requirement.
- **`Customer.find_or_create_by!(phone:)`** in the public flow — phone is the customer identifier since they come from WhatsApp.
- **Google OAuth uses manual Signet controller** (no OmniAuth gem) — `Dashboard::GoogleOauthController` handles connect/callback/disconnect. OAuth redirect URI is `/dashboard/google_oauth/callback`.
- **Google OAuth state** is HMAC-SHA256 signed with `secret_key_base` to prevent CSRF on the callback.
- **Google Calendar sync is per-staff**, not per-account. Each staff member connects their own Google account.
- **`Booking#skip_google_sync`** attr_accessor prevents infinite loop when the webhook controller updates a booking time received from Google.
- **Google tokens encrypted** at rest via `encrypts :google_oauth_token`, `:google_refresh_token`, `:google_sync_token` — requires `active_record.encryption.*` keys in credentials.
- **Dashboard booking calendar v1** will be built as a native Rails + Hotwire + Stimulus experience, not a third-party embedded calendar.
- **Booking calendar v1 scope** is `Day` + `Week` only; `Month` is intentionally deferred but the range-query/event serialization should be designed to support it later.
- **Calendar drag-and-drop saves immediately** on drop; no confirmation modal.
- **Calendar layout uses staff columns** so bookings can move across collaborators directly.
- **Calendar conflicts are warnings, not blockers**: overlap and outside-availability states should persist and be surfaced clearly in the UI.
- **Calendar implementation structure** currently uses `Dashboard::BookingCalendarController`, `Bookings::RescheduleFromCalendar`, and `Bookings::CalendarPlacementWarnings`, plus a Stimulus controller for drag/drop and inline UI updates.

## Google Calendar — Out of Scope (v1)

- Importing existing Google Calendar events into Citable
- Syncing recurring bookings as Google recurring events (synced as individual events)
- Customer receiving a Google Calendar invite
- Conflict detection against non-Citable events on the Google Calendar
