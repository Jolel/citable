# PRD: Citable - WhatsApp-Native Booking + Light CRM for Mexican Local Services

Date: 2026-04-17
Author: jolell
Status: Draft v1, pending user review
Related: [design spec](2026-04-17-whatsapp-booking-mx-design.md), [competitor matrix](../../competitor-matrix.md)

---

## 1. Executive Summary

### Problem Statement

Mexican local-service businesses (cleaners, tutors, groomers, stylists, A/C technicians, trainers) run their entire customer workflow on WhatsApp + Google Sheets + a paper notebook. They lose 10-20% of revenue to no-shows, forget appointments, double-book, and have no customer history beyond their memory. Every existing booking SaaS is either English-first (Calendly, Acuity, Jobber), too expensive (AgendaPro, Jobber at USD $25-250/mo), or missing WhatsApp - the communication channel their customers actually use.

### Proposed Solution

Citable is a Spanish-first, WhatsApp-native appointment booking and light CRM for Mexican local-service businesses. It replaces their WhatsApp + Sheets + libreta stack with a booking page, customer records, automated WhatsApp reminders, and multi-staff calendars. Cash-first flow matches Mexican reality; optional Stripe MX deposits are available. The free tier stays usable for true solo operators indefinitely; paid tier (MXN $299/mo) unlocks scale.

### Success Criteria

1. **Onboarded accounts**: 20 paying or free-tier-active accounts within 30 days of launch; 100 within 90 days.
2. **Activation**: 70% of sign-ups create their first service and take their first booking within 7 days.
3. **No-show reduction**: median account reports >= 25% reduction in no-show rate within 60 days vs. their self-reported baseline.
4. **Free → Pro conversion**: >= 8% within 60 days of signup.
5. **Reliability**: P95 booking page load < 2s on 4G in Mexico; 99.5% uptime SLO.

---

## 2. User Experience & Functionality

### User Personas

**Ana, la estilista de la colonia**

- Solo operator, 1-chair salon from home or a small shop
- 30-80 active clients, mostly repeat
- All booking happens via WhatsApp today
- Tracks appointments in a paper notebook and/or Google Calendar
- 10-15% no-show rate
- Monthly revenue MXN $15,000-40,000
- iPhone or mid-range Android; marketing via Instagram
- Spanish-only

**Luis, el dueño de un equipo de 3 técnicos**

- Owner of a 3-person A/C repair / plumbing / electrical business
- Needs to see all techs' calendars in one place
- Customer history matters (past jobs, service addresses, preferred tech)
- Collects deposits sometimes; mostly paid on arrival

**Sofía, la clienta**

- Tertiary but critical. Books with Ana or Luis from her phone.
- Doesn't want to install anything or create an account.
- Communicates with businesses exclusively through WhatsApp.

### User Stories and Acceptance Criteria

#### Story 1: As Ana, I want to sign up and publish a working booking page in under 5 minutes, so I can start taking online bookings today.

Acceptance criteria:

- Sign-up requires only: email, business name, WhatsApp phone, password. No credit card.
- Onboarding wizard in Spanish walks through: add first service (name, duration, price), set weekly availability, preview booking page.
- Booking page is live at `[subdomain].citable.mx` immediately after wizard completion.
- Median time from sign-up start to live booking page <= 5 minutes in usability testing with 5 Spanish-speaking non-technical users.
- User sees a "Copia el link de tu página" button at the end of onboarding.

#### Story 2: As Ana, I want customers to book me without creating an account, so they don't drop off.

Acceptance criteria:

- Public booking page requires only: service selection, slot selection, customer name, customer WhatsApp phone. Email is optional.
- No sign-up, no password, no captcha (honeypot + rate-limiting is sufficient).
- Booking completes in <= 4 taps on mobile from landing to confirmation.
- P95 time-to-interactive on the booking page < 2.5s on a Telcel 4G connection.

#### Story 3: As Ana, I want confirmations and reminders to go out over WhatsApp automatically, so I stop chasing clients manually.

Acceptance criteria:

- On booking confirmation, a WhatsApp message is sent to the customer within 10 seconds using an approved Meta template.
- A reminder is sent 24 hours before the booking; another 2 hours before.
- If a customer replies `1`, the booking is marked `confirmed`. If they reply `2`, it's `cancelled` and the slot is freed.
- If WhatsApp delivery fails (no WA on number, opt-out, quota exhausted), an email fallback is sent; delivery state is logged.
- All outgoing and inbound messages are logged in `MessageLog` and visible on the booking detail view.

