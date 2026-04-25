# Google OAuth2 + Calendar Sync — Design Spec
**Date:** 2026-04-18
**Status:** Approved

---

## Overview

Implement Google Calendar two-way sync for Citable. Each staff member (or their account owner) connects their Google account via OAuth2. A dedicated "Citable" calendar is created in their Google account. Bookings are pushed to Google Calendar on create/update/cancel. Changes made on the Google Calendar side (reschedule, delete) are reflected back in Citable via Google push notifications.

---

## Decisions Made

| Question | Decision |
|---|---|
| Sync direction | True two-way |
| Who connects | Self-service (staff) and owner-managed |
| Which calendar | Dedicated "Citable" calendar per staff member |
| Cancel behavior | Keep event, prefix title with ❌ |
| Google → Citable delete | Cancel the booking in Citable |
| Google → Citable time edit | Update booking starts_at / ends_at |
| OAuth approach | Manual controller + `google-apis-calendar_v3` gem (Option B) |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Citable                              │
│                                                             │
│  Dashboard::GoogleOauthController                           │
│    GET /dashboard/google/connect   → redirect to Google     │
│    GET /dashboard/google/callback  → exchange code + store  │
│    DELETE /dashboard/google/disconnect → remove tokens      │
│                                                             │
│  GoogleCalendarService             (service object)         │
│    #ensure_calendar                → get/create "Citable"   │
│    #sync_booking(booking, action)  → create/update/cancel   │
│    #setup_watch(user)              → register push channel  │
│    #refresh_token!                 → renew access token     │
│    #with_token_refresh             → retry wrapper on 401   │
│                                                             │
│  GoogleCalendarSyncJob             (stub → full impl)       │
│    → calls GoogleCalendarService#sync_booking               │
│                                                             │
│  RenewGoogleWatchJob               (new, recurring daily)   │
│    → renews push channels before they expire (7-day max)    │
│                                                             │
│  Webhooks::GoogleCalendarController                         │
│    POST /webhooks/google_calendar  → receive Google push    │
│    → incremental sync → update/cancel bookings              │
└─────────────────────────────────────────────────────────────┘
         ↕ OAuth2            ↕ Calendar API      ↕ Push notifications
┌─────────────────────────────────────────────────────────────┐
│                     Google APIs                             │
│  accounts.google.com/oauth2  (consent + token exchange)     │
│  www.googleapis.com/calendar/v3  (Calendar API)             │
└─────────────────────────────────────────────────────────────┘
```

---

## Gems

Add to `Gemfile`:

```ruby
gem "google-apis-calendar_v3"   # Calendar API client + Signet OAuth (no extra OAuth gem needed)
```

---

## Credentials

Add to `rails credentials:edit`:

```yaml
google:
  client_id: YOUR_CLIENT_ID
  client_secret: YOUR_CLIENT_SECRET
  webhook_token: RANDOM_SHARED_SECRET   # used to validate push notification authenticity
```

---

## Data Model

### New Migration: `add_google_watch_fields_to_users`

```ruby
add_column :users, :google_token_expires_at,   :datetime
add_column :users, :google_channel_id,         :string
add_column :users, :google_channel_expires_at, :datetime
add_column :users, :google_sync_token,         :text
```

### Existing Columns (no schema change)

| Column | Type | Purpose |
|---|---|---|
| `google_oauth_token` | text | OAuth2 access token (encrypted) |
| `google_refresh_token` | text | OAuth2 refresh token (encrypted) |
| `google_calendar_id` | string | ID of the dedicated "Citable" calendar |

### Rails 8 Encryption (User model)

```ruby
encrypts :google_oauth_token
encrypts :google_refresh_token
encrypts :google_sync_token
```

Requires `config.active_record.encryption` to be initialized (automatic in Rails 8 when `primary_key`, `deterministic_key`, `key_derivation_salt` are in credentials).

### User Model Helper Methods

```ruby
def google_connected?
  google_oauth_token.present?
end

def google_token_expired?
  google_token_expires_at.present? && google_token_expires_at <= 5.minutes.from_now
end

def google_watch_expiring?
  google_channel_expires_at.present? && google_channel_expires_at <= 1.day.from_now
end
```

---

## OAuth2 Flow

### Scopes Requested

- `https://www.googleapis.com/auth/calendar`
- `https://www.googleapis.com/auth/calendar.events`

### Flow Steps

