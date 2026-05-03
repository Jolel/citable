# Progress

## Status: Foundation Complete — UI Not Yet Built

## What Works (Code Written, Needs `db:migrate` to Run)

- [x] Rails 8.1.3 app created with PostgreSQL + TailwindCSS + Solid Queue
- [x] All gems installed: devise, acts_as_tenant, twilio-ruby, resend, money-rails
- [x] Database migrations written
- [x] All 9 models with associations, enums, validations, scopes
- [x] Devise configuration (initializer)
- [x] acts_as_tenant configured (require_tenant = true)
- [x] money-rails configured (MXN default)
- [x] Dashboard account access through the signed-in user
- [x] Dashboard controllers (bookings, customers, services, staff, settings)
- [x] Public booking controller
- [x] Webhook controllers (Twilio inbound)
- [x] ReminderJob with WhatsApp/email routing
- [x] WhatsappSendJob with Twilio integration + MessageLog audit (now delegates send to `Whatsapp::MessageSender`)
- [x] WhatsApp guided booking flow: `Account.whatsapp_number`, `WhatsappConversation` model, rewritten `TwilioWebhook::HandleReply`, new `Whatsapp::MessageSender` service
- [x] GoogleCalendarSyncJob (fully implemented — create/update/cancel sync)
- [x] Solid Queue config with named queues
- [x] Routes (dashboard namespace, public booking, webhooks, Devise, Google OAuth)
- [x] Application timezone (Mexico City) and locale (es-MX)
- [x] Seeds with "Ana" persona data
- [x] Google OAuth2 + Calendar sync (11 migrations total; `Dashboard::GoogleOauthController` — manual Signet flow, no OmniAuth)
- [x] `RenewGoogleWatchJob` — daily job renewing push channels before Google's 7-day expiry

## What Needs to Be Done

### Before the app can boot
- [ ] Run `bin/rails db:migrate db:seed` (or `bin/setup --skip-server` on a fresh clone)
- [ ] Run `rails generate devise:views` for auth pages if views are missing

### UI (completed)
- [x] `app/views/layouts/application.html.erb` — Tailwind v4 theme, Google Fonts (Fraunces + Plus Jakarta Sans)
- [x] `app/views/layouts/dashboard.html.erb` — forest sidebar + cream content, mobile drawer (Stimulus)
- [x] `app/views/layouts/public.html.erb` — mobile-first, Spanish, privacy footer
- [x] Dashboard bookings: index (filter tabs, booking rows), show (confirm/cancel actions), new, edit, _form
- [x] Dashboard customers: index (search), show (profile + history), new, edit, _form
- [x] Dashboard services: index (cards + toggle), new, edit, _form
- [x] Public booking page: 3-step flow (service → datetime → customer details), Stimulus controller
- [x] Public confirmation page: WhatsApp reminder info
- [x] Devise views: sessions/new, registrations/new+edit, passwords/new+edit — all in Spanish
- [x] `ApplicationHelper`: `dashboard_nav_link`, `booking_status_badge`, `whatsapp_link`
- [x] Stimulus controllers: `sidebar_controller.js`, `booking_flow_controller.js`
- [x] Tailwind v4 `@theme`: brand colors + custom fonts

### Integrations (when credentials are added)
- [ ] Twilio WhatsApp templates submitted to Meta
- [ ] Resend email templates for fallback reminders
- [x] Google OAuth2 flow for Calendar sync (code complete — needs credentials + Google Cloud Project setup)

### Production Readiness
- [ ] RSpec test suite (especially cross-tenant isolation tests)
- [ ] Brakeman security scan
- [ ] Rubocop lint
- [ ] Sentry error monitoring
- [ ] CI (GitHub Actions)
- [ ] Hatchbox/Render deployment
- [x] Dashboard booking calendar (`Day` + `Week`) with drag-and-drop rescheduling and warning states

## Known Issues / TODOs in Code

- `WhatsappSendJob`: message templates in `build_message` are placeholders, need to match Twilio-approved templates exactly
- `Public::BookingsController#find_or_create_customer`: phone uniqueness is global, should validate format before lookup
- `Dashboard::BookingsController#schedule_reminders`: should check if `starts_at` is in the past before enqueuing
- Devise `email` uniqueness is global (not per-tenant) — acceptable for v1, may need per-tenant email in v2
- **Duplicate migration bug**: migrations 10 (`add_google_watch_fields_to_users`) and 11 (`add_google_token_expires_at_to_users`) both add the `google_token_expires_at` column — fresh `db:migrate` will fail on migration 11. Fix: remove the duplicate `add_column` from migration 11 or squash it.
- Google Calendar: needs Rails encryption keys in credentials (`active_record.encryption.*`) for `encrypts :google_oauth_token` etc.
- Google Calendar: `RenewGoogleWatchJob` uses `default_url_options[:host]` — must be configured in production env

## Recently Specified

- `docs/superpowers/specs/2026-04-23-booking-calendar-day-week-design.md` defines a native dashboard calendar for bookings with:
  - `Lista`, `Día`, and `Semana` modes
  - collaborator columns
  - drag-and-drop rescheduling with immediate save
  - warnings for overlaps and outside-availability placements
  - explicit future seams for a month view