#### Story 4: As Ana, I want to see every customer's history at a glance, so I remember who they are and what they booked before.

Acceptance criteria:

- Customer list shows: name, phone, last booking date, total bookings, tags.
- Customer detail view shows chronological timeline of bookings with status, notes, and messages exchanged.
- Ana can add free-form notes and custom fields on a customer (e.g., "tinte rubio cenizo, alergica a X").
- Search by name or phone returns matching customers in < 300ms for up to 10,000 customers.

#### Story 5: As Ana, I want to take deposits online for high-value services, so no-shows cost them something.

Acceptance criteria:

- Per service, Ana can toggle "requires deposit" and set a fixed MXN amount.
- On the booking page, deposit services show the deposit amount and a "Pagar depósito" step.
- Booking is created as `pending_payment`; it converts to `confirmed` only after Stripe webhook confirms payment.
- If payment is not completed within 30 minutes, the slot is released and the pending booking is cancelled.
- Deposits are visible on the booking detail; refunds are a one-click action for the owner.

#### Story 6: As Luis, I want each of my techs to have their own calendar and bookings, so my team can be scheduled properly.

Acceptance criteria:

- Luis can invite up to 2 staff on free tier, unlimited on Pro.
- Each staff user has their own weekly availability and Google Calendar connection.
- Public booking page lets the customer pick a preferred tech OR auto-assigns to the first available.
- Dashboard calendar view can filter by staff or show all in a single overlay.
- Staff users can see and edit only their own bookings; owner sees everything.

#### Story 7: As Ana, I want recurring clients (e.g., weekly haircut) to rebook automatically.

Acceptance criteria:

- When creating or editing a booking, Ana can set it to repeat weekly, biweekly, or monthly, with an optional end date.
- Recurring bookings respect Ana's availability and skip days she has blocked off.
- Customer receives one confirmation and then reminder messages for each instance.
- Cancelling an instance does not cancel the series unless Ana explicitly chooses "cancelar toda la serie".

#### Story 8: As Ana, I want the product to work in Spanish, tuned for Mexico.

Acceptance criteria:

- 100% of user-facing copy is in es-MX Spanish on launch.
- Date/time formats follow Mexican conventions (24-hour or 12-hour AM/PM configurable; `d/m/Y`).
- Currency is MXN with `$1,299.00` formatting.
- No English strings are visible in the product or emails, including error messages, Stripe pages (use Stripe locale=es), and WhatsApp templates.

#### Story 9: As a free-tier user, I want to know clearly when I'm approaching limits so I can upgrade before I'm blocked.

Acceptance criteria:

- Dashboard shows a WhatsApp quota meter (e.g., "72 de 100 mensajes este mes"). The UI label is "mensajes" for simplicity, but internally we count Meta-billed business-initiated conversations (24h windows) - one conversation per customer per day regardless of how many messages are exchanged.
- At 80% of monthly quota, show a soft notice and email the owner.
- At 100%, new outbound WhatsApp sends are auto-replaced with email fallback; no bookings are blocked. There is no overage billing in v1.
- One-click upgrade flow to Pro, handled entirely in Stripe Checkout (Spanish locale).

#### Story 10: As Ana, I want my Google Calendar to stay in sync so my bookings don't conflict with personal events.

Acceptance criteria:

- Ana can connect her Google Calendar via OAuth during onboarding or later from settings.
- Events created in Google Calendar block her availability in Citable within 60 seconds.
- Bookings taken in Citable appear in Google Calendar within 60 seconds.
- If Google OAuth expires, Ana is notified via in-app banner and email; sync pauses until reconnected.

### Non-Goals for v1

- Facturación / CFDI / SAT integration
- Quotes, estimates, or invoicing beyond deposits
- Dispatching, routing, or map views
- Full CRM pipelines (deals, stages, sales forecasts)
- Native iOS / Android applications
- English or any non-Spanish UI
- Multi-currency (MXN only)
- iCloud / Outlook / Office 365 calendar sync
- MercadoPago payment rail (deferred to v1.1)
- SMS fallback (deferred to v1.1; email is fallback in v1)
- Bulk WhatsApp broadcasts (deferred to v1.2)

---

## 3. Integration Requirements

### Third-party services and APIs

