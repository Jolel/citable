# Local Testing Guide — Citable

This guide walks you through running Citable on your Mac from scratch, creating a test booking, and verifying that it appears in Google Calendar. No programming experience required.

**Time required:** ~30–40 minutes  
**What you'll need:** A Mac, an internet connection, and a personal Google account.

---

## What You'll Test

By the end of this guide you will:

1. Run the app on your Mac (no internet hosting required).
2. Log in as a salon owner (a pre-loaded demo account).
3. Connect the app to your Google Calendar.
4. Create an appointment booking via the public booking page.
5. Confirm the booking from the owner dashboard.
6. Open Google Calendar and see the appointment appear automatically.

---

## Part 1 — Install the Tools You Need

You only need to do Part 1 once. If you already have Homebrew, Ruby, and PostgreSQL installed, skip to Part 2.

### Step 1 — Open Terminal

Press **Command + Space**, type **Terminal**, and press **Enter**. A black (or white) window with a cursor will appear. You'll type all commands in this window.

### Step 2 — Install Homebrew

Homebrew is a tool that installs other tools. Paste this entire line and press **Enter**:

```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

When it asks for your Mac password, type it (you won't see the characters — that's normal) and press **Enter**. This will take 2–5 minutes.

When it finishes, it may show instructions to add Homebrew to your PATH. If you see lines starting with `echo` and `eval`, copy and run them one by one before continuing.

Verify it worked:
```
brew --version
```
You should see something like `Homebrew 4.x.x`.

### Step 3 — Install rbenv and Ruby 3.3.6

rbenv lets you install and manage Ruby versions. Run these three commands one at a time:

```
brew install rbenv ruby-build
```

```
rbenv install 3.3.6
```

This installs Ruby 3.3.6. It takes 3–8 minutes depending on your connection.

```
rbenv global 3.3.6
```

Add rbenv to your shell so it works in new Terminal windows. Run:

```
echo 'eval "$(rbenv init - zsh)"' >> ~/.zshrc && source ~/.zshrc
```

Verify Ruby is ready:
```
ruby --version
```
You should see `ruby 3.3.6`.

### Step 4 — Install PostgreSQL (the database)

```
brew install postgresql@16
```

Start the database and make it start automatically when your Mac boots:

```
brew services start postgresql@16
```

Verify it is running:
```
brew services list | grep postgresql
```
The status should say `started`.

### Step 5 — Install Git (if needed)

Git downloads and manages code. It may already be installed:

```
git --version
```

If it shows a version number, skip ahead. If not:

```
brew install git
```

---

## Part 2 — Download and Set Up the App

### Step 6 — Download the Code

Navigate to your home folder and download the app:

```
cd ~
git clone https://github.com/jolel/citable.git
cd citable
```

You are now inside the `citable` folder. All following commands must be run from this folder. If you open a new Terminal window, run `cd ~/citable` first.

### Step 7 — Install App Dependencies and Set Up the Database

Run:

```
bin/setup --skip-server
```

This automatically:
- Downloads all required libraries (~3 minutes on a good connection).
- Creates the database and runs all migrations.
- Loads demo data (a salon called "Estudio de Ana" with services, staff, and one sample booking).

When it finishes you should see:
```
Done! Visit http://ana.localhost:3000 and sign in as ana@example.com / password123
```

---

## Part 3 — Set Up Google Calendar Access

This step connects the app to Google's services so bookings can appear in your calendar.

### Step 8 — Create a Google Cloud Project

You need to generate credentials (a "Client ID" and "Client Secret") from Google. This is free.

1. Open a browser and go to: **https://console.cloud.google.com**
2. Sign in with any Google account.
3. At the top of the page, click the project selector (it may say "Select a project" or show an existing project name).
4. Click **New Project**.
5. Name it `Citable Local Test` and click **Create**.
6. Wait a few seconds, then make sure the new project is selected at the top.

### Step 9 — Enable the Google Calendar API

1. In the left sidebar, go to **APIs & Services → Library**.
2. In the search bar, type `Google Calendar API`.
3. Click on **Google Calendar API** in the results.
4. Click the blue **Enable** button.

### Step 10 — Configure the OAuth Consent Screen

Before creating credentials you must configure what users will see when they authorize the app.

1. In the left sidebar, go to **APIs & Services → OAuth consent screen**.
2. Select **External** and click **Create**.
3. Fill in the required fields:
   - **App name:** `Citable Local Test`
   - **User support email:** your email address
   - **Developer contact information:** your email address
4. Click **Save and Continue**.
5. On the **Scopes** step, click **Add or Remove Scopes**.
6. In the search box type `calendar` and check the box for `.../auth/calendar` (full access to Google Calendar).
7. Click **Update**, then **Save and Continue**.
8. On the **Test users** step, click **+ Add Users** and add your own Google email address. Click **Save and Continue**.
9. Review and click **Back to Dashboard**.

### Step 11 — Create OAuth 2.0 Credentials

1. In the left sidebar, go to **APIs & Services → Credentials**.
2. Click **+ Create Credentials → OAuth client ID**.
3. Set **Application type** to **Web application**.
4. Name it `Citable Local`.
5. Under **Authorized redirect URIs**, click **+ Add URI** and paste exactly:
   ```
   http://localhost:3000/dashboard/auth/users/auth/google_oauth2/callback
   ```
6. Click **Create**.
7. A popup will show your **Client ID** and **Client Secret**. Keep this window open — you'll need both values in the next step.

### Step 12 — Add the Credentials to the App

Back in Terminal, run:

```
EDITOR=nano bin/rails credentials:edit
```

This opens a text editor inside Terminal. Use the arrow keys to navigate to the bottom of the file. Add these lines exactly (replace the placeholder values with your real credentials from Step 11):

```yaml
google:
  client_id: "PASTE_YOUR_CLIENT_ID_HERE"
  client_secret: "PASTE_YOUR_CLIENT_SECRET_HERE"
