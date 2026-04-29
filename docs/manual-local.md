# Local Developer Manual — Citable

This manual helps a developer run Citable locally, configure Google Calendar sync, and test WhatsApp messaging through Twilio.

- **Audience:** developers setting up the app on macOS
- **Expected time:** 30-45 minutes for app + Google Calendar, 10-20 more minutes for Twilio
- **Primary local host:** `http://localhost:3000`

---

## What You Will Verify

By the end, you should be able to:

1. Run the Rails app locally.
2. Sign in with the seeded demo owner account.
3. Connect Google Calendar through OAuth.
4. Create a booking from the public booking page.
5. Confirm that the booking appears in Google Calendar.
6. Send a WhatsApp confirmation through Twilio.
7. Receive a WhatsApp reply through the Twilio webhook.
8. Send a free-text date such as "el viernes a las 3" and have the AI NLU parser resolve it to a real datetime.
9. Receive a personalized AI-generated greeting when a conversation starts, and confirm "dale" or "sí" are accepted at the confirmation step.

Twilio is required only for WhatsApp testing. A Gemini API key is required only for AI NLU testing. You can run the app and test Google Calendar without either.

---

## Prerequisites

| Tool | Required for | Check command |
|---|---|---|
| Homebrew | macOS package installation | `brew --version` |
| Git | Cloning the repo | `git --version` |
| Ruby 3.3.6 | Rails app runtime | `ruby --version` |
| PostgreSQL 16 | Local database | `brew services list` |
| A Google account | Google Calendar OAuth | n/a |
| A Twilio account | WhatsApp send/reply testing | n/a |
| A WhatsApp-capable phone | Joining the Twilio WhatsApp Sandbox | n/a |
| ngrok or another HTTPS tunnel | Receiving Twilio webhooks locally | `ngrok version` |
| A Google AI Studio / Gemini API key | AI NLU free-text parsing | n/a |

The app stores Google and Twilio secrets in Rails encrypted credentials. You need `config/master.key` from the project owner before you can edit or read those credentials.

---

## 1. Install Local Tools

Skip any tool you already have installed.

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install rbenv ruby-build
rbenv install 3.3.6
rbenv global 3.3.6
echo 'eval "$(rbenv init - zsh)"' >> ~/.zshrc
source ~/.zshrc
brew install postgresql@16
brew services start postgresql@16
brew install git
brew install ngrok/ngrok/ngrok
```

Verify the core tools:

```sh
ruby --version
brew services list | grep postgresql
git --version
ngrok version
```

---

## 2. Set Up the App

Clone the repo and move into the project directory:

```sh
cd ~
git clone https://github.com/jolel/citable.git
cd citable
```

All later commands assume you are in the repo root. If you open a new terminal, run:

```sh
cd ~/citable
```

Install dependencies, prepare the database, and load seed data:

```sh
bin/setup --skip-server
```

The seeded demo account includes:

| Field | Value |
|---|---|
| Business | `Estudio de Ana` |
| Owner email | `ana@example.com` |
| Owner password | `password123` |
| Staff email | `maria@example.com` |
| Staff password | `password123` |
| Services | `Corte de cabello`, `Tinte y highlights`, `Peinado especial` |
| Sample customers | `Rosa Martínez`, `Carlos Hernández` |

---

## 3. Configure Rails Credentials

Open credentials:

```sh
EDITOR=nano bin/rails credentials:edit
```

Add the Google, Twilio, and Gemini sections shown below. Replace every placeholder with the real value.

```yaml
google:
  client_id: "PASTE_GOOGLE_CLIENT_ID_HERE"
  client_secret: "PASTE_GOOGLE_CLIENT_SECRET_HERE"

twilio:
  account_sid: "PASTE_TWILIO_ACCOUNT_SID_HERE"
  auth_token: "PASTE_TWILIO_AUTH_TOKEN_HERE"
  whatsapp_number: "+14155238886"

gemini:
  api_key: "PASTE_GEMINI_API_KEY_HERE"
