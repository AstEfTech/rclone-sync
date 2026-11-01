# Connecting rclone to Backblaze B2

Instructions for a headless local server. No browser step: rclone uses an application key.

## Requirements

- A Backblaze account and a bucket.
- rclone on the server. Install via the script from rclone.org, not from `apt`:
  ```bash
  curl https://rclone.org/install.sh | sudo bash
  rclone version
  ```
- An **Application Key** (Backblaze: App Keys → Add a New Application Key). Restrict it to the one bucket and give it Read and Write (Read only if the bucket is only a source). Copy the **keyID** and the **applicationKey** at creation: the key is shown once. Do not use the master application key.

## Part 1. Configuring rclone on the server

```bash
rclone config
```

| Question | Answer |
|---|---|
| `n` New remote | `n` |
| name | `b2` |
| Storage | `b2` |
| account | the **keyID** (or the account ID when using the master key) |
| key | the **applicationKey** |
| hard_delete | `false` |
| Edit advanced config | `n` |

## Part 2. Verification

As the user the sync will run as (not root):

```bash
rclone lsd b2:
rclone ls b2:BUCKET/some/path
chmod 600 ~/.config/rclone/rclone.conf
```

A key restricted to one bucket cannot list all buckets: use `rclone lsd b2:BUCKET` instead. `src` of a pair is `b2:BUCKET/path`.

## Notes

- Deleting or overwriting a file in B2 keeps the old version as a hidden version (billed until a bucket lifecycle rule removes it). With `hard_delete = true` rclone removes the file permanently.
- Downloads are free up to three times the stored data per month, then charged: avoid pointless full rereads (a `copy` run only lists, it does not download unchanged files).

## Common errors

| Symptom | Cause and solution |
|---|---|
| `401 unauthorized` / `bad_auth_token` | Wrong keyID/key, or the key was deleted. Create a new application key. |
| `Bucket not found` or `unauthorized` on a bucket | The key is restricted to another bucket, or lacks the needed capability. |
| `cap_exceeded` | The daily caps of the Backblaze account are reached: raise them in Caps & Alerts. |
| `remote not found` | The remote was configured under another user. Configure it as `run_user`. |
