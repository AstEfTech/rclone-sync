# Connecting rclone to Microsoft Azure Blob Storage

Instructions for a headless local server. No browser step: rclone uses a storage account key or a SAS URL.

## Requirements

- An Azure storage account and a container.
- rclone on the server. Install via the script from rclone.org, not from `apt`:
  ```bash
  curl https://rclone.org/install.sh | sudo bash
  rclone version
  ```
- One of the credentials (the first one is the least privileged):
  - a **SAS URL** for the container (Storage account → Containers → the container → Shared access tokens; permissions Read, List for a source, plus Add, Create, Write for a destination, plus Delete only for modes that delete) and a sensible expiry date;
  - the storage account **name and key** (Access keys): full access to the whole account.

## Part 1. Configuring rclone on the server

```bash
rclone config
```

| Question | Answer |
|---|---|
| `n` New remote | `n` |
| name | `azureblob` |
| Storage | `azureblob` |
| account | the storage account name (empty with a SAS URL) |
| key | the account key (empty with a SAS URL) |
| sas_url | the container SAS URL (empty with the account key) |
| Edit advanced config | `n` |

## Part 2. Verification

As the user the sync will run as (not root):

```bash
rclone lsd azureblob:             # with an account key
rclone ls azureblob:CONTAINER/some/path
chmod 600 ~/.config/rclone/rclone.conf
```

With a container-level SAS URL use paths without the container name: `rclone ls azureblob:some/path`. `src` of a pair is `azureblob:CONTAINER/path` with an account key.

## Notes

- A SAS URL expires on its date; renew it with `rclone config update azureblob sas_url=NEW_URL`.
- The Archive access tier cannot be read directly: rehydrate those blobs first.

## Common errors

| Symptom | Cause and solution |
|---|---|
| `AuthenticationFailed` | Wrong key, or the SAS token expired or has a clock/start-time problem. |
| `AuthorizationPermissionMismatch` / `403` | The SAS or role lacks the permission needed (list, read, write, delete). |
| `ContainerNotFound` | A typo in the container name, or the SAS is scoped to another container. |
| `remote not found` | The remote was configured under another user. Configure it as `run_user`. |