1. Staff (or owner acting on behalf of staff) clicks "Conectar Google Calendar"
2. `GET /dashboard/google/connect?user_id=X` (user_id optional; only honored by owners)
3. Controller builds Google consent URL, includes signed `state` param encoding `{ user_id:, return_to: }`
4. Redirect to Google OAuth consent screen
5. Google redirects to `GET /dashboard/google/callback?code=...&state=...`
6. Controller validates `state` signature (CSRF prevention)
7. Exchange `code` for `access_token`, `refresh_token`, `expires_at`
8. Store encrypted tokens on target user record
9. Call `GoogleCalendarService#ensure_calendar` → create "Citable" calendar, store `google_calendar_id`
10. Call `GoogleCalendarService#setup_watch` → register push notification channel, store `google_channel_id` + `google_channel_expires_at`
11. Redirect to staff profile page with success flash: "Google Calendar conectado correctamente."

### State Parameter

Encoded as: `Base64(JSON({ user_id:, return_to: }))` signed with HMAC-SHA256 using `Rails.application.secret_key_base`. Validated on callback before any token exchange occurs.

### Owner Managing Staff

- Connect URL: `GET /dashboard/google/connect?user_id=:staff_id`
- Controller guard: if `params[:user_id]` is present, verify `current_user.owner?` before loading target user; otherwise use `current_user`
- Owner-managed connect/disconnect buttons appear on `Dashboard::Staff#show`

### Disconnect

`DELETE /dashboard/google/disconnect` (with `user_id` param for owner-managed):
1. Load target user (same owner guard as connect)
2. Call Google to stop the push channel (`channel.stop`)
3. Clear all `google_*` columns on the user
4. Redirect back to profile with flash: "Google Calendar desconectado."
5. The "Citable" calendar in Google is left intact (not deleted)

---

## GoogleCalendarService

**Location:** `app/services/google_calendar_service.rb`

```
initialize(user)
  → builds Google::Apis::CalendarV3::CalendarService
  → sets Signet::OAuth2::Client from user's stored tokens
  → calls refresh_token! if google_token_expired?

ensure_calendar
  → if user.google_calendar_id present: verify it still exists
  → else: insert new Calendar(summary: "Citable"), save id on user
  → returns calendar_id

sync_booking(booking, action)
  action :create  → insert event, save google_event_id on booking
  action :update  → patch event (title, start, end, location, description)
  action :cancel  → patch event title to "❌ [Cancelada] {service} – {customer}"

setup_watch
  → channel = Channel.new(id: SecureRandom.uuid, type: "web_hook", address: webhook_url, token: google.webhook_token)
  → calendar_service.watch_event(calendar_id, channel)
  → save google_channel_id + google_channel_expires_at on @user

refresh_token!
  → use Signet to exchange refresh_token for new access_token
  → update google_oauth_token + google_token_expires_at on user

with_token_refresh(&block)
  → yield block
  → rescue Google::Apis::AuthorizationError → call refresh_token! → retry once
```

### Event Format

| Field | Value |
|---|---|
| Title (active) | `{Service name} – {Customer name}` |
| Title (cancelled) | `❌ [Cancelada] {Service name} – {Customer name}` |
| Start | `booking.starts_at` (account timezone) |
| End | `booking.ends_at` (account timezone) |
| Description | `"Cliente: {phone}\nNotas: {notes}\nCitable ID: {booking.id}"` |
| Location | `booking.address` (if present) |

---

## GoogleCalendarSyncJob

**Location:** `app/jobs/google_calendar_sync_job.rb` (replaces current stub)

Signature: `perform(booking_id, action)` where `action` is `:create`, `:update`, or `:cancel` (stored as string in Solid Queue).

```ruby
def perform(booking_id, action)
  booking = Booking.find_by(id: booking_id)
  return unless booking

  ActsAsTenant.with_tenant(booking.account) do
    staff = booking.user
    return unless staff.google_connected?

    GoogleCalendarService.new(staff).sync_booking(booking, action.to_sym)
  end
end
```

### Trigger Points

Called from `Booking` model callbacks and controller actions:

| Event | Action passed |
|---|---|
| `after_create_commit` | `:create` |
| `after_update_commit` (starts_at or ends_at changed, `skip_google_sync` is false) | `:update` |
| `Booking#cancel!` | `:cancel` |
| `Booking#confirm!` | `:update` (updates event to show confirmed) |

---

## Two-Way Sync — Webhooks::GoogleCalendarController

**Route:** `POST /webhooks/google_calendar` (no CSRF, no auth)

