# System Patterns

## Multi-Tenancy

Manual row-level tenancy scoped on `account_id`. No gem — all scoping is explicit in controllers and services.

- `Account` is the tenant root — NOT scoped itself
- Dashboard controllers resolve the tenant via `current_user.account`
- All tenant-scoped queries include an explicit `account_id:` condition or scope
- Background jobs pass the account explicitly and scope queries manually

## Account Resolution

- Dashboard routes use `current_user.account`.
- The public booking page is at `/reservar`.

## Controller Hierarchy

```
ActionController::Base
  └── ApplicationController
        ├── Dashboard::BaseController (authenticate_user!)
        │     ├── Dashboard::BookingsController
        │     ├── Dashboard::CustomersController
        │     ├── Dashboard::ServicesController
        │     ├── Dashboard::StaffController
        │     └── Dashboard::SettingsController
        └── Public::BookingsController  (public, no auth, layout: public)

ActionController::Base (direct, no CSRF)
  └── Webhooks::TwilioController
```

## Job Architecture

All jobs follow the pattern:
1. Find the record by ID (handle nil gracefully — job may be stale)
2. Scope all queries to `record.account` explicitly
3. Do the work
4. Log to `MessageLog` for WhatsApp sends (append-only audit trail)

## Data Money Convention

All monetary amounts stored as **integer cents** (e.g., MXN $250.00 → `25000`).
`money-rails` gem provides `monetize :price_cents` which adds `.price` Money object accessor.
Default currency: MXN.

## Booking State Machine

```
pending → confirmed → completed
       ↘           ↗
        cancelled
        no_show
```

- `Booking#confirm!` sets status=confirmed + confirmed_at
- `Booking#cancel!` sets status=cancelled
- WhatsApp reply "1" → confirm!, "2" → cancel!

## Free Tier Enforcement

- `Account#whatsapp_quota_limit` returns 100 (free) or 1000 (pro)
- `Account#whatsapp_quota_exceeded?` checked before every WhatsApp send
- When exceeded: `ReminderJob` falls back to email, WhatsApp send is skipped
- `Account#whatsapp_quota_used` incremented after each successful send

## Enum Convention

Rails 8 enum syntax:
```ruby
enum :status, { pending: "pending", confirmed: "confirmed" }, default: "pending"
```
String values (not integers) for readability in DB and easier migrations.

## Google Calendar Integration Pattern

Two-way sync per staff member:
1. Staff connects via `Dashboard::GoogleOauthController` — Signet OAuth2, state param signed with HMAC-SHA256
2. `GoogleCalendarService` wraps all API calls; `with_token_refresh` retries once on 401
3. `Booking` model fires `GoogleCalendarSyncJob` on `after_create_commit` / `after_update_commit` / `cancel!`
4. `Booking#skip_google_sync` (attr_accessor) prevents echo-back when the webhook controller updates a booking
5. `Webhooks::GoogleCalendarController` receives push notifications, uses `google_sync_token` for incremental sync
6. `RenewGoogleWatchJob` runs daily to renew push channels before Google's 7-day expiry

Controller hierarchy addition:
```
ActionController::Base (direct, no CSRF)
  └── Webhooks::GoogleCalendarController
```

## Hexagonal Architecture — Infrastructure Layer (LLM pilot)

The app uses a thin hexagonal layer for outbound I/O. ActiveRecord stays as the domain model; the boundary applies to external services only.

### Files
- `lib/citable/container.rb` — `Citable::Container` (dry-container) + `Citable::Import`
- `lib/citable/types.rb` — `Citable::Types` (dry-types)
- `app/infrastructure/llm/port.rb` — `Llm::Port` abstract contract; `Llm::Port::Error`
- `app/infrastructure/llm/response.rb` — `Llm::Response` (Dry::Struct with content, input_tokens, output_tokens, model)
- `app/infrastructure/llm/gemini_adapter.rb` — `Llm::GeminiAdapter < Llm::Port`; registered as `"infrastructure.llm"` in the container

### Port contract
Any adapter must implement `#call(system:, user:, schema:) → Llm::Response` and raise `Llm::Port::Error` on transport/parse failure. Shared contract specs live in `spec/infrastructure/llm/port_contract_spec.rb`.

### Application service pattern (LLM)
All three LLM application services (`Llm::NluParser`, `Llm::QuestionClassifier`, `Llm::GreetingGenerator`) follow the same shape:
- Accept an optional `llm:` kwarg defaulting to `Citable::Container["infrastructure.llm"]`
- Include `Dry::Monads[:result]`
- Return **`Success(hash)`** on success (plain hash, never a Dry::Struct wrapper class) or **`Failure(:tag)`** on miss/error
- **No intermediate Result struct classes** — the hash carries the domain value plus token metadata inline

#### Hash shapes by service
- `NluParser` — `{ value: <Time|Service|Symbol>, input_tokens:, output_tokens:, model: }`
- `QuestionClassifier` — `{ intent: <Symbol>, service: <Service|nil>, input_tokens:, output_tokens:, model: }`
- `GreetingGenerator` — `{ message: <String>, input_tokens:, output_tokens:, model: }`

#### Failure tags
- `:low_confidence` — LLM returned result below MIN_CONFIDENCE threshold
- `:not_a_question` — classifier intent is booking/other (QuestionClassifier only)
- `:blank_message` — LLM returned empty string (GreetingGenerator only)
- `:llm_error` — `Llm::Port::Error` raised (timeout, transport, parse failure)

### Caller convention
Callers unwrap with `.success?` / `.value!`:
```ruby
nlu = Llm::NluParser.parse_service(body, services, account: account)
if nlu.success?
  record_ai_usage(nlu.value!)   # hash
  service = nlu.value![:value]  # domain value
end
```
`record_ai_usage` takes the plain hash and reads `[:input_tokens]`, `[:output_tokens]`, `[:model]`.

### Testing
Specs inject an `instance_double(Llm::Port)` via the `llm:` kwarg; no WebMock or container stubs needed for application-service tests. Container stubs (`Citable::Container.stub`) are available for integration tests via `spec/support/container_helpers.rb`.

## Key Indexes

- `bookings.(account_id, starts_at)` — calendar queries
- `bookings.(user_id, starts_at)` — per-staff calendar
- `customers.(account_id, phone)` — inbound WhatsApp matching
- `customers.custom_fields` — GIN index for JSONB queries
- `customers.tags` — GIN index for array containment queries
- `reminder_schedules.(booking_id, kind)` — unique, prevents duplicate reminders
