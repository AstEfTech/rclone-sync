# rclone-sync: cloud storage → local disk

Setting up RClone for local storage might be a real pain, so i decided to automate this process and make it more accessible.

rclone-sync keeps folders of a cloud storage and folders on a local disk in sync on a Linux server. You describe **folder pairs** (source → destination) with a **sync type** for each pair in one `config.yml`, and `deploy.sh` installs a script and a systemd timer for every provider you use (every 15 minutes by default). Providers are independent: each has its own timer, lock, logs and settings.

## Supported providers

| Provider | Name | Example `src` | rclone backend | Notes |
|---|---|---|---|---|
| Google Drive | `gdrive` | `gdrive:Media` | `drive` | Shared Drives supported |
| Google Photos | `gphotos` | `gphotos:media/by-month` | `google photos` | Download only (use `copy`); the API only exposes app-uploaded media since 2025 |
| iCloud Drive | `icloud` | `icloud:SomeDir` | `iclouddrive` | Experimental, trust token lasts 30 days; Photos via a separate read-only remote |
| Microsoft OneDrive | `onedrive` | `onedrive:Documents` | `onedrive` | Personal, Business and SharePoint Online |
| Dropbox | `dropbox` | `dropbox:Files` | `dropbox` | Personal and Business |
| Box | `box` | `box:Work` | `box` | Personal and enterprise |
| Amazon S3 | `s3` | `s3:my-bucket/backups` | `s3` | AWS and any S3-compatible service (MinIO, R2, Spaces, ...) |
| Backblaze B2 | `b2` | `b2:my-bucket/backups` | `b2` | Application key; old versions stay as hidden versions |
| Google Cloud Storage | `gcs` | `gcs:my-bucket/backups` | `google cloud storage` | Service account JSON key |
| Azure Blob Storage | `azureblob` | `azureblob:my-container/backups` | `azureblob` | Account key or SAS URL |
| Wasabi | `wasabi` | `wasabi:my-bucket/backups` | `s3` (provider Wasabi) | Billed minimum retention for deleted objects |

