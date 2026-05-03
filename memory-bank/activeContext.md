# Active Context

## Current Focus

Hexagonal architecture pilot (LLM) complete on `feat/ai-nlu-phase1`. Infrastructure layer introduced with `Llm::Port`, `Llm::Response`, `Llm::GeminiAdapter`, and `Citable::Container`. All three LLM application services (`NluParser`, `QuestionClassifier`, `GreetingGenerator`) now return `Success(hash)` / `Failure(:tag)` via dry-monads rather than nil-or-struct. Dry::Struct `Result` wrapper classes removed from application services; token metadata lives inline in the Success hash. Next step: replicate the pattern for WhatsApp/Twilio (outbound port + adapter).

## What Was Just Built

### Hexagonal Infrastructure Layer — LLM Pilot (feat/ai-nlu-phase1)

#### New files
- `lib/citable/container.rb` — `Citable::Container` (dry-container), `"infrastructure.llm"` registered
- `lib/citable/types.rb` — `Citable::Types` (dry-types)
- `app/infrastructure/llm/port.rb` — abstract `Llm::Port` + `Llm::Port::Error`
- `app/infrastructure/llm/response.rb` — `Llm::Response` (Dry::Struct)
- `app/infrastructure/llm/gemini_adapter.rb` — `Llm::GeminiAdapter < Llm::Port`
- `config/initializers/container.rb` — to_prepare hook
- `spec/infrastructure/llm/{gemini_adapter,port_contract}_spec.rb`
- `spec/support/container_helpers.rb`

#### Modified
- `Llm::NluParser`, `Llm::QuestionClassifier`, `Llm::GreetingGenerator` — accept `llm:` kwarg; return `Success(hash)` / `Failure(:tag)`; no Dry::Struct Result wrapper
- `TwilioWebhook::AdvanceConversation`, `TwilioWebhook::StartConversation` — unwrap via `.success?` / `.value!`; `record_ai_usage` takes plain hash

#### Deleted
- `app/services/llm/client.rb` + `spec/services/llm/client_spec.rb`

#### Gems added
- `dry-container`, `dry-auto_inject`, `dry-struct`

### AI NLU Phase 2 — Question Answering (feat/ai-nlu-phase1)

#### Migration (`db/migrate/20260430000000_add_question_answering_fields.rb`)
- Adds `services.description` (text, nullable) — surfaced when answering "qué servicios tienen" and price/duration questions.
- Adds `accounts.business_hours` (jsonb, default `{}`) — keyed by `mon..sun` with values `["09:00","19:00"]` for open days or `nil` for closed.

#### Services
- `Llm::QuestionClassifier` — single Gemini call returning `{ intent, service_index, confidence }`. Intents: `services_list`, `price`, `duration`, `hours` (answerable) plus `booking`, `other` (fall through). Same 0.8 confidence threshold and silent-fallback contract as `Llm::NluParser`.
- `TwilioWebhook::AnswerQuestion` — pure-Ruby Spanish renderer. No LLM call; reads `Service` and `Account#business_hours` and always appends "¿Quieres reservar una cita?". Eliminates hallucination risk.
- `TwilioWebhook::StartConversation` — accepts `body:`; if AI is enabled and the classifier returns a question intent, sends the answer via `Whatsapp::MessageSender` and returns `Success(:answered_question)` **without creating a `WhatsappConversation`** so the next message can either ask another question or start booking. Stamps token usage on the inbound `MessageLog` via the existing `record_ai_usage` helper.
- `TwilioWebhook::HandleReply` — passes `body:` through to `StartConversation`.

#### Dashboard surfaces
- `Dashboard::ServicesController` strong params + `_form.html.erb` expose `Service#description`.
- `Dashboard::SettingsController` + `settings/show.html.erb` expose a weekly hours editor (open/close `<input type="time">` per weekday + "Cerrado" checkbox); `normalize_business_hours` collapses the nested params into the storage shape.

#### Specs (374 examples, all green)
- `spec/services/llm/question_classifier_spec.rb` (new)
- `spec/services/twilio_webhook/answer_question_spec.rb` (new)
- `spec/services/twilio_webhook/start_conversation_spec.rb` (extended with question-branch examples)

#### Documentation
- `docs/manual-local.md` updated with verification item #10, a new "Question answering before booking" subsection under section 8, and two troubleshooting entries.

### WhatsApp Guided Booking Flow (staged on main)

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

- **Question answering now runs both before and during a booking conversation.** `AdvanceConversation#call` intercepts FAQ questions (price, duration, services list, hours) before dispatching to the step handler. It answers the question, re-sends the current step prompt, and returns `Success(:answered_question)` without advancing the step. Confirmation digits `"1"`/`"2"` bypass the classifier (fast path). Non-question intents (`booking`, `cancel`, `other`, LLM failure) fall through to the step handler unchanged. Legacy confirm/cancel flow is unaffected.
- **LLM classifies, Ruby renders.** `Llm::QuestionClassifier` returns a structured intent + service index; `TwilioWebhook::AnswerQuestion` formats the answer from the database. No LLM-generated free-text in answers — eliminates hallucination and keeps token cost low.
- **Question-branch answers do not create `WhatsappConversation` rows.** Keeps Q&A stateless so the next message can either ask another question or start booking naturally.
- **Question scope v1: services list/descriptions, price, duration, business hours.** Location/address answers were explicitly deferred (no `Account#address` field added).

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