```

To save and exit nano: press **Ctrl + X**, then **Y**, then **Enter**.

> **Tip:** Make sure `google:` is at the same indentation level as any other top-level keys in the file (no leading spaces). The `client_id:` and `client_secret:` lines must be indented by 2 spaces.

---

## Part 4 — Start the App

### Step 13 — Start the Development Server

```
bin/dev
```

You will see log output scrolling by. The app is ready when you see:
```
* Listening on http://127.0.0.1:3000
```

Leave this Terminal window running. The app stops if you close it or press **Ctrl + C**.

> **Open a second Terminal window** (Command + T or Command + N) for any other commands. From the new window, run `cd ~/citable` first.

---

## Part 5 — Test the Full Booking Flow

### Step 14 — Open the Dashboard

In your browser (Chrome or Safari work best), go to:

```
http://ana.localhost:3000/dashboard
```

You will be redirected to the login page. Sign in with:
- **Email:** `ana@example.com`
- **Password:** `password123`

You should see the bookings dashboard for "Estudio de Ana".

### Step 15 — Connect Your Google Calendar

1. In the dashboard sidebar, click **Configuración** (Settings).
2. You will see a card titled **Google Calendar**.
3. Click the **Conectar Google Calendar** button.
4. Your browser will redirect to Google. Select your Google account.
5. You may see a warning that says "Google hasn't verified this app" — click **Continue** (this is expected for local development apps).
6. Grant permission to manage your calendar and click **Continue**.
7. You will be returned to the Settings page with the message "Google Calendar conectado correctamente."

The Google Calendar card now shows your email address, confirming the connection.

### Step 16 — Make a Test Booking (as a Customer)

Open a **new browser tab** and go to:

```
http://ana.localhost:3000/reservar
```

This is the public booking page a customer would use (no login required).

1. **Select a service** — for example, "Corte de cabello" (45 min, $250).
2. Click **Siguiente** (Next).
3. **Pick a date and time** — choose any upcoming date and a time between 9:00 AM and 6:00 PM.
4. Click **Siguiente**.
5. **Enter customer details:**
   - **Nombre completo:** `Rosa Martínez` (or any name)
   - **Número de WhatsApp:** `+5215511111111`
6. Click **Confirmar cita**.

You should see a confirmation page.

### Step 17 — Confirm the Booking in the Dashboard

1. Switch back to the dashboard tab (`http://ana.localhost:3000/dashboard`).
2. The new booking should appear in the list with status **Pendiente** (Pending).
3. Click on the booking to open it.
4. Click the **Confirmar** (Confirm) button.