- **Twilio WhatsApp Business API**: send templated messages (confirmation, 24h reminder, 2h reminder, cancellation, reschedule link); receive inbound replies via webhook; handle opt-outs per Meta policy.
- **Stripe Mexico**: Payment Intents for deposits; Billing for Pro subscriptions; webhook signature verification; Mexican OXXO support via Payment Methods.
- **Google Calendar API**: OAuth 2.0; `calendar.events` scope; two-way sync per user; push notifications via Watch API (fall back to polling every 5 min if Watch unavailable).
- **Resend**: transactional email for fallback notifications and owner-facing alerts.
- **Sentry**: error reporting from Rails app and background jobs.

### WhatsApp template inventory (Meta approval required)

All templates in Spanish (es-MX). Submit for approval in week 1 of development.

1. `confirmacion_cita` - booking confirmation (variables: cliente, servicio, fecha, hora, negocio)
2. `recordatorio_24h` - 24-hour reminder with confirm/cancel buttons
3. `recordatorio_2h` - 2-hour reminder
4. `cancelacion_cita` - cancellation confirmation
5. `link_reagendar` - reschedule link with booking-specific short URL

### No AI/LLM dependencies in v1

No LLM features in MVP. WhatsApp reply parsing uses simple keyword matching (`1`, `2`, `confirmar`, `cancelar`, numeric inputs). If and when we add AI features (smart reminders, chatbot booking, no-show prediction), they will be a separate scoped addition in v1.2+ with their own evaluation plan.

### Evaluation strategy (for non-AI quality)

- **WhatsApp delivery reliability**: automated end-to-end test in staging sending real templates to a test phone number daily; alert if success rate < 99%.
- **Booking flow reliability**: Playwright smoke tests run on CI for the public booking path and owner dashboard in Spanish locale.
- **Tenant isolation**: RSpec integration tests that attempt cross-tenant reads in every controller; all must return 404 or equivalent.
- **Availability correctness**: property-based tests (using `rantly` or manual fixtures) to verify the availability calculator produces no double-bookings under concurrent requests.

---

## 4. Technical Specifications

### Architecture Overview

Rails 8.1+ monolithic application with Hotwire for reactive UI. Postgres 15+ for primary data. Solid Queue for background jobs (reminders, calendar sync, webhook retries). No separate frontend; Hotwire (Turbo Frames + Turbo Streams + Stimulus) handles interactivity.

Multi-tenant via row-level scoping with `acts_as_tenant` on `account_id`. Subdomain routing resolves tenant middleware before any controller action. Public booking pages resolve tenancy via subdomain and are NOT behind auth - customers book without signing in. The `require_tenant!` global setting applies only to authenticated dashboard routes; public routes explicitly set the current tenant via subdomain lookup and skip the auth filter.

Background jobs are the critical path for reliability:

- Reminder jobs enqueued at booking creation with `run_at` timestamps.
- Google Calendar sync runs on booking create/update/destroy and via a poller for inbound changes.
- WhatsApp webhook delivery uses Twilio's built-in retry; our own webhook handlers are idempotent via message SID.

