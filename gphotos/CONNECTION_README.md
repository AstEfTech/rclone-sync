# Connecting rclone to Google Photos

Instructions for a headless local server (no browser). The `gphotos` backend is meant for downloading: use it with `copy` (or `copyto`), not with `twoway`, `bisync`, `move`, `moveto` or `sync`, which would write to the library or delete from it.

> Since 2025 the Google Photos Library API only gives an app access to media that **the app itself uploaded**. A new client may therefore see an empty library; the backend works fully only with clients authorized before that change. If your library comes back empty, use Google Takeout or Google Drive for a one-off export instead.

## Requirements

- A Google account.
- rclone on the server **and** on a computer with a browser (the computer's version the same or newer):
  ```bash
  curl https://rclone.org/install.sh | sudo bash
  rclone version
  ```
- Your own OAuth client (Desktop app), created as in [../gdrive/CONNECTION_README.md](../gdrive/CONNECTION_README.md) Part 1, but enable the **Photos Library API** instead of the Drive API and add the scope `https://www.googleapis.com/auth/photoslibrary.readonly`. Publish the app to **In production**, otherwise the token dies after 7 days.

## Part 1. Configuring rclone on the server

```bash
rclone config
```

| Question | Answer |
|---|---|
| `n` New remote | `n` |
| name | `gphotos` |
| Storage | `google photos` |
| client_id / client_secret | paste yours |
| read_only | `true` |
| Edit advanced config | `n` |
| Use web browser to automatically authenticate | **`n`** |

rclone prints a command like `rclone authorize "google photos" "eyJ..."`. Run it **in full** on a computer with a browser, sign in, copy the JSON between the arrows and paste it at `config_token>` on the server. Confirm: `y`, then `q`.

## Part 2. Verification

As the user the sync will run as (not root):

```bash
rclone lsd gphotos:
rclone lsd gphotos:album
chmod 600 ~/.config/rclone/rclone.conf
```

Virtual directories: `media/by-month`, `media/by-day`, `album`, `shared-album`, `upload`, `feature`. Example `src` for a pair: `gphotos:media/by-month` (all photos) or `gphotos:album/Holiday`.

## Re-authorization

```bash
rclone config reconnect gphotos:
```

## Common errors

| Symptom | Cause and solution |
|---|---|
| Library is empty | See the note at the top: the API only exposes app-uploaded media. |
| `invalid_grant` after about a week | The app stayed in Testing: move it to In production and re-authorize. |
| Images are not the original | The API returns re-encoded files and strips location metadata. |
| `rateLimitExceeded` | Lower `--transfers` in `gphotos/provider.conf`. |