The status changes to **Confirmada**.

### Step 18 — Verify in Google Calendar

1. Open **https://calendar.google.com** in a new tab.
2. Look for today or the date you selected in Step 16.
3. You should see an event titled **"Corte de cabello — Rosa Martínez"** at the time you booked.

> The Google Calendar sync runs in the background. If you don't see the event immediately, wait 5–10 seconds and refresh the calendar page.

---

## Part 6 — Verify the Sync Works End to End

Here is a quick checklist to confirm everything is working:

| Action | Expected Result |
|---|---|
| Submit booking from `/reservar` | Event appears in Google Calendar |
| Confirm booking from dashboard | Calendar event status updated |
| Cancel booking from dashboard | Calendar event marked as cancelled |
| Click "Desconectar" in Settings | Google Calendar connection removed; new bookings won't sync |

---

## Troubleshooting

### "This site can't be reached" at `ana.localhost:3000`

- Make sure the server is running (`bin/dev` in Terminal).
- Try Chrome instead of Firefox. Chrome and Safari resolve `*.localhost` automatically; Firefox may not.
- If using Firefox, you need to add an entry to your system's hosts file. In Terminal:
  ```
  echo "127.0.0.1 ana.localhost" | sudo tee -a /etc/hosts
  ```
  Enter your Mac password when prompted, then reload the browser.

### "PG::ConnectionBad" or database error

PostgreSQL is not running. Start it:
```
brew services start postgresql@16
```

### Google OAuth error: "redirect_uri_mismatch"

The redirect URI in Google Cloud Console doesn't match. Go back to Step 11 and make sure the Authorized redirect URI is exactly:
```
http://localhost:3000/dashboard/auth/users/auth/google_oauth2/callback
```
No trailing slash, no typos.

### "Invalid credentials" when editing Rails credentials

You may be missing the master key file. Check if it exists:
```
ls config/master.key
```
If it doesn't exist, ask the project owner for the `config/master.key` file. Without it you cannot edit credentials.

### The Google Calendar event doesn't appear

1. Check that your account is connected (Settings page shows your email under Google Calendar).
2. Open a second Terminal, go to the app folder, and check the logs:
   ```
   tail -f log/development.log | grep GoogleCalendar
   ```
   Make a new booking. You should see a line like:
   ```
   [GoogleCalendarSyncJob] Created event <event_id> for booking <id>
   ```
   If you see an error instead, the credentials may be incorrect — repeat Step 12.

### "Google hasn't verified this app" warning

This is normal for a local development app. Click **Continue** (or **Advanced → Go to Citable Local Test (unsafe)**). This warning only appears because the app is not published — it is not a security risk for your own local test.

---

## Stopping and Restarting the App

To **stop** the app: press **Ctrl + C** in the Terminal window running `bin/dev`.

To **restart** the app: run `bin/dev` again from the `citable` folder.

To **reset all data** to a clean state (deletes all bookings and restores demo data):
```
bin/setup --reset
```

---

## Demo Account Credentials

| Field | Value |
|---|---|
| Owner email | `ana@example.com` |
| Owner password | `password123` |
| Staff email | `maria@example.com` |
| Staff password | `password123` |
| Dashboard URL | `http://ana.localhost:3000/dashboard` |
| Public booking URL | `http://ana.localhost:3000/reservar` |

The demo account includes 3 services (Corte de cabello, Tinte y highlights, Peinado especial), 2 staff members (Ana and María), and one sample booking for tomorrow at 10 AM.