## Recently Built

- Security audit fixes (2026-05-02) — 15 findings closed in one bundled change:
  - **HIGH** Public account resolution → `/r/:account_whatsapp/...` (was `Account.order(:id).first`)
  - **HIGH** Confirmation IDOR → `confirmation_token` column (`has_secure_token`); URL is `/confirmada/:token`
  - **HIGH** Public mass-assignment → drop `:user_id`/`:service_id` from permit; re-resolve service through `@account.services.active`; auto-pick staff via new `PublicBookings::StaffPicker`
  - **HIGH** Reply hijack → `MessageLog.kind` column + `HandleReply#resolve_reply_booking` binds 1/2 to the most recent outbound prompt for the customer (36h window), not earliest by `starts_at`
  - **HIGH** Dashboard cross-tenant FKs → `Dashboard::BookingsController#scoped_associations` re-resolves customer/service/user/recurrence_rule via `current_account` collections; `:status` removed from permit; new `mark_completed!`/`mark_no_show!` member actions
  - **MEDIUM** Production HTTPS/HSTS → `config.assume_ssl`/`config.force_ssl`/`ssl_options` now active in production.rb; new `config/initializers/session_store.rb` with Secure+SameSite=Lax+HttpOnly
  - **MEDIUM** Twilio fail-closed → token re-read from credentials per request (no class-load capture); blank token returns 503; new `config/initializers/twilio.rb` boot-time assertion
  - **MEDIUM** Email injection in reminder → unsanitized interpolation replaced with `CGI.escapeHTML` for owner name, customer name, phone, and time; `Customer#name` validation rejects `<` and `>`, caps length at 80
  - **MEDIUM** OAuth confused deputy → state token now binds `initiator_id` + `nonce` + `iat`; callback rejects on mismatch or expiry; `connect` route is now `POST` (CSRF-protected); session stores per-flow nonce; `extract_path` rejects non-`/dashboard/` redirects
  - **MEDIUM** Backdated bookings → `Booking#starts_at_in_future` validation on create; `schedule_reminder_jobs` skips past `wait_until`s; `ReminderJob#perform` no-ops on past bookings
  - **MEDIUM** Staff password bypass → `:password`/`:password_confirmation` removed from update params; new `Dashboard::StaffController#reset_password` member action triggers Devise password-reset email; `:confirmable` enabled on User with `reconfirmable: true` so email change requires clicking a link in the new mailbox
  - **MEDIUM** Services controller missing owner gate → new `Dashboard::OwnerOnly` concern; ServicesController applies it via `before_action :require_owner!, only: %i[new create edit update deactivate toggle_active]`; SettingsController and StaffController use the same concern
  - **LOW** Booking status mass-assign → `:status` removed from `Dashboard::BookingsController#booking_params`; transitions only via `confirm`/`cancel`/`mark_completed`/`mark_no_show` member actions
  - **LOW** Quota race → `Whatsapp::MessageSender` claims a quota slot via atomic `UPDATE ... WHERE quota_used < limit`; failed sends release the slot back; missing credentials fail before claim
  - **LOW** Google webhook unscoped lookup → `process_event` now uses `user.account.bookings.find_by(google_event_id: ..., user_id: user.id)`; controller action renamed `receive` → `create` to match route; new unique partial index on `bookings(account_id, google_event_id)`
- Migrations added: `20260502000001_add_confirmation_token_to_bookings`, `20260502000002_add_kind_to_message_logs`, `20260502000003_add_google_event_unique_index_to_bookings`, `20260502000004_add_devise_confirmable_to_users`


- WhatsApp guided booking flow (staged on main, 2026-04-25):
  - `Account.whatsapp_number` — unique column; seeds set Ana's account to `14155238886`
  - `WhatsappConversation` model — guided steps, 30-min expiry, `active`/`open` scopes
  - `TwilioWebhook::HandleReply` — rewritten to resolve account from `To`, route to conversation or legacy confirm/cancel
  - `Whatsapp::MessageSender` — centralized outbound sender (quota check, Twilio API, MessageLog)
  - `WhatsappSendJob` — now uses `MessageSender` internally

- Dashboard booking calendar first pass:
  - `GET /dashboard/calendar` renders `Día` and `Semana`
  - `PATCH /dashboard/calendar/events/:id` updates bookings immediately from the calendar
  - `Bookings::RescheduleFromCalendar` preserves duration while moving across times/collaborators
  - `Bookings::CalendarPlacementWarnings` flags overlap and outside-availability states
  - Stimulus-based drag/drop updates the booking card inline after save

## Phased Roadmap Alignment

- **MVP** (~8-10 wks): Foundation done ✓. UI, WhatsApp, cash-payment polish, Google Cal remain.
- **v1.1**: MercadoPago, SMS fallback, CSV import
- **v1.2**: Customer segments, bulk WhatsApp broadcasts, analytics
- **v2**: WhatsApp chatbot booking, LATAM expansion, CFDI