**Validation:**
1. Check `X-Goog-Channel-Token` header equals `Rails.application.credentials.google.webhook_token` — return 200 silently on mismatch (do not expose 401)
2. Find `User` by `X-Goog-Channel-ID` header matching `google_channel_id`
3. If no user found, return 200 (channel may be stale)

**Sync logic:**
1. If `X-Goog-Resource-State == "sync"` → this is the initial handshake. Do a full list to get initial `google_sync_token`, save it, return 200.
2. Otherwise → call `calendar_service.list_events` with `sync_token: user.google_sync_token` to get only changed events
3. For each changed event:
   - `status == "cancelled"` → find booking by `google_event_id` → `booking.cancel!` (if not already cancelled)
   - Start/end time changed → find booking → set `booking.skip_google_sync = true` → update `starts_at` / `ends_at`, save
4. Save new `google_sync_token` from the response

**Infinite loop prevention:** `Booking` adds `attr_accessor :skip_google_sync`. The `after_update_commit` callback checks this flag before enqueuing `GoogleCalendarSyncJob`. The webhook controller sets this to `true` before saving any time change, so the update does not echo back to Google.

**Error handling:** If `Google::Apis::GoneError` (410 — sync token expired) → fall back to full re-sync, get new token.

---

## RenewGoogleWatchJob

**Location:** `app/jobs/renew_google_watch_job.rb`

**Schedule:** Daily via `config/recurring.yml`

```ruby
def perform
  User.where.not(google_channel_id: nil)
      .where("google_channel_expires_at <= ?", 1.day.from_now)
      .find_each do |user|
        ActsAsTenant.with_tenant(user.account) do
          GoogleCalendarService.new(user).setup_watch
        end
      end
end
```

Calls `setup_watch` which registers a new channel and overwrites the stored `google_channel_id` + `google_channel_expires_at`.

---

## Routes

```ruby
# OAuth2 connect/disconnect (inside dashboard, requires login)
namespace :dashboard do
  resource :google_oauth, only: [] do
    get  :connect
    get  :callback
    delete :disconnect
  end
end

# Google Calendar push notifications
namespace :webhooks do
  post :google_calendar
end
```

---

## UI

### Staff Profile (`/dashboard/staff/:id`)

Add a "Google Calendar" card below the availability section:

**Not connected:**
```
┌─────────────────────────────────┐
│ Google Calendar                 │
│ Sin conectar                    │
│ [Conectar Google Calendar]      │  ← links to /dashboard/google_oauth/connect(?user_id=X)
└─────────────────────────────────┘
```

**Connected:**
```
┌─────────────────────────────────┐
│ Google Calendar           ✓     │
│ Calendario: Citable             │
│ [Desconectar]                   │  ← delete form to /dashboard/google_oauth/disconnect
└─────────────────────────────────┘
```

The owner sees these buttons for any staff member on their show page. Staff see it on their own profile only.

### No changes to Settings page

Calendar connection is per-staff, not per-account.

---

## Error Handling

| Scenario | Behavior |
|---|---|
| Access token expired | `with_token_refresh` retries once after refreshing |
| Refresh token revoked (user disconnected from Google) | Clear all `google_*` columns, log warning; no crash |
| Google API rate limit (429) | Job raises, Solid Queue retries with backoff |
| Push channel expired | `RenewGoogleWatchJob` renews daily before expiry |
| Sync token expired (410) | Full re-sync in webhook handler |
| Booking not found on webhook | 200 returned silently |
| Invalid webhook token | 200 returned silently (no info leak) |

---

## Google Cloud Project Setup (Pre-requisites)

Before this feature can work in any environment:

1. Create a project at [console.cloud.google.com](https://console.cloud.google.com)
2. Enable **Google Calendar API**
3. Create **OAuth 2.0 Client ID** (type: Web Application)
4. Add authorized redirect URIs:
   - `http://localhost:3000/dashboard/google_oauth/callback` (development)
   - `https://app.citable.mx/dashboard/google_oauth/callback` (production)
5. Add `client_id` + `client_secret` to Rails credentials
6. Generate a random `webhook_token` (`SecureRandom.hex(32)`) and add to credentials

**Note on production redirect URIs:** Keep the OAuth callback on the canonical app host, for example `https://app.citable.mx/dashboard/google_oauth/callback`.

---

## Out of Scope (v1)

- Importing existing Google Calendar events into Citable
- Syncing recurring bookings as Google recurring events (synced as individual events)
- Customer receiving a Google Calendar invite
- Conflict detection against non-Citable events on the Google Calendar
