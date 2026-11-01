# Connecting rclone to iCloud Drive

Instructions for a headless local server (no browser). Unlike Google Drive there is no OAuth client or browser step: rclone logs in with your Apple ID, password and a two-factor code entered right in the terminal. The result is a trust token that rclone stores in `rclone.conf`.

> The `iclouddrive` backend is marked by rclone as **experimental (Tier 4)**: expect gaps and changes. The trust token is valid for **30 days**; after that you have to reauthenticate (see below), otherwise the sync silently stops.

## Requirements

- An Apple ID with two-factor authentication and access to a trusted device or a trusted phone number (for SMS).
- **Your regular Apple ID password.** App-specific passwords are not accepted.
- rclone **1.69 or newer** on the server. Install via the script from rclone.org, not from `apt` (the packaged version is usually too old):
  ```bash
  curl https://rclone.org/install.sh | sudo bash
  rclone version
  ```
- On the iPhone: Settings → Apple Account → iCloud → **Access iCloud Data on the Web** must be ON.

## Part 1. Configuring rclone on the server

Run it as the user the sync will run as (not root):

```bash
rclone config
```

Answers:

| Question | Answer |
|---|---|
| `n` New remote | `n` |
| name | `icloud` |
| Storage | `iclouddrive` |
| service | Enter (`drive` = iCloud Drive) or `2` (`photos` = iCloud Photos, see below) |
| apple_id | your Apple ID |
| password | `y`, then type your Apple ID password twice |
| Edit advanced config | `n` |
| config_2fa | the 6-digit code from the trusted device, or `sms` to get a text message |
| Yes this is OK | `y`, then `q` |

The prompt for the code appears right after the password: a notification arrives on your trusted devices. If you type `sms`, rclone asks for the code again after the text message arrives.

## Part 2. Verification

Run it as the same user that will run the sync:

```bash
rclone lsd icloud:
rclone about icloud:
```

The config with the password (obscured, not encrypted) and the trust token is in `~/.config/rclone/rclone.conf`. It gives access to the whole iCloud Drive:

```bash
chmod 600 ~/.config/rclone/rclone.conf
```

## iCloud Photos

Photos are a separate service of the same backend. Create a second remote (for example `icloudphotos`) and choose `service = photos`. It is **read-only**:

```bash
rclone lsd icloudphotos:                          # photo libraries (PrimarySync, SharedSync-XXXX)
rclone lsd icloudphotos:PrimarySync/              # albums
rclone ls  "icloudphotos:PrimarySync/Favorites/"  # photos in an album
```

To sync photos, set `src_remote: icloudphotos:PrimarySync/Favorites` (or another album) under `providers.icloud` in `config.yml`. The first listing of a very large album can take several minutes; later ones use a local cache in `~/.cache/rclone/iclouddrive-photos/`.

## Reauthentication (token expired, password changed)

```bash
rclone config reconnect icloud:
```

Enter the password and the 2FA code again. Set a reminder to do this about once a month: `icloud-pull` will log an authentication error when the token expires, and the systemd unit will be marked as failed.

## Advanced Data Protection (ADP)

ADP is supported. Make sure **Access iCloud Data on the Web** is ON on the iPhone. After the 2FA code rclone requests PCS cookies, and Apple may ask you to approve this on a trusted device: do it promptly.

## Common errors

| Symptom | Cause and solution |
|---|---|
| Login fails with a correct password | An app-specific password was used. Use the regular Apple ID password. |
| `Missing PCS cookies from the request` or `requestPCS:` | The ADP approval did not complete. Enable **Access iCloud Data on the Web**, approve the prompt on the trusted device and run `rclone config reconnect icloud:`. |
| Still fails after that | Stale auth state. Clear the `cookies` and `trust_token` fields in the config, or delete and recreate the remote. |
| Authentication errors about a month after setup | The 30-day trust token expired. Run `rclone config reconnect icloud:`. |
| `didn't find section in config file` / remote not found | The remote was configured under another user. Configure it as `run_user`. |
| `unknown backend type "iclouddrive"` | rclone is older than 1.69. Update it via the script from rclone.org. |
