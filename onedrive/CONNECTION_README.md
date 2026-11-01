# Connecting rclone to Microsoft OneDrive

Instructions for a headless local server (no browser). Works for personal OneDrive, OneDrive for Business and SharePoint Online document libraries. The login happens on a computer with a browser; the token is pasted into the server.

## Requirements

- A Microsoft account (personal, work or school).
- rclone on the server **and** on a computer with a browser (the computer's version the same or newer). Install via the script from rclone.org, not from `apt`:
  ```bash
  curl https://rclone.org/install.sh | sudo bash
  rclone version
  ```
- Optional: your own app registration (Azure portal → App registrations, redirect URI `http://localhost:53682/`, delegated permissions `Files.ReadWrite.All`, `offline_access`) and its client ID/secret. Without it rclone uses its shared client, which works but shares rate limits. Work/school tenants may require admin consent for third-party apps.

## Part 1. Configuring rclone on the server

```bash
rclone config
```

| Question | Answer |
|---|---|
| `n` New remote | `n` |
| name | `onedrive` |
| Storage | `onedrive` |
| client_id / client_secret | empty (or your own) |
| region | `1` (Microsoft Cloud Global) |
| Edit advanced config | `n` |
| Use web browser to automatically authenticate | **`n`** (the server has no browser) |

rclone prints a command like `rclone authorize "onedrive" "eyJ..."`.

## Part 2. Getting the token on a computer with a browser

1. Run the printed command **in full** on a computer with a browser and rclone.
2. Sign in to Microsoft and allow access.
3. Copy the JSON between `Paste the following into your remote machine --->` and `<---End paste` and paste it at `config_token>` on the server.
4. Choose the drive type: `1` OneDrive Personal or Business, `2` root SharePoint site, `3` a site by URL, `4` a library by name. Pick the drive from the list the wizard shows.
5. Confirm: `y`, then `q`.

## Part 3. Verification

As the user the sync will run as (not root):

```bash
rclone lsd onedrive:
rclone about onedrive:
chmod 600 ~/.config/rclone/rclone.conf
```

## Re-authorization

```bash
rclone config reconnect onedrive:
```

The refresh token expires after about 90 days without use; a regularly running sync keeps it alive.

## Common errors

| Symptom | Cause and solution |
|---|---|
| `AADSTS65001` / admin approval required | The tenant blocks third-party apps: ask the admin or use your own app registration. |
| `invalid_grant` / token expired | Run `rclone config reconnect onedrive:`. |
| `Item does not exist` on a library | Wrong drive chosen in the wizard: `rclone config` → edit the remote and pick again. |
| `activityLimitReached` / 429 | Throttling by Microsoft: lower `--transfers` in `onedrive/provider.conf`. |
| `remote not found` | The remote was configured under another user. Configure it as `run_user`. |
