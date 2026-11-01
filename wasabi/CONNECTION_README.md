# Connecting rclone to Wasabi

Instructions for a headless local server. Wasabi is S3 compatible, so rclone uses the `s3` backend with `provider = Wasabi` and an access key pair. Egress is free, but see the billing notes below.

## Requirements

- A Wasabi account and a bucket.
- rclone on the server. Install via the script from rclone.org, not from `apt`:
  ```bash
  curl https://rclone.org/install.sh | sudo bash
  rclone version
  ```
- An **access key** of a dedicated sub-user (Wasabi console: Users → Create User → programmatic access, with a policy limited to the bucket). Copy the access key and secret at creation: the secret is shown once.

## Part 1. Configuring rclone on the server

```bash
rclone config
```

| Question | Answer |
|---|---|
| `n` New remote | `n` |
| name | `wasabi` |
| Storage | `s3` |
| provider | `Wasabi` |
| env_auth | `false` |
| access_key_id / secret_access_key | the sub-user's keys |
| region | the bucket's region, e.g. `eu-central-1` (or empty for `us-east-1`) |
| endpoint | the region endpoint, e.g. `s3.eu-central-1.wasabisys.com` (`s3.wasabisys.com` for us-east-1) |
| location_constraint, acl, storage_class | defaults (empty) |
| Edit advanced config | `n` |

## Part 2. Verification

As the user the sync will run as (not root):

```bash
rclone lsd wasabi:BUCKET
rclone ls wasabi:BUCKET/some/path
chmod 600 ~/.config/rclone/rclone.conf
```

`src` of a pair is `wasabi:BUCKET/path`, e.g. `wasabi:my-backups/photos`.

## Billing notes

- Wasabi bills a minimum of 1 TB of storage per account and keeps deleted or overwritten objects billable for the minimum retention period (90 days for pay-as-you-go), so modes that delete or overwrite often (`sync`, `bisync`, `move`) do not save money.
- Egress is free as long as it stays reasonable relative to stored data (see Wasabi's fair use policy).

## Common errors

| Symptom | Cause and solution |
|---|---|
| `SignatureDoesNotMatch` / `InvalidAccessKeyId` | Wrong keys, or the `endpoint` does not match the bucket's region. |
| `AccessDenied` | The sub-user's policy does not cover the bucket (list on the bucket, get/put on its objects). |
| `NoSuchBucket` / `301` | A typo in the bucket name, or a region/endpoint mismatch. |
| `remote not found` | The remote was configured under another user. Configure it as `run_user`. |
