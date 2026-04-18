# Progress

## Status: Foundation Complete — UI Not Yet Built

## What Works (Code Written, Needs `db:migrate` to Run)

- [x] Rails 8.1.3 app created with PostgreSQL + TailwindCSS + Solid Queue
- [x] All gems installed: devise, acts_as_tenant, stripe, twilio-ruby, resend, money-rails
- [x] All 9 database migrations written
- [x] All 9 models with associations, enums, validations, scopes
- [x] Devise configuration (initializer)
- [x] acts_as_tenant configured (require_tenant = true)
- [x] money-rails configured (MXN default)
- [x] ApplicationController with subdomain tenant resolution
- [x] Dashboard controllers (bookings, customers, services, staff, settings)
- [x] Public booking controller
- [x] Webhook controllers (Twilio inbound, Stripe payment events)
- [x] ReminderJob with WhatsApp/email routing
- [x] WhatsappSendJob with Twilio integration + MessageLog audit
- [x] GoogleCalendarSyncJob (stub ready for implementation)
- [x] Solid Queue config with named queues
- [x] Routes (dashboard namespace, public booking, webhooks, Devise)
- [x] Application timezone (Mexico City) and locale (es-MX)
- [x] Seeds with "Ana" persona data

## What Needs to Be Done

### Before the app can boot
- [ ] Run `rails db:create db:migrate db:seed` in terminal
- [ ] Run `rails generate devise:views` for auth pages

### UI (next major phase)
- [ ] `app/views/layouts/application.html.erb` — update for TailwindCSS + Turbo
- [ ] `app/views/layouts/dashboard.html.erb` — sidebar nav, responsive
- [ ] `app/views/layouts/public.html.erb` — mobile-first, Spanish
- [ ] Dashboard views: bookings/index, bookings/show, customers/index, etc.
- [ ] Public booking page: service picker → time slot picker → form → confirmation
- [ ] Devise views customized in Spanish

### Integrations (when credentials are added)
- [ ] Twilio WhatsApp templates submitted to Meta
- [ ] Stripe Mexico account + webhooks configured
- [ ] Resend email templates for fallback reminders
- [ ] Google OAuth2 flow for Calendar sync

### Production Readiness
- [ ] RSpec test suite (especially cross-tenant isolation tests)
- [ ] Brakeman security scan
- [ ] Rubocop lint
- [ ] Sentry error monitoring
- [ ] CI (GitHub Actions)
- [ ] Hatchbox/Render deployment

## Known Issues / TODOs in Code

- `WhatsappSendJob`: message templates in `build_message` are placeholders, need to match Twilio-approved templates exactly
- `GoogleCalendarSyncJob`: `create_event`/`update_event` are stubs — need `google-api-ruby-client` gem added
- `Public::BookingsController#find_or_create_customer`: phone uniqueness is global, should validate format before lookup
- `Dashboard::BookingsController#schedule_reminders`: should check if `starts_at` is in the past before enqueuing
- Devise `email` uniqueness is global (not per-tenant) — acceptable for v1, may need per-tenant email in v2

## Phased Roadmap Alignment

- **MVP** (~8-10 wks): Foundation done ✓. UI, WhatsApp, Stripe, Google Cal remain.
- **v1.1**: MercadoPago, SMS fallback, CSV import
- **v1.2**: Customer segments, bulk WhatsApp broadcasts, analytics
- **v2**: WhatsApp chatbot booking, LATAM expansion, CFDI