```

For nano, save and exit with **Ctrl + X**, then **Y**, then **Enter**.

Credential notes:

- `google.client_id` and `google.client_secret` come from the Google Cloud OAuth client.
- `twilio.account_sid` and `twilio.auth_token` come from the Twilio Console.
- `twilio.whatsapp_number` must be the WhatsApp sender number without the `whatsapp:` prefix.
- For the Twilio WhatsApp Sandbox, the sender is usually `+14155238886`.
- `gemini.api_key` is used only when `Account#ai_nlu_enabled` is true. Without it the app falls back to the strict date/service parser. Get a key at [aistudio.google.com/app/apikey](https://aistudio.google.com/app/apikey).
- `gemini.model` is optional. When omitted, the app uses `gemini-2.0-flash`. Override to switch to a newer model (e.g. `gemini-3.1-flash`) without a code deploy. Verify current model IDs at [ai.google.dev/gemini-api/docs/models](https://ai.google.dev/gemini-api/docs/models).

**Gemini free-tier limits (as of April 2026):**

| Model | Requests / min | Requests / day | Shared token limit |
|---|---|---|---|
| Flash-Lite | 15 | 1,000 | 250,000 / min |
| Flash | 10 | 250 | 250,000 / min |
| Pro | 5 | 100 | 250,000 / min |

For local development the free tier is sufficient. The seeded "Estudio de Ana" account averages one NLU call per booking step, well within the 250 requests/day Flash limit for testing.

> ⚠️ **LFPDPPP / data-privacy notice — read before using in production:** On the Gemini free tier, Google may use inputs and outputs to improve its models. Customer names, phone fragments, and appointment details sent to the NLU parser could be included. **For production, switch to a paid Gemini plan** (billing enabled in Google Cloud) which opts you out of data training, and update the business's *aviso de privacidad* to disclose the AI processor. See `docs/ai-integration-plan.md §2` for the full compliance checklist.

---

## 4. Configure Google Calendar

1. Open `https://console.cloud.google.com`.
2. Create or select a project, for example `Citable Local Test`.
3. Go to **APIs & Services > Library** and enable **Google Calendar API**.
4. Go to **APIs & Services > OAuth consent screen**.
5. Choose **External** while testing locally.
6. Fill in the required app information.
7. Add these scopes:
   - `https://www.googleapis.com/auth/calendar`
   - `https://www.googleapis.com/auth/calendar.events`
8. Add your Google email as a test user.
9. Go to **APIs & Services > Credentials**.
10. Click **Create Credentials > OAuth client ID**.
11. Set **Application type** to **Web application**.
12. Add this authorized redirect URI:

```text
http://localhost:3000/dashboard/google_oauth/callback
```

Copy the generated **Client ID** and **Client Secret** into Rails credentials.

---

## 5. Configure Twilio WhatsApp

Use Twilio's WhatsApp Sandbox for local development. The Sandbox is for testing only; production requires a registered WhatsApp sender.

You need:

- A Twilio account.
- The Twilio **Account SID**.
- The Twilio **Auth Token**.
- Access to the Twilio WhatsApp Sandbox.
- A test phone with WhatsApp installed.
- The Sandbox WhatsApp sender number, usually `+14155238886`.
- A local HTTPS tunnel URL for inbound webhook testing.

Join the Sandbox:

1. Open the Twilio Console.
2. Go to **Messaging > Try it out > Send a WhatsApp message** or the WhatsApp Sandbox page.
3. Activate the Sandbox if prompted.
4. From your WhatsApp test phone, send the displayed join message, such as `join example-code`, to the Sandbox number.
5. Wait for Twilio's confirmation reply.

Start a webhook tunnel:

```sh
cd ~/citable
ngrok http 3000
```

In the Twilio WhatsApp Sandbox settings, set:

| Field | Value |
|---|---|
| When a message comes in | `https://YOUR-NGROK-HOST.ngrok-free.app/webhooks/twilio` |
| Method | `POST` |

The app verifies Twilio signatures with `twilio.auth_token`, so the Auth Token in Rails credentials must match the Twilio account that sends the webhook.

---

## 6. Start the App

Run:

```sh
bin/dev
```

The app is ready when Rails prints a listening URL similar to:

```text
Listening on http://127.0.0.1:3000
```

Open the dashboard:

```text
http://localhost:3000/dashboard
```

Sign in:

| Field | Value |
|---|---|
| Email | `ana@example.com` |
| Password | `password123` |

---

## 7. Test Google Calendar Sync

Connect Google Calendar:

1. Open `http://localhost:3000/dashboard`.
2. Sign in as `ana@example.com`.
3. Open **Configuración**.
4. In the Google Calendar card, click **Conectar Google Calendar**.
5. Choose the Google test user you added to the OAuth consent screen.
6. Continue through the local app warning if Google shows one.
7. Grant calendar access.
8. Confirm that the Settings page shows the connected Google account.

Create a customer booking:

```text
http://localhost:3000/reservar
```

Submit a booking:

1. Select `Corte de cabello`.
2. Pick an upcoming date and a time during business hours.
3. Enter a customer name.
4. Enter the WhatsApp number that joined your Twilio Sandbox if you also want to test WhatsApp delivery.
5. Click **Confirmar cita**.

Expected result:

- The app shows a booking confirmation page.
- A booking appears in the dashboard with status `Pendiente`.
- A Google Calendar event appears for the selected time.

---

## 8. Test Twilio WhatsApp

### Outbound confirmation (from the public booking page)

When a public booking is created, `Public::BookingsController` enqueues:

```ruby
WhatsappSendJob.perform_later(@booking.id, :confirmation)
```

To test outbound WhatsApp:

1. Confirm `bin/dev` is running.
2. Confirm your test phone has joined the Twilio WhatsApp Sandbox.
3. Create a public booking at `http://localhost:3000/reservar`.
4. Use the joined Sandbox phone number as the customer WhatsApp number, in E.164 format, for example `+5215511111111`.

### Inbound guided booking flow

The app supports a full guided booking flow over WhatsApp. When a customer messages the business WhatsApp number, the app walks them through:

1. **Name** — collected once for new customers.
2. **Service selection** — numbered list of active services.
3. **Date and time** — customer enters a date and time.
4. **Address** — only asked if the selected service requires it.
5. **Confirmation** — customer replies `1` to confirm or `2` to cancel.

The seed data sets "Estudio de Ana" `whatsapp_number` to `14155238886` (the Twilio Sandbox sender). The inbound webhook matches the `To` field of each message to an account by that number. If no account matches, the request is silently ignored.

To test the guided booking flow:

1. Keep `bin/dev` running.
2. Keep `ngrok http 3000` running.
3. Confirm the Twilio Sandbox **When a message comes in** URL points to `https://YOUR-NGROK-HOST/webhooks/twilio`.
4. From the joined WhatsApp test phone, send any message to the Sandbox number.
5. Follow the prompts to select a service, enter a date/time, and confirm.

Expected result:

- Twilio sends a signed webhook to the local app through ngrok.
- `TwilioWebhook::HandleReply` resolves the account from `To`, finds or creates the customer from `From`, and advances the conversation step by step.
- After confirmation (`1`), a booking is created with status `pending` and assigned to the first available staff member.
- At each step, the app replies with the next prompt via `Whatsapp::MessageSender`.

### AI — greeting generation, NLU parsing, and confirmation

The seeded "Estudio de Ana" account has `ai_nlu_enabled: true`, which activates all Gemini 2.0 Flash AI features. When enabled, three stages of the conversation are enhanced:

**1. Conversation start — personalised greeting (`Llm::GreetingGenerator`)**

When a customer messages the business number for the first time, instead of the hardcoded "¡Hola! Para reservar tu cita…" prompt, the app calls `Llm::GreetingGenerator`. It generates a short, warm message in Mexican Spanish tailored to the business name and, for returning customers, to their name and the available services. New customers get a friendly name request; known customers get a greeting plus the numbered service list so they can still reply "1" or type the service name freely.

Fallback: if the Gemini key is missing, the LLM call raises `Llm::Client::Error` (rescued silently) and the hardcoded prompts are used exactly as before.

**2. Service and date/time steps — NLU parsing (`Llm::NluParser`)**

- **Service step:** if the customer types a service name instead of a number (e.g. `quiero un corte`), the LLM matches it to the closest active service with ≥ 0.8 confidence. Below that threshold, or if the Gemini key is missing, the app re-prompts with the numbered list as before.
- **Date/time step:** if the customer sends a natural-language date (e.g. `el viernes a las 3`, `mañana por la tarde a las 5`, `el próximo lunes a las 10am`), the LLM parses it to an ISO 8601 datetime. The same 0.8 confidence threshold and silent fallback apply.

**3. Confirmation step — natural-language acceptance (`Llm::NluParser.parse_confirmation`)**

At the final confirmation prompt the bot previously only accepted `1` (confirm) or `2` (cancel). With `ai_nlu_enabled`, it also accepts conversational replies:

| Customer says | Interpreted as |
|---|---|
| `dale`, `sí`, `claro`, `va`, `ok`, `perfecto`, `confirmo` | Confirmed |
| `no`, `mejor no`, `cancela`, `no puedo`, `no gracias` | Cancelled |

Rigid `1` / `2` are tried first; the LLM only fires for anything else. Below 0.8 confidence the bot re-prompts with "Responde 1 para confirmar o 2 para cancelar."

All three LLM calls share the same 4-second timeout and silent fallback — the conversation never breaks if the Gemini API is slow or unavailable.

**Enabling or disabling AI for an account:**

```ruby
# Rails console
account = Account.find_by(name: "Estudio de Ana")
account.update!(ai_nlu_enabled: true)   # enable all AI features
account.update!(ai_nlu_enabled: false)  # disable — strict FSM only
```

**Inspecting token usage:**

After any AI-assisted turn, the most recent inbound `MessageLog` for that account stores the token counts:

```ruby
account = Account.find_by(name: "Estudio de Ana")
account.message_logs.inbound.where.not(ai_model: nil).last
# => #<MessageLog ai_model: "gemini-2.0-flash", ai_input_tokens: 130, ai_output_tokens: 22>
# (ai_model reflects whichever model is set in credentials.gemini.model)
```

**Skipping AI locally:** if you do not add a `gemini.api_key` credential, all three AI features raise `Llm::Client::Error` internally and fall back silently. You do not need a Gemini key to run the app or test any other part of the booking flow.

### Existing confirm/cancel flow

Customers with an active upcoming booking who message the Sandbox number still get the legacy confirm/cancel flow — the guided booking flow only starts if there is no active upcoming booking for that customer.

- Reply `1` changes the booking status to `confirmed`.
- Reply `2` changes the booking status to `cancelled`.

---

## 9. Useful Local Commands

| Task | Command |
|---|---|
| Start app | `bin/dev` |
| Stop app | Press `Ctrl + C` in the `bin/dev` terminal |
| Run setup without starting server | `bin/setup --skip-server` |
| Reset database and seed data | `bin/setup --reset --skip-server` |
| Open Rails console | `bin/rails console` |
| List routes | `bin/rails routes` |
| Run test suite | `bin/rspec` |
| Run full CI locally | `bin/ci` |
| Tail development log | `tail -f log/development.log` |
| Check AI token usage | `MessageLog.where.not(ai_model: nil).sum(:ai_input_tokens)` (in Rails console) |
| Inspect last AI-assisted log | `Account.find_by(name: "Estudio de Ana").message_logs.inbound.where.not(ai_model: nil).last` (in Rails console) |
| Toggle all AI features for Ana's account | `Account.find_by(name: "Estudio de Ana").update!(ai_nlu_enabled: true\|false)` (in Rails console) |

---

## Troubleshooting

### `localhost:3000` does not load

Make sure `bin/dev` is running, then load:

```text
http://localhost:3000/dashboard
```

### Public booking page returns `Negocio no encontrado`

Make sure seed data exists:

```sh
bin/setup --skip-server
```

The public booking route is:

```text
http://localhost:3000/reservar
```

### PostgreSQL connection fails

Start PostgreSQL:

```sh
brew services start postgresql@16
```

Then rerun:

```sh
bin/setup --skip-server
```

### Rails credentials cannot be edited

Confirm the master key exists:

```sh
ls config/master.key
```

If it is missing, ask the project owner for `config/master.key`.

### Google OAuth shows `redirect_uri_mismatch`

Add the exact callback URL to the Google OAuth client:

```text
http://localhost:3000/dashboard/google_oauth/callback
```

### WhatsApp message is not received

Check these items:

- The customer phone number has joined your Twilio WhatsApp Sandbox.
- The booking form phone number is in E.164 format, such as `+5215511111111`.
- `twilio.whatsapp_number` is the Sandbox sender number without `whatsapp:`.
- `twilio.account_sid` and `twilio.auth_token` are from the same Twilio account as the Sandbox.
- `bin/dev` was restarted after editing credentials.
- The account has not exceeded its local WhatsApp quota.

### Twilio webhook returns `403 Forbidden`

The app rejected the Twilio signature. Confirm:

- The Rails credential `twilio.auth_token` matches the active Twilio account.
- The Twilio Sandbox webhook URL exactly matches the ngrok HTTPS URL plus `/webhooks/twilio`.
- The webhook method is `POST`.
- You did not restart ngrok without updating the Twilio webhook URL.

### AI features do not activate (no greeting, no free-text parsing)

Check in order:

1. Confirm `ai_nlu_enabled` is true for the account:
   ```ruby
   Account.find_by(name: "Estudio de Ana").ai_nlu_enabled? # => true
   ```
2. Confirm the `gemini.api_key` credential is set and `bin/dev` was restarted after editing credentials.
3. Check `log/development.log` for lines starting with `[Llm::GreetingGenerator]` or `[Llm::NluParser]`. A `WARN` line means the LLM call failed or returned low confidence and the fallback took over.
4. If the key is missing entirely, the log shows `Gemini API key not configured` and every AI step falls back silently. No action is needed unless you want the AI features active.

**AI greeting is not personalised / falls back to hardcoded prompt:**

- Check that `ai_nlu_enabled` is true *and* a valid `gemini.api_key` is set.
- Check `log/development.log` for `[Llm::GreetingGenerator] …` warn lines.
- A blank response from Gemini also triggers the fallback. This can happen on the free tier under load.

**"dale" / "sí" not accepted at the confirmation step:**

- Confirm `ai_nlu_enabled` is true.
- Check `log/development.log` for `[Llm::NluParser] parse_confirmation failed` lines.
- If Gemini returns low confidence (< 0.8), the bot re-prompts with "Responde 1 para confirmar o 2 para cancelar." — `1` and `2` always work regardless of AI status.

---

## Local URLs

| Purpose | URL |
|---|---|
| Dashboard | `http://localhost:3000/dashboard` |
| Login | `http://localhost:3000/dashboard/auth/entrar` |
| Public booking page | `http://localhost:3000/reservar` |
| Google OAuth callback | `http://localhost:3000/dashboard/google_oauth/callback` |
| Twilio webhook path | `/webhooks/twilio` |
| Twilio webhook through ngrok | `https://YOUR-NGROK-HOST/webhooks/twilio` |

---

## External References

- [Twilio WhatsApp Sandbox](https://www.twilio.com/docs/whatsapp/sandbox)
- [Twilio WhatsApp quickstart](https://www.twilio.com/docs/whatsapp/quickstart)
- [Twilio WhatsApp API addressing](https://www.twilio.com/docs/sms/whatsapp/api)
