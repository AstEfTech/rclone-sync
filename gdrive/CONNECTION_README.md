# Getting Google credentials and a token for rclone (Google Drive)

Instructions for a headless local server (no browser). It uses your own OAuth client ID rather than rclone's shared key: there are no hard rate limits and the token does not expire after 7 days.

## Requirements

- A Google account (regular Gmail or Workspace).
- rclone on the server **and** on a computer with a browser. The computer's version should be the same or newer. Install via the script from rclone.org, not from `apt`:
  ```bash
  curl https://rclone.org/install.sh | sudo bash
  rclone version
  ```
  On Windows/macOS: download from https://rclone.org/downloads/

## Part 1. Creating an OAuth client ID in Google Cloud

### 1.1 Project and API
1. Open https://console.cloud.google.com/ and create a project (e.g. `rclone-sync`).
2. **APIs & Services → Library** → find **Google Drive API** → **Enable**.

### 1.2 Google Auth Platform (consent screen)
1. **APIs & Services → OAuth consent screen** (Google Auth Platform section) → **Get started**.
2. **Branding:**
   - App name: `rclone-sync`
   - User support email: your Gmail
   - App home page and Privacy policy link: any real https links (e.g. a GitHub Pages page or a public gist with one line: "Personal rclone backup tool, no user data is collected"). Google does not check the content, only the format.
   - Developer contact information: your email
   - Do not upload a logo (it triggers extra verification). Do not add anything to Authorized domains.
3. **Audience:** `External` for Gmail, `Internal` for Workspace.
4. **Data Access → Add or remove scopes:** add `https://www.googleapis.com/auth/drive`.
5. **Audience → Test users:** add your Gmail (required while the status is Testing).
6. **Audience → Publish app → Confirm.** The status must become **In production**.

> Important: if you leave the status as **Testing**, the refresh token dies after 7 days (`invalid_grant`) and the sync silently breaks. App verification is not required. At login Google shows the warning "Google hasn't verified this app": Advanced → Go to rclone-sync (unsafe).

### 1.3 Creating the client
1. **Google Auth Platform → Clients → Create client** (or Credentials → Create credentials → OAuth client ID).
2. Application type: **Desktop app** (not Web application!). Name: `rclone-sync`.
3. Copy the **Client ID** and **Client secret** (the secret may only be shown at creation).

## Part 2. Configuring rclone on the server

```bash
rclone config
```

Answers:

| Question | Answer |
|---|---|
| `n` New remote | `n` |
| name | `gdrive` |
| Storage | `drive` |
| client_id | paste yours |
| client_secret | paste yours |
| scope | `1` (Full access) |
| service_account_file | empty |
| Edit advanced config | `n` |
| Use web browser to automatically authenticate | **`n`** (the server has no browser) |

rclone will print a command like:

```
rclone authorize "drive" "eyJ....long string...."
```

## Part 3. Getting the token on a computer with a browser

1. Copy the command **in full**, including the long quoted string (it embeds your client_id and secret).
2. Run it on the computer that has a browser and rclone.
3. A browser opens: sign in to Google and allow access (Advanced → Go to rclone-sync (unsafe) → Continue).
4. A block appears in the terminal:
   ```
   Paste the following into your remote machine --->
   {"access_token":"...","token_type":"Bearer","refresh_token":"...","expiry":"..."}
   <---End paste
   ```
5. Copy the JSON between the arrows and paste it on the server at the `config_token>` prompt.
6. For the Shared Drive question: `n` (for a regular "My Drive").
7. Confirm saving: `y`, then `q`.

> If you run just `rclone authorize "drive"` without the long string, authorization goes through rclone's shared client and the token will not fit your config.

## Part 4. Verification

Run as the same user the sync will run as (not root):

```bash
rclone lsd gdrive:
rclone about gdrive:
```

The config with the token is `~/.config/rclone/rclone.conf`. It grants full access to Drive:

```bash
chmod 600 ~/.config/rclone/rclone.conf
```

## Re-authorization (token expired or client ID changed)

```bash
rclone config update gdrive client_id=NEW_ID client_secret=NEW_SECRET
rclone config reconnect gdrive:
```

Answer `n` to the browser question, then proceed as in Part 3.

## Common errors

| Symptom | Cause and solution |
|---|---|
| `redirect_uri_mismatch` | The client was created as Web application. Create a new one of type **Desktop app**. Or add `http://127.0.0.1:53682/` to Authorized redirect URIs. Or an old rclone (OOB redirect): update it on both machines. |
| `invalid_grant` after about a week | The app stayed in Testing. Move it to In production and re-authorize. |
| `access_denied` at login | The account is not in Test users (if the status is Testing). |
| `accessNotConfigured` | Drive API is not enabled in the project. |
| `rateLimitExceeded` | rclone's shared client_id is used instead of your own. |
| "valid app name, support email, homepage url, privacy policy url are required" when publishing | Fill in all fields on the Branding page, then Publish app again. |
| After moving to Production the token still lives 7 days | The token was issued before the status change. Run `rclone config reconnect gdrive:`. |