See architecture and sequence diagrams in the [design spec §4](2026-04-17-whatsapp-booking-mx-design.md#4-system-architecture).

### Integration Points

- **Auth**: Devise with email/password. Google OAuth for staff-level calendar sync (separate from login).
- **DB**: Postgres. Daily automated backups via hosting provider. One logical database per environment.
- **Webhooks inbound**: Twilio (WhatsApp messages + status), Stripe (payment intents + subscriptions). All verified via signatures.
- **Webhooks outbound**: none in v1.
- **Public API**: none in v1. Build internal-only JSON endpoints for the dashboard's Hotwire use only.

### Data Model Summary

See [design spec §4](2026-04-17-whatsapp-booking-mx-design.md#core-data-model-sketch). Full ERD and migrations will be produced in the implementation plan.

### Performance Targets

- P95 booking page time-to-interactive < 2.5s on a simulated Telcel 4G connection.
- P95 availability calculation < 200ms for a 2-week lookahead with 100 bookings.
- P95 dashboard calendar render < 500ms for a week view with 50 bookings.
- WhatsApp outbound send < 10s from trigger to Twilio-accepted status, P95.
- Background job queue latency: reminders fire within ±60 seconds of their scheduled time.

### Security & Privacy

- Jurisdiction: Mexico. Compliance: LFPDPPP (Mexican privacy law). Publish aviso de privacidad at `/privacidad`.
- No card data stored; Stripe handles all PCI scope.
- Passwords hashed with bcrypt via Devise.
- All secrets via Rails encrypted credentials; no secrets in repo.
- HTTPS enforced site-wide via hosting provider + HSTS header.
- `MessageLog` is append-only; provides audit trail for customer communications.
- Daily Postgres backups retained 30 days.
- Soft-delete for customers and bookings (retain for audit); hard-delete available on customer request per LFPDPPP.
- Multi-tenant isolation verified by automated tests in CI.

---

## 5. Risks & Roadmap

### Phased Rollout

**MVP (weeks 1-10, solo founder, ~20-30 hrs/wk)**

- Accounts, users, services, staff availability, customers
- Public booking page with slot picker
- WhatsApp confirmation + 24h and 2h reminders with templated messages
- Inbound WhatsApp reply handling (confirm / cancel)
- Google Calendar two-way sync
- Optional Stripe MX deposits
- Free tier enforcement (services, staff, WhatsApp quota)
- Pro subscription billing via Stripe
- Spanish-only UI, es-MX locale
- Landing page + marketing site copy in Spanish

**v1.1 (+4 weeks)**

- MercadoPago integration as alternate payment method
- SMS fallback via Twilio (for numbers without WhatsApp)
- Recurring appointments UX polish (edit single vs. all)
- CSV customer import
- Better onboarding flows based on pilot feedback

**v1.2**

- Customer tags and segments
- Bulk WhatsApp broadcasts (templated; respects opt-out)
- Basic analytics dashboard (bookings, revenue, no-show rate)
- Owner mobile web optimizations (add-to-home-screen PWA)

**v2**

- WhatsApp-native booking chatbot (customer books from inside WA)
- Team routing rules (round-robin, load-balanced, preferred tech)
- LATAM expansion (Colombia, Argentina, Chile): locale, local payment rails, region-appropriate pricing
- CFDI / facturación integration
- Native iOS/Android apps (evaluate based on PWA performance)

### Technical Risks

1. **WhatsApp template approval delays** - Meta approval can take days to weeks. Mitigation: submit templates week 1; ship email-only fallback behind feature flag so we can demo before templates approve.
2. **Twilio Mexico WhatsApp pricing** - per-message cost determines free-tier math. Mitigation: validate pricing in week 1; if it breaks economics, migrate to 360dialog or direct Meta BSP.
3. **Stripe Mexico onboarding latency** - KYB can take days. Mitigation: start onboarding week 1.
4. **Tenant data leakage** - the single most dangerous bug class in multi-tenant SaaS. Mitigation: `acts_as_tenant` with `require_tenant!` enabled globally; cross-tenant RSpec tests for every controller; add `bullet` gem and `brakeman` to CI.
5. **Solo founder velocity risk** - 8-10 week MVP assumes 20-30 hrs/wk. Mitigation: enforce strict v1 scope; every "nice to have" goes to v1.1.
6. **Reminder unit economics** - if WhatsApp messages cost more than the value of a prevented no-show, the model breaks. Mitigation: only send WA reminders for bookings worth > message cost; measure no-show rate reduction; fall back to email for low-value bookings if needed.
7. **Availability calculation concurrency** - two customers clicking the same slot simultaneously. Mitigation: `SELECT ... FOR UPDATE` around slot reservation; unique constraint on `(staff_id, starts_at)` for active bookings; integration test simulating concurrent bookings.
8. **Google Calendar two-way sync edge cases** - recurring events, all-day events, timezone mismatches. Mitigation: scope v1 to non-recurring Google events only for blocking; document known limitations.

### Business Risks

1. **Distribution** - a better product without distribution dies. Founder must spend at least 50% of early weeks on content + community, not code.
2. **Pricing sensitivity** - MXN $299/mo is an assumption; willingness-to-pay needs validation in the first 10 customer interviews.
3. **Incumbent (WhatsApp + Sheets) is free and "good enough"** - onboarding friction must be dramatically lower than the perceived cost of switching. The 5-minute onboarding target is a business requirement, not just UX.

---

## 6. Definition of Done for MVP Launch

- All 10 user stories above have passing acceptance criteria verified by automated tests + manual QA with a Spanish-speaking tester.
- 5 pilot accounts (real Mexican SMBs) onboarded and taking real bookings for 14+ days.
- No P0 or P1 bugs open.
- Privacy policy and terms of service published in Spanish.
- Public marketing page live with clear pricing, sign-up CTA, and 2-3 customer testimonials from pilots.
- Sentry, backups, and uptime monitoring live.
- Runbook for: restoring from backup, rotating Twilio/Stripe keys, responding to a tenant-isolation incident.