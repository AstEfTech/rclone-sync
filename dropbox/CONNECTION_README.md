# Connecting rclone to Dropbox

Instructions for a headless local server (no browser). Works for personal Dropbox and Dropbox Business (team member access). The login happens on a computer with a browser; the token is pasted into the server.

## Requirements

- A Dropbox account.
- rclone on the server **and** on a computer with a browser (the computer's version the same or newer):
  ```bash
  curl https://rclone.org/install.sh | sudo bash
  rclone version
  ```
- Recommended: your own app. At https://www.dropbox.com/developers/apps choose **Create app → Scoped access → Full Dropbox**, and on the Permissions tab enable `files.metadata.read`, `files.metadata.write`, `files.content.read`, `files.content.write`, then Submit. Copy the **App key** and **App secret**. Without it rclone uses its shared key.

## Part 1. Configuring rclone on the server

```bash
rclone config
```

| Question | Answer |
|---|---|
| `n` New remote | `n` |
| name | `dropbox` |
| Storage | `dropbox` |
| client_id / client_secret | App key / App secret (or empty) |
| Edit advanced config | `n` |
| Use web browser to automatically authenticate | **`n`** |

rclone prints a command like `rclone authorize "dropbox" "eyJ..."`.

## Part 2. Getting the token on a computer with a browser

1. Run the printed command **in full** on the computer with a browser.
2. Sign in to Dropbox and allow access.
3. Copy the JSON between the arrows and paste it at `config_token>` on the server.
4. Confirm: `y`, then `q`.

## Part 3. Verification

As the user the sync will run as (not root):

```bash
rclone lsd dropbox:
rclone about dropbox:
chmod 600 ~/.config/rclone/rclone.conf
```

## Re-authorization

```bash
rclone config reconnect dropbox:
```

## Common errors

| Symptom | Cause and solution |
|---|---|
| `missing_scope` | A permission was not enabled before authorizing: enable it in the app, then `rclone config reconnect dropbox:`. |
| `too_many_requests` / `too_many_write_operations` | Rate limit: lower `--transfers` in `dropbox/provider.conf`. |
| Dropbox Paper docs or shortcuts are skipped | rclone cannot download them as plain files. |
| `remote not found` | The remote was configured under another user. Configure it as `run_user`. |
