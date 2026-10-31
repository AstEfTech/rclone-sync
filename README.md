# rclone-sync: Google Drive → local disk

[Русская версия](README_RU.md)

One-way sync from Google Drive to a local disk on a Raspberry Pi every 15 minutes (source, destination and user are set in `.env`).
Only `rclone copy` is used: nothing is ever deleted.

## Environment

| What | Value |
|---|---|
| Host | Raspberry Pi (Linux); rclone, the script and systemd run as `RUN_USER`, not root |
| Source | `SRC_REMOTE` (e.g. `gdrive:Media`; a regular Google account, OAuth client of type **Desktop app**, app status In production) |
| Destination | `DST_DIR` on a disk mounted at `MOUNT_POINT` |
| rclone config | `~/.config/rclone/rclone.conf` of `RUN_USER` (`chmod 600`) |
| rclone install | via the script from rclone.org |

Getting the OAuth client ID and token and setting up the `gdrive` remote: [gdrive/CONNECTION_README.md](gdrive/CONNECTION_README.md). Do this before running `deploy.sh`.

## Layout

```
gdrive/
├── .env.example                 # template for personal settings
├── CONNECTION_README.md         # getting Google credentials and configuring rclone
├── deploy.sh                    # installs the script and units
├── scripts/
│   ├── gdrive-pull.sh           # main script
│   └── watch-log.sh             # tail -f of the latest log
└── system/
    ├── gdrive-pull.service.in   # unit template: oneshot, Nice=10, IOSchedulingClass=idle
    └── gdrive-pull.timer        # OnCalendar=*:0/15, Persistent=true, RandomizedDelaySec=30
```

Layout on the Pi (`APP_DIR` from `.env`):

| File | Path |
|---|---|
| Script | `$APP_DIR/gdrive-pull.sh` |
| Logs | `$APP_DIR/log/YYYY-MM-DD_HH-MM-SS.log` (one per run, deleted after 14 days) |
| Lock | `$APP_DIR/.lock` |
| Settings | `$APP_DIR/.env` (copy, chmod 600) |
| Units | `/etc/systemd/system/gdrive-pull.{service,timer}` |

## Installation

```bash
git clone https://github.com/AstEfTech/rclone-sync.git
cd rclone-sync/gdrive
cp .env.example .env
$EDITOR .env       # fill in RUN_USER, SRC_REMOTE, DST_DIR (inside MOUNT_POINT), MOUNT_POINT, APP_DIR
./deploy.sh        # as RUN_USER, not via sudo
```

`.env` is required: `deploy.sh` will not run without it. The script checks that rclone is installed (if not, it asks for confirmation and installs it via the script from rclone.org) and that the remote from `SRC_REMOTE` is configured for `RUN_USER`; then it copies the files to `APP_DIR`, substitutes values into the unit template, runs `daemon-reload` and enables the timer. `.env` is not tracked by git.

Line endings: during installation `deploy.sh` strips CR from `.env`, scripts and units, so CRLF from Windows is not a problem. The exception is `deploy.sh` itself: bash will not run a file with CRLF. If it arrived with CRLF, run `sed -i 's/\r$//' deploy.sh` once.

## Script logic

1. `flock -n` on `.lock`: if the previous run is still going, exit with code 0.
2. Check `mountpoint $MOUNT_POINT` and at least 5 GB of free space.
3. `rclone copy $SRC_REMOTE $DST_DIR` with the options:
   `--transfers 4 --checkers 8 --drive-skip-gdocs --exclude ".Trash-*/**" --stats 30s --stats-file-name-length 0`,
   the log is written via `--log-file` into `log/`.
4. `LOG_LEVEL=INFO` by default, overridable via an environment variable (`LOG_LEVEL=DEBUG` for debugging).
5. A non-zero rclone exit code is logged and returned to the caller (the unit is marked as failed).

## Operation

```bash
# enable the timer
sudo systemctl enable --now gdrive-pull.timer

# manual run (does not block the terminal)
sudo systemctl start --no-block gdrive-pull.service

# status and journal
systemctl list-timers | grep gdrive
journalctl -u gdrive-pull -f

# latest run log
tail -f "$(ls -t $APP_DIR/log/*.log | head -1)"   # or $APP_DIR/watch-log.sh

# after editing unit files (better to edit the template and rerun deploy.sh)
sudo systemctl daemon-reload
```

## Behavior

- **Overlapping runs.** systemd does not start a second instance of a oneshot unit, and `flock` guards against manual runs. Missed triggers do not pile up.
- **Interruption.** An interrupted file is downloaded again (rclone writes to a temporary `.partial`); completed files are skipped.

## Solved problems

| Symptom | Cause / solution |
|---|---|
| `redirect_uri_mismatch` | The OAuth client must be of type Desktop app |
| Cannot publish to Production | Fill in Branding: name, email, homepage, privacy policy |
| `permission denied` on `mkdir` | `DST_DIR` must be owned by `RUN_USER`; for NTFS/exFAT set `uid`/`gid` in fstab |
| `permission denied` on `/tmp/gdrive-pull.lock` | The lock was moved to the script directory; always run as `RUN_USER`, not via `sudo` |
| `systemctl start` blocks the terminal (oneshot) | Use `--no-block` or rely on the timer |

## Possible improvements

- Failure notifications.
- `--fast-list` for large trees.
- `--update` or `--ignore-existing` to avoid overwriting local files.
