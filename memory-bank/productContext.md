# Product Context

## Why This Exists

Mexican local-service solo operators lose ~15% of revenue to no-shows. They manage everything through WhatsApp DMs, paper notebooks, and Google Calendar — none of which talk to each other. Sending a reminder means manually opening WhatsApp, finding the client, typing a message. Tracking who confirmed takes more manual work.

Calendly/Acuity don't integrate with WhatsApp and are English-first. Jobber is USD $50+/mo. AgendaPro is beauty-focused with no free tier. The real competitor is the current manual workflow, not another SaaS.

## How It Should Work

### For the Business Owner (Ana)
1. Signs up in < 5 minutes → gets `ana.citable.mx` immediately
2. Adds her services (Corte $250, Tinte $850 con depósito $200)
3. Sets her availability (Lun-Sáb 9am-6pm)
4. Shares her booking link on Instagram Stories / WhatsApp
5. Clients book → Ana gets a WhatsApp notification
6. 24h before the appointment: client gets "Tu cita es mañana. Responde 1 para confirmar o 2 para cancelar."
7. No-shows drop; Ana sees her confirmed vs. pending bookings in the dashboard

### For the Client (Rosa)
1. Clicks link from Instagram or WhatsApp
2. Picks a service → picks a slot → enters name + phone
3. Pays deposit if required (optional Stripe checkout)
4. Gets WhatsApp confirmation immediately
5. Gets WhatsApp reminder 24h and 2h before

### Differentiators (in order of importance)
1. WhatsApp-first — no other tool in this price band does this natively
2. Spanish-native UX — Mexican idioms, not translated English
3. Cash-first — "pagar en el lugar" is the default, deposit is optional
4. Genuinely usable free tier — not crippled; users can run their business on free
5. Service-business-native — addresses, recurring bookings, multi-staff from v1

## UX Principles
- Mobile-first: the public booking page must work perfectly on mid-range Android
- Spanish always: no English in any user-visible string
- Fast: booking flow should take < 2 minutes from link click to confirmation
- Obvious: zero documentation required to use the dashboard
- Trust: explicit privacy notice (aviso de privacidad per LFPDPPP) on booking page

## Pricing
- **Libre (gratis)**: 3 servicios, 2 colaboradores, ilimitadas citas, 100 mensajes WhatsApp/mes
- **Pro (MXN $299/mes)**: ilimitados servicios y colaboradores, 1,000 mensajes, dominio propio

## Tone / Copy
- Warm, direct, colloquial Mexican Spanish
- "Cita" not "appointment", "colaborador" not "employee", "mensajes" not "conversations"
- No corporate language
