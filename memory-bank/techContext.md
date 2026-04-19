# Tech Context

## Stack
- **Framework**: Ruby on Rails 8.1.3 + Hotwire (Turbo + Stimulus)
- **Ruby**: 3.3.6 (managed via rbenv)
- **Database**: PostgreSQL (development + production)
- **Background jobs**: Solid Queue (Rails 8 default, no Redis required)
- **Cache**: Solid Cache (Rails 8 default)
- **Styling**: TailwindCSS via tailwindcss-rails gem
- **Auth**: Devise 5.x
- **Multi-tenancy**: acts_as_tenant 1.x (row-level, scoped on account_id)
- **WhatsApp**: twilio-ruby (Twilio WhatsApp Business API)
- **Payments**: stripe gem (Stripe Mexico - Payment Intents + Billing)
- **Email**: resend gem (transactional fallback)
- **Money**: money-rails (integer cents, MXN default)
- **Hosting**: Kamal with Docker (production); multi-database Solid stack (cache/queue/cable)

## Key Gems Added
```
gem "devise"
gem "acts_as_tenant"
gem "stripe"
gem "twilio-ruby"
gem "resend"
gem "money-rails"
gem "google-apis-calendar_v3"   # Calendar API client + Signet OAuth2
```

## Database Name Convention
- Development: `citable_development`
- Test: `citable_test`
- Production: `citable_production` (+ separate cache/queue/cable DBs via Solid)

## Local Development Setup
```bash
# Prerequisites: Ruby 3.2.2, PostgreSQL running
cd /path/to/citable
bundle install
rails db:create db:migrate db:seed
bin/dev   # starts Rails + TailwindCSS watcher
```

For subdomain testing locally, add entries to `/etc/hosts`:
```
127.0.0.1 ana.localhost
```
Then access `http://ana.localhost:3000`

## Environment / Credentials
Secrets are stored in Rails encrypted credentials. Keys needed:
- `stripe.secret_key`
- `stripe.webhook_secret`
- `twilio.account_sid`
- `twilio.auth_token`
- `twilio.whatsapp_number` (e.g. `+14155238886`)
- `resend.api_key`
- `google.client_id`
- `google.client_secret`
- `google.webhook_token` (random hex, used to verify push notifications)

Edit with: `rails credentials:edit`

## CI
`bin/ci` runs: Brakeman → bundler-audit → importmap audit → Rubocop → RSpec (`bin/rails db:test:prepare` first).
GitHub Actions mirrors this sequence.

## Queue Architecture
Three named Solid Queue queues:
- `reminders` — 24h/2h booking reminders (ReminderJob)
- `notifications` — WhatsApp sends (WhatsappSendJob)
- `default` — Google Calendar sync + everything else
