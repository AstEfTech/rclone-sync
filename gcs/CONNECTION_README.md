# Connecting rclone to Google Cloud Storage (GCS)

Instructions for a headless local server. No browser step: rclone authenticates with a **service account** JSON key. This is the object storage service of Google Cloud; for Google Drive use [../gdrive/CONNECTION_README.md](../gdrive/CONNECTION_README.md).

## Requirements

- A Google Cloud project with billing and a bucket.
- rclone on the server. Install via the script from rclone.org, not from `apt`:
  ```bash
  curl https://rclone.org/install.sh | sudo bash
  rclone version
  ```
- A **service account** (IAM & Admin → Service Accounts → Create) with a role on the bucket: *Storage Object Viewer* if the bucket is only a source, *Storage Object User* (read/write/overwrite; `storage.objectUser`) for copying into it, *Storage Object Admin* if modes that delete are used. Then Keys → Add key → Create new key → **JSON** and save the file on the server, readable by `run_user` only:
  ```bash
  chmod 600 ~/gcs-key.json
  ```

## Part 1. Configuring rclone on the server

```bash
rclone config
```

| Question | Answer |
|---|---|
| `n` New remote | `n` |
| name | `gcs` |
| Storage | `google cloud storage` (not `drive`) |
| client_id / client_secret | empty |
| project_number | the project's ID/number (needed only to list or create buckets) |
| service_account_file | path to the JSON key, e.g. `/home/run_user/gcs-key.json` |
| bucket_policy_only | `true` if the bucket uses uniform bucket-level access, otherwise default |
| location, storage_class | defaults |
| Edit advanced config | `n` |
| Use web browser to automatically authenticate | `n` (not used with a service account file) |

## Part 2. Verification

As the user the sync will run as (not root):

```bash
rclone lsd gcs:BUCKET
rclone ls gcs:BUCKET/some/path
chmod 600 ~/.config/rclone/rclone.conf
```

`src` of a pair is `gcs:BUCKET/path`, e.g. `gcs:my-backups/photos`.

## Common errors

| Symptom | Cause and solution |
|---|---|
| `403 ... does not have storage.objects.list access` | The service account lacks a role on the bucket (see Requirements). |
| `403 ... storage.buckets.list` | Listing all buckets needs a project-level role; use `rclone lsd gcs:BUCKET` instead. |
| `conditionNotMet` / ACL errors on upload | The bucket uses uniform access: set `bucket_policy_only = true`. |
| `invalid_grant` / `Invalid JWT` | Wrong key file, or the server clock is far off: check `timedatectl`. |
| `remote not found` | The remote was configured under another user. Configure it as `run_user`. |
