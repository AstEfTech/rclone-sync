# Connecting rclone to Box

Instructions for a headless local server (no browser). The login happens on a computer with a browser; the token is pasted into the server.

## Requirements

- A Box account (personal or enterprise).
- rclone on the server **and** on a computer with a browser (the computer's version the same or newer):
  ```bash
  curl https://rclone.org/install.sh | sudo bash
  rclone version
  ```
- Optional: your own app in the Box Developer Console (Custom App, OAuth 2.0 with user authentication, redirect URI `http://127.0.0.1:53682/`, read and write scopes). Without it rclone uses its shared client. Enterprise accounts may need admin approval for the app.

## Part 1. Configuring rclone on the server

```bash
rclone config
```

| Question | Answer |
|---|---|
| `n` New remote | `n` |
| name | `box` |
| Storage | `box` |
| client_id / client_secret | empty (or your own) |
| box_config_file | empty (this is for the JWT mode) |
| box_sub_type | `1` (user) |
| Edit advanced config | `n` |
| Use web browser to automatically authenticate | **`n`** |

rclone prints a command like `rclone authorize "box" "eyJ..."`.

## Part 2. Getting the token on a computer with a browser

1. Run the printed command **in full** on the computer with a browser.
2. Sign in to Box and grant access.
3. Copy the JSON between the arrows and paste it at `config_token>` on the server.
4. Confirm: `y`, then `q`.

## Part 3. Verification

As the user the sync will run as (not root):

```bash
rclone lsd box:
rclone about box:
chmod 600 ~/.config/rclone/rclone.conf
```

## Re-authorization

```bash
rclone config reconnect box:
```

The Box refresh token is valid for 60 days and is renewed on each use; if the sync stays off for longer, reauthorize.

## Common errors

| Symptom | Cause and solution |
|---|---|
| `invalid_grant` / refresh token expired | Run `rclone config reconnect box:`. |
| `access_denied` on enterprise | The app is not approved by the Box admin. |
| Large files fail | Box limits the file size by account type. |
| `remote not found` | The remote was configured under another user. Configure it as `run_user`. |
