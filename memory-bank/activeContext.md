# Active Context

## Current Focus

Foundation complete. Next phase is building the UI (views, layouts, components).

## What Was Just Built (Foundation)

### Migrations (db/migrate/)
All 9 migrations written, ready to run:
1. `create_accounts` — tenant root
2. `devise_create_users` — auth + custom fields
3. `create_services`
4. `create_staff_availabilities`
5. `create_customers` — JSONB custom_fields, text[] tags, GIN indexes
6. `create_recurrence_rules`
7. `create_bookings` — full state + deposit tracking
8. `create_message_logs` — append-only audit trail
9. `create_reminder_schedules` — unique per booking+kind

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
- `GoogleCalendarSyncJob` — stub, ready for google-api-ruby-client integration

### Config
- `config/initializers/devise.rb` — standard Devise config, es-MX mailer
- `config/initializers/acts_as_tenant.rb` — require_tenant = true
- `config/initializers/money.rb` — MXN default currency
- `config/queue.yml` — 3 named queues: reminders, notifications, default
- `config/recurring.yml` — placeholder
- `config/application.rb` — timezone=Mexico_City, locale=es-MX
- `config/routes.rb` — dashboard namespace, public booking, webhooks, Devise

### Seeds (db/seeds.rb)
Creates: Account "Estudio de Ana" (subdomain: ana), owner user ana@example.com, staff maria@example.com, 3 services, staff availabilities Mon-Sat, 2 customers, 1 sample booking.

## Next Steps

### Immediate (to get a running app)
1. Run in terminal: `rails db:create db:migrate db:seed`
2. Add Devise views: `rails generate devise:views`
3. Create layouts: `app/views/layouts/dashboard.html.erb` + `public.html.erb`
4. Create dashboard home view (booking calendar/list)
5. Create public booking page view

### Near-term UI priorities
- Dashboard layout with sidebar navigation
- Booking index (today + upcoming calendar view)
- Customer list with search
- Service list + edit form
- Public booking page (mobile-first, Spanish, service picker + time slots)

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
