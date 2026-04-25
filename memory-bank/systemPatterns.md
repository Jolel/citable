# System Patterns

## Multi-Tenancy

Row-level tenancy via `acts_as_tenant` scoped on `account_id`.

- `Account` is the tenant root — NOT scoped itself
- `User` belongs_to Account via `account_id` — NOT acts_as_tenant (Devise handles auth cross-tenant; scoping is manual)
- All other models use `acts_as_tenant(:account)` which automatically adds `account_id` WHERE clause to every query
- `ActsAsTenant.require_tenant = true` globally in initializer — any query without an active tenant raises an error (security guarantee)
- `ApplicationController#resolve_tenant` sets the current tenant from the subdomain before every request
- Background jobs use `ActsAsTenant.with_tenant(booking.account) { ... }` block

## Subdomain Routing

```
ana.citable.mx → resolves Account with subdomain="ana" → set_current_tenant
```

- `ApplicationController#resolve_tenant` reads `request.subdomain` and calls `set_current_tenant`
- Dashboard routes also use the subdomain to scope queries
- Public booking page is at `/reservar` under the tenant subdomain

## Controller Hierarchy

```
ActionController::Base
  └── ApplicationController          (tenant resolution)
        ├── Dashboard::BaseController (authenticate_user! + require_tenant!)
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
2. Wrap in `ActsAsTenant.with_tenant(record.account)` block
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

## Key Indexes

- `accounts.subdomain` — unique, used on every request for tenant lookup
- `bookings.(account_id, starts_at)` — calendar queries
- `bookings.(user_id, starts_at)` — per-staff calendar
- `customers.(account_id, phone)` — inbound WhatsApp matching
- `customers.custom_fields` — GIN index for JSONB queries
- `customers.tags` — GIN index for array containment queries
- `reminder_schedules.(booking_id, kind)` — unique, prevents duplicate reminders