Every provider has a guide for getting credentials and creating the rclone remote (do this before `deploy.sh`): `<name>/CONNECTION_README.md`, e.g. [gdrive/CONNECTION_README.md](gdrive/CONNECTION_README.md), [onedrive/CONNECTION_README.md](onedrive/CONNECTION_README.md), [s3/CONNECTION_README.md](s3/CONNECTION_README.md). Cloud drives log in through a browser on another computer (OAuth token pasted into the server) or with a password and 2FA code; object storages use access keys, a service account key or a SAS URL. All guides are listed in the [layout](#layout).

## Environment

| What | Value |
|---|---|
| Host | Local server (Linux, systemd); rclone, the scripts and the timers run as `run_user`, not root |
| Source | `providers.<name>.pairs.<pair>.src`: `<remote>:<path>` of a remote configured in rclone |
| Destination | `providers.<name>.pairs.<pair>.dst`: a directory on a local disk (optionally a separate disk mounted at `mount_point`) |
| rclone config | `~/.config/rclone/rclone.conf` of `run_user` (`chmod 600`) holds the remotes and their credentials |
| rclone install | via the script from rclone.org (`deploy.sh` offers to install it) |

## Installation

```bash
git clone https://github.com/AstEfTech/rclone-sync.git
cd rclone-sync
cp config.example.yml config.yml
$EDITOR config.yml    # the common block and the blocks of the providers you use
./deploy.sh           # as run_user, not via sudo: all providers that have a block
./deploy.sh <name>    # or just one, e.g. ./deploy.sh onedrive
```

After editing `config.yml`, run `./deploy.sh` again: it redeploys every provider that has a block under `providers` (skips the others, reports failures at the end). Without arguments on a terminal it offers a list.

`config.yml` is required and is not tracked by git. It holds no secrets: credentials stay in the `rclone.conf` of `run_user`. Redeploying is safe: it takes the same lock as the sync, so it refuses to run while a sync of that provider is in progress.

## Configuration

One `config.yml` in the repository root serves all providers. The `common` block holds the defaults (`run_user`, `app_dir`, optional `mount_point`, `min_free_gb`, `keep_log_days`, `schedule`, `mode`); a block under `providers.<name>` can override any of them for that provider and holds its folder pairs. Each provider is deployed from `common` and its own block only, so the blocks of providers you do not use can stay as they are. The full list of keys with comments is in [config.example.yml](config.example.yml).

```yaml
common:
  run_user: rclone_user
  app_dir: /home/rclone_user
  mount_point: /mnt/storage        # optional: separate disk, every dst must be inside it
  schedule: "*:0/15"               # optional: systemd OnCalendar, default every 15 minutes

providers:
  gdrive:
    pairs:
      media:
        src: gdrive:Media
        dst: /mnt/storage/gdrive/media
  s3:
    schedule: "hourly"             # override for this provider only
    pairs:
      backups:
        src: s3:my-bucket/backups
        dst: /mnt/storage/s3/backups
        mode: twoway
```

`deploy.sh` checks the config before installing anything: required keys, valid `mode`, `src` in the `<remote>:<path>` form, every `dst` inside `mount_point` (if set), a valid `schedule`, the rclone remote of every `src` configured for `run_user`, and no two pairs (of one provider or of different ones) sharing a `dst` or nesting one inside another. A failing provider does not stop the others.

The file is read by a small built-in parser, so no `yq` is needed. Supported subset: nested mappings indented with 2 spaces and `key: value` scalars (quotes and `# comments` are fine; lists and multi-line values are not, which is why pairs are named blocks).

## Folder pairs and sync types

Each provider syncs any number of folder pairs. A pair is a named block under `providers.<name>.pairs` with a source (`src`), a destination (`dst`) and an optional `mode`. Pair names may use letters, digits, `-` and `_`.

| `mode` | Safe | rclone command | Effect |
|---|---|---|---|
| `copy` (default) | ✅ safe: never deletes, only adds and updates files in `dst` | `rclone copy` | New and changed files are copied; nothing is ever deleted |
| `copyto` | ✅ safe: never deletes, only adds and updates the target | `rclone copyto` | Like `copy`, but `src` and `dst` may be single files (`dst` is then the target file name) |
| `twoway` | ✅ safe: both directions are plain copies, nothing is deleted | `rclone copy` both ways, with `--update` | A file added to `src` goes to `dst` and a file added to `dst` goes to `src`; nothing is deleted. If both sides have the file, the newer one (by modification time) wins. A file deleted on one side comes back from the other. Needs a remote you can write to |
| `bisync` | ⚠️ not safe: a deletion on either side is replicated to the other | `rclone bisync` | Real two-way sync: changes **and deletions** propagate both ways. The first run uses `--resync` (merges both sides, deletes nothing); its state is marked by `.bisync-<pair>` in the install directory. Needs rclone 1.58+; if bisync reports an error, a manual `--resync` may be needed |
| `move` | ⚠️ not safe: removes the files from `src` after transfer | `rclone move` | Files are copied, then **deleted from `src`** (the source gets emptied) |
| `moveto` | ⚠️ not safe: removes the files from `src` after transfer | `rclone moveto` | Like `move`, but `src` and `dst` may be single files; **deletes from `src`** |
| `sync` | ⚠️ not safe: deletes from `dst` what is missing in `src` | `rclone sync` | `dst` becomes an exact mirror of `src`: files missing in `src` are **deleted** from `dst` |

**Safe** = the mode never deletes anything (`copy`, `copyto`, `twoway`). Safe modes can still overwrite a file that changed, but no file disappears. The reason is given in the Safe column of each row.

`mode` is resolved per pair: the pair's own value, else the provider block, else `common`, else `copy`. Pairs of one provider run one after another within a single timer run and share its schedule, lock and log. Use the modes that delete only when you are sure (`rclone sync --dry-run` is a good first check by hand). Modes that write to or delete from the cloud side (`twoway`, `bisync`, `move`, `moveto`, and `sync` with the cloud as `dst`) need a remote you can write to, so they do not fit read-only sources such as Google Photos or iCloud Photos; on object storages mind that deleted and overwritten objects may still be billed.

## Layout

```
config.example.yml               # template of the shared settings (copy to config.yml)
deploy.sh                        # deploys one provider or all that have a block in config.yml
undeploy.sh                      # asks which provider to remove, removes its units and installed directory
common/                          # shared by all providers
├── config.sh                    # minimal config.yml reader (no yq needed)
├── pull.sh                      # main script, installed as <NAME>-pull.sh
├── watch-log.sh                 # tail -f of the latest log
├── pull.service.in              # unit template: oneshot, Nice=10, IOSchedulingClass=idle
└── pull.timer.in                # OnCalendar=@SCHEDULE@ (default *:0/15), Persistent=true, RandomizedDelaySec=30
<provider>/                      # one folder per provider
├── provider.conf                # provider differences: name, rclone options, minimum rclone version
└── CONNECTION_README.md         # getting credentials and configuring the rclone remote
```

Providers: `gdrive`, `gphotos`, `icloud`, `onedrive`, `dropbox`, `box`, `s3`, `b2`, `gcs`, `azureblob`, `wasabi`. Connection guides: [gdrive](gdrive/CONNECTION_README.md), [gphotos](gphotos/CONNECTION_README.md), [icloud](icloud/CONNECTION_README.md), [onedrive](onedrive/CONNECTION_README.md), [dropbox](dropbox/CONNECTION_README.md), [box](box/CONNECTION_README.md), [s3](s3/CONNECTION_README.md), [b2](b2/CONNECTION_README.md), [gcs](gcs/CONNECTION_README.md), [azureblob](azureblob/CONNECTION_README.md), [wasabi](wasabi/CONNECTION_README.md).

Layout on the server (`app_dir` from `config.yml`; each provider gets its own `$APP_DIR/<NAME>-pull/`, `<NAME>` is the provider name):

| File | Path |
|---|---|
| Script | `$APP_DIR/<NAME>-pull/<NAME>-pull.sh` |
| Provider options | `$APP_DIR/<NAME>-pull/provider.conf` |
| Logs | `$APP_DIR/<NAME>-pull/log/YYYY-MM-DD_HH-MM-SS.log` (one per run, deleted after `keep_log_days`, default 14) |
| Lock | `$APP_DIR/<NAME>-pull/.lock` |
| Settings | `$APP_DIR/<NAME>-pull/.env` (generated by `deploy.sh` from `config.yml`: `MOUNT_POINT`, the `PAIR_NAMES/SRC/DST/MODE` arrays, optionally `MIN_FREE_GB`, `KEEP_LOG_DAYS`; chmod 600) |
| Units | `/etc/systemd/system/<NAME>-pull.{service,timer}` |

## Script logic

What `deploy.sh` does per provider: checks the config and rclone (offers to install it, checks the minimum version from `provider.conf`), copies the script and settings to `$APP_DIR/<NAME>-pull/`, generates `.env`, renders the unit templates, runs `daemon-reload` and restarts the timer.

What the installed script does on each run:

1. `flock -n` on `.lock`: if the previous run is still going, exit with code 0.
2. If `mount_point` is set, check `mountpoint $MOUNT_POINT`.
3. For each pair in turn (a failed pair does not stop the others; the exit code is that of the last failure): check at least `min_free_gb` GB of free space (default 5; on the mount, or on the destination's filesystem when `mount_point` is not set), then run `rclone <mode> <src> <dst>` with the provider's options from `provider.conf` (`RCLONE_ARGS`) plus `--stats 30s --stats-file-name-length 0`. The log is written via `--log-file` into `log/`.
4. `LOG_LEVEL=INFO` by default, overridable via an environment variable (`LOG_LEVEL=DEBUG` for debugging).
5. A non-zero rclone exit code is logged and returned to the caller (the unit is marked as failed). For providers with expiring logins (`RECONNECT_ON_ERROR=1` in `provider.conf`) the log also hints to run `rclone config reconnect <remote>:`.

Provider options differ in `provider.conf` (parallelism, provider-specific flags such as `--drive-skip-gdocs` for Google Drive, minimum rclone version, e.g. 1.69 for iCloud).

## Operation

`<NAME>` is the provider name (`gdrive`, `onedrive`, `s3`, ...).

```bash
# enable the timer (deploy.sh already does it)
sudo systemctl enable --now <NAME>-pull.timer

# manual run (does not block the terminal)
sudo systemctl start --no-block <NAME>-pull.service

# status and journal
systemctl list-timers | grep <NAME>
journalctl -u <NAME>-pull -f

# latest run log
$APP_DIR/<NAME>-pull/watch-log.sh

# after editing unit files (better to edit the template and rerun deploy.sh)
sudo systemctl daemon-reload
```

## Behavior

- **Overlapping runs.** systemd does not start a second instance of a oneshot unit, and `flock` guards against manual runs. Missed triggers do not pile up.
- **Interruption.** An interrupted file is downloaded again (rclone writes to a temporary `.partial`); completed files are skipped.
- **Independent providers.** Each provider has its own timer, lock and logs; they may run at the same time, which is why destinations must not overlap.

## Removal

```bash
./undeploy.sh              # as run_user: pick the provider from the list, then confirm
./undeploy.sh <name> -y    # provider named explicitly; -y skips the confirmation
```

Stops and removes `<NAME>-pull.timer` / `.service` and deletes `$APP_DIR/<NAME>-pull/` (script, settings, logs). Files already copied to the destinations, the rclone remote and `config.yml` are kept. If a sync is running, it is stopped; a run started by hand blocks the removal until it finishes.

## Adding a provider

A new provider is a new folder `<name>/` with `provider.conf` (`NAME`, `DESCRIPTION`, `MIN_RCLONE_VERSION`, `RCLONE_ARGS`, `RECONNECT_ON_ERROR`; see any existing one) and a `CONNECTION_README.md`, plus its block under `providers` in `config.example.yml`. `deploy.sh` and `undeploy.sh` find providers by `*/provider.conf`; nothing else needs changing. Any backend that rclone supports works this way.

## Troubleshooting

Authentication and provider-specific problems are listed at the end of each `<name>/CONNECTION_README.md`. General ones:

| Symptom | Cause / solution |
|---|---|
| `Run as user <run_user> (not via sudo)` | `deploy.sh`, `undeploy.sh` and the manual run must be done as `run_user`; sudo is invoked internally |
| `rclone remote '<name>:' not found` | The remote was configured under another user: configure it in the `rclone.conf` of `run_user` |
| `<name>-pull is running ... rerun deploy.sh later` | A sync of that provider is in progress; deploy again when it finishes |
| `... overlaps ...: use separate directories` | Two pairs share a `dst` or one is inside another: give each pair its own directory |
| `permission denied` on `mkdir` | Every `dst` must be owned by `run_user`; for NTFS/exFAT set `uid`/`gid` in fstab |
| `permission denied` on the lock file | Always run as `run_user`, not via `sudo` |
| `bash\r: No such file` / `$'\r': command not found` | The root scripts arrived with CRLF: `sed -i 's/\r$//' *.sh common/*.sh` once in the repository root (during installation `deploy.sh` strips CR from `config.yml`, `provider.conf` and the installed files itself) |
| `systemctl start` blocks the terminal (oneshot) | Use `--no-block` or rely on the timer |

## Possible improvements

- Failure notifications.
- `--fast-list` for large trees on object storages.
