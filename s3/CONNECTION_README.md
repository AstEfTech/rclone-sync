# Connecting rclone to Amazon S3 (and S3-compatible storage)

Instructions for a headless local server. No browser step: rclone uses an access key pair. The same `s3` backend also serves MinIO, Ceph, Cloudflare R2, DigitalOcean Spaces and other S3-compatible services (for Wasabi there is a ready guide: [../wasabi/CONNECTION_README.md](../wasabi/CONNECTION_README.md)).

## Requirements

- An AWS account and a bucket.
- rclone on the server. Install via the script from rclone.org, not from `apt`:
  ```bash
  curl https://rclone.org/install.sh | sudo bash
  rclone version
  ```
- A dedicated **IAM user** with an access key and the minimum permissions for the bucket (replace `BUCKET`):
  ```json
  {
    "Version": "2012-10-17",
    "Statement": [
      {"Effect": "Allow", "Action": ["s3:ListBucket", "s3:GetBucketLocation"], "Resource": "arn:aws:s3:::BUCKET"},
      {"Effect": "Allow", "Action": ["s3:GetObject", "s3:PutObject"], "Resource": "arn:aws:s3:::BUCKET/*"}
    ]
  }
  ```
  Add `s3:DeleteObject` only for modes that delete in the bucket (`sync`/`bisync` with the bucket as `dst`, or `move`/`moveto` with the bucket as `src`). Never use the root account keys.

## Part 1. Configuring rclone on the server

```bash
rclone config
```

| Question | Answer |
|---|---|
| `n` New remote | `n` |
| name | `s3` |
| Storage | `s3` |
| provider | `AWS` (or the name of your S3-compatible service) |
| env_auth | `false` |
| access_key_id / secret_access_key | the IAM user's keys |
| region | the bucket's region, e.g. `eu-central-1` |
| endpoint | empty for AWS; for compatible services the service URL |
| location_constraint, acl, storage_class | defaults (empty) |
| Edit advanced config | `n` |

For an EC2 server with an instance role, choose `env_auth = true` and leave the keys empty.

## Part 2. Verification

As the user the sync will run as (not root):

```bash
rclone lsd s3:BUCKET            # or `rclone lsd s3:` if the user may list all buckets
rclone ls s3:BUCKET/some/path
chmod 600 ~/.config/rclone/rclone.conf
```

`src` of a pair is `s3:BUCKET/path`, e.g. `s3:my-backups/photos`.

## Common errors

| Symptom | Cause and solution |
|---|---|
| `AccessDenied` on listing | The policy lacks `s3:ListBucket` on the bucket (not on `BUCKET/*`). |
| `AccessDenied` on `lsd s3:` | The user may not list all buckets: use `rclone lsd s3:BUCKET`. |
| `SignatureDoesNotMatch` / `InvalidAccessKeyId` | Wrong or mistyped keys, or a wrong `endpoint`/`region`. |
| `301 PermanentRedirect` | The region does not match the bucket's region. |
| `NoSuchBucket` | A typo, or the bucket is in another account. `rclone copy` does not create buckets without `bucket_acl` rights. |
| `remote not found` | The remote was configured under another user. Configure it as `run_user`. |
