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

Twilio is required only for WhatsApp testing. You can run the app and test Google Calendar without it.

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

Add the Google and Twilio sections shown below. Replace every placeholder with the real value.

```yaml
google:
  client_id: "PASTE_GOOGLE_CLIENT_ID_HERE"
  client_secret: "PASTE_GOOGLE_CLIENT_SECRET_HERE"

twilio:
  account_sid: "PASTE_TWILIO_ACCOUNT_SID_HERE"
  auth_token: "PASTE_TWILIO_AUTH_TOKEN_HERE"
  whatsapp_number: "+14155238886"
```

For nano, save and exit with **Ctrl + X**, then **Y**, then **Enter**.

Credential notes:

- `google.client_id` and `google.client_secret` come from the Google Cloud OAuth client.
- `twilio.account_sid` and `twilio.auth_token` come from the Twilio Console.
- `twilio.whatsapp_number` must be the WhatsApp sender number without the `whatsapp:` prefix.
- For the Twilio WhatsApp Sandbox, the sender is usually `+14155238886`.

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

When a public booking is created, `Public::BookingsController` enqueues:

```ruby
WhatsappSendJob.perform_later(@booking.id, :confirmation)
```

To test outbound WhatsApp:

1. Confirm `bin/dev` is running.
2. Confirm your test phone has joined the Twilio WhatsApp Sandbox.
3. Create a public booking at `http://localhost:3000/reservar`.
4. Use the joined Sandbox phone number as the customer WhatsApp number, in E.164 format, for example `+5215511111111`.

To test inbound WhatsApp replies:

1. Keep `bin/dev` running.
2. Keep `ngrok http 3000` running.
3. Confirm the Twilio Sandbox **When a message comes in** URL points to `https://YOUR-NGROK-HOST/webhooks/twilio`.
4. From the joined WhatsApp test phone, reply to the Sandbox sender:
   - `1` confirms the active booking.
   - `2` cancels the active booking.

Expected result:

- Twilio sends a signed webhook to the local app through ngrok.
- `TwilioWebhook::HandleReply` finds the customer by phone number.
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
| Run test suite | `bundle exec rspec` |
| Tail development log | `tail -f log/development.log` |

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
