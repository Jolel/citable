# Competitor Matrix - Mexico-Focused Appointment Booking + Light CRM

Last updated: 2026-04-17
Market: Mexico (launch); target segment: solo and 2-3 person local-service businesses.

## At a glance


| Product                                | Pricing (entry)          | Free tier              | Language       | WhatsApp             | Multi-staff    | CRM depth                              | Recurring appts | Mexico presence               | Key weakness                                                                                                                                                             |
| -------------------------------------- | ------------------------ | ---------------------- | -------------- | -------------------- | -------------- | -------------------------------------- | --------------- | ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **AgendaPro**                          | ~USD $25-60/mo           | No                     | ES / EN        | Via add-on / partial | Yes            | Medium (client file)                   | Yes             | Strong (LATAM-wide, HQ Chile) | No free tier; beauty-vertical lean; priced above solo operators                                                                                                          |
| **Fluix / Agendalo**                   | ~USD $15-30/mo           | Limited trial          | ES             | Limited              | Yes            | Light                                  | Partial         | Medium                        | Dated UX; thin integrations                                                                                                                                              |
| **Bookeo**                             | USD $14.95/mo            | 30-day trial           | ES + 34 others | No                   | Yes            | Medium                                 | Yes             | Low (no MX marketing)         | Dated UI; no WhatsApp; generic (not MX-native)                                                                                                                           |
| **Calendly**                           | USD $12-20/user/mo       | Yes, 1 event type only | EN-first       | No                   | Team tier only | Very light (contacts only, no history) | Limited         | Low in MX SMB                 | English-first; no WhatsApp; free tier too restrictive; built for B2B sales not local services                                                                            |
| **Acuity Scheduling**                  | USD $16-61/mo            | No                     | EN-first       | No                   | Yes            | Medium (client notes, forms)           | Yes             | Low in MX SMB                 | English-first; no free tier; no WhatsApp; setup takes 30+ min                                                                                                            |
| **Square Appointments**                | USD $0 solo / $29+ teams | Yes (solo)             | EN-first       | No                   | Yes            | Medium                                 | Yes             | Very low in MX                | Limited MX payment/POS support; English-first; no WhatsApp                                                                                                               |
| **Setmore**                            | USD $5-9/user/mo         | Yes                    | ES available   | Via Zapier only      | Yes            | Light                                  | Yes             | Low                           | Weak automation; no native WhatsApp; not MX-native                                                                                                                       |
| **SimplyBook.me**                      | USD $0-70/mo modular     | Yes (limited)          | ES + many      | Via add-on           | Yes            | Medium                                 | Yes             | Low                           | Cluttered UX; add-on pricing confusing                                                                                                                                   |
| **HoneyBook**                          | USD $19-79/mo            | No                     | EN only        | No                   | Yes            | Heavy (client + projects + contracts)  | Limited         | None in MX                    | English-only; scoped to creative freelancers; heavier than MX SMBs need                                                                                                  |
| **Jobber**                             | USD $39-249/mo           | No                     | EN only        | No                   | Yes            | Heavy (full FSM)                       | Yes             | None in MX                    | English-only; way too expensive; overbuilt for solo/duo operators                                                                                                        |
| **Housecall Pro**                      | USD $65+/mo              | No                     | EN only        | No                   | Yes            | Heavy (full FSM)                       | Yes             | None in MX                    | English-only; expensive; overbuilt                                                                                                                                       |
| **WhatsApp + Google Sheets + libreta** | Free                     | n/a                    | ES native      | Yes (native)         | Manual         | None (memory + notes)                  | Manual          | Universal                     | Zero automation, no reminders, no booking page, no history, no payments, error-prone. **This is what 80%+ of our target users do today - and it's our real competitor.** |


## What we must match (table stakes)

- Public booking page per business, mobile-first
- Two-way Google Calendar sync
- Automated reminders (we use WhatsApp; they use email/SMS)
- Availability rules (hours, buffers, min-notice, max-advance)
- Multiple service types with duration and price
- Customer record with contact, history, notes
- Payment collection (we start with optional Stripe MX deposit)
- Timezone handling (single-tz Mexico is simpler than global competitors)
- Self-service cancel / reschedule

## Where we win

1. **WhatsApp-native communication** - literally no competitor in the price band does this natively. Acuity, Calendly, Setmore require Zapier hacks. AgendaPro has partial WhatsApp via add-ons but doesn't center on it.
2. **Spanish-first UX for Mexico specifically** - Bookeo and Setmore have Spanish but as a translation layer, not a market-native product. AgendaPro is closest but leans beauty-vertical and is priced above our beachhead.
3. **Genuinely usable free tier** - every competitor's free tier either doesn't exist (AgendaPro, Jobber, Acuity) or is severely capped (Calendly = 1 event type). We keep the free tier usable for true solo operators indefinitely.
4. **Cash-first booking flow** - all major competitors assume online prepayment is default. In Mexico, cash-on-arrival is the norm. We flip the default.
5. **Service-business-native from v1** - recurring appointments, service addresses, multi-staff calendars on the free tier. Calendly and Square treat these as upsells or afterthoughts.

## Where we lose (acknowledged gaps for v1)

- No invoicing or facturación CFDI (AgendaPro has partial; Jobber is full)
- No dispatching / routing (Jobber, Housecall Pro are full-featured here)
- No native iOS/Android app at launch (mobile web only)
- Fewer integrations than Calendly's 700+
- No English UI (deliberate; we ship MX-first)

## Pricing positioning

- **Free**: up to 3 services, 2 staff, unlimited bookings, 100 WhatsApp messages/mo included
- **Pro** (target ~MXN $299/mo, roughly USD $17): unlimited services, unlimited staff, higher WhatsApp quota, custom branding, custom domain

Entry price is ~60% of AgendaPro and half of Jobber, while being Spanish-first and WhatsApp-native. The real anchor is not "cheaper than Calendly"; it's "free replaces your WhatsApp + Sheets + libreta stack, paid adds scale."