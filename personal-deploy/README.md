# Personal Deploy — Wealthfolio on Render (Free Tier)

Deploys the official Wealthfolio Docker image to Render's free web service with
**Litestream** for SQLite replication to S3-compatible storage. Your data
survives Render's ephemeral filesystem and cold starts.

## How it works

```
┌─────────────────── Render Free Tier ───────────────────┐
│                                                         │
│  entrypoint.sh                                          │
│    1. Restore SQLite from S3 replica (cold start)       │
│    2. Start wealthfolio-server under Litestream         │
│                                                         │
│  Litestream (sidecar)                                   │
│    • Continuously streams WAL changes to S3             │
│    • Flushes on graceful shutdown                       │
│                                                         │
└────────────────────────┬────────────────────────────────┘
                         │ WAL replication
                         ▼
              ┌─────────────────────┐
              │   Tigris (S3-compat) │
              │   Free: 5GB, no card │
              └─────────────────────┘
```

**Trade-offs:**
- Cold starts take a few extra seconds (restore from S3)
- If Render kills the container without SIGTERM, you may lose the last ~1s of
  writes (the replication interval). For a personal portfolio tracker this is
  negligible.

---

## Prerequisites

- A GitHub account (to push this repo)
- A [Render](https://render.com) account (free, no card required)
- A [Tigris](https://console.storage.dev) account for S3-compatible object
  storage (free tier: 5 GB, zero egress fees, **no credit card required** —
  OAuth signup via GitHub/Google)

---

## Step 1: Set up S3-compatible storage (Tigris)

Tigris is S3-compatible object storage with a free tier (5 GB) and no credit
card required.

### Option A: Using the Tigris CLI (recommended)

1. Install the CLI:
   ```bash
   npm install -g @tigrisdata/cli
   ```

2. Log in (opens browser for OAuth — GitHub/Google):
   ```bash
   tigris login
   ```

3. Create a bucket:
   ```bash
   tigris mk wealthfolio-backup
   ```

4. Create access keys:
   ```bash
   tigris access-keys create wealthfolio-litestream
   ```
   This outputs:
   - **Access Key ID**: `tid_...`
   - **Secret Access Key**: `tsec_...`

5. Note down these values — you'll need them for Render env vars:
   - **Bucket**: `wealthfolio-backup`
   - **Endpoint**: `https://t3.storage.dev`
   - **Access Key ID**: `tid_...`
   - **Secret Access Key**: `tsec_...`

### Option B: Via the web console

1. Go to https://console.storage.dev and sign up (GitHub/Google OAuth)
2. Create a bucket named `wealthfolio-backup`
3. Go to Access Keys and create a new key
4. Note the credentials (same as above)

---

## Step 2: Generate Wealthfolio secrets

On your local machine:

```bash
# 1. Generate a 32-byte secret key for encryption + JWT signing
SECRET=$(openssl rand -base64 32)
echo "WF_SECRET_KEY=$SECRET"

# 2. Generate an Argon2id password hash for login
#    Replace 'your-password' with your actual password
#    Replace 'yoursalt16chars!' with a random 16+ char salt
printf 'your-password' | argon2 yoursalt16chars! -id -e
# Output looks like: $argon2id$v=19$m=19456,t=2,p=1$...
```

If you don't have `argon2` installed:
- macOS: `brew install argon2`
- Debian/Ubuntu: `apt install argon2`

---

## Step 3: Deploy to Render

### Option A: Blueprint (recommended)

1. Push your fork to GitHub (make sure `personal-deploy/` and `render.yaml` at
   the repo root are committed)
2. Go to https://dashboard.render.com
3. Click **New** → **Blueprint**
4. Connect your GitHub repo, select the branch
5. Render auto-detects `render.yaml` at the repo root and creates the service
6. Fill in the environment variables it prompts for (see below)

### Option B: Manual setup

1. Go to https://dashboard.render.com
2. Click **New** → **Web Service**
3. Connect your GitHub repo
4. Configure:
   - **Environment**: Docker
   - **Dockerfile Path**: `./personal-deploy/Dockerfile`
   - **Docker Context**: `./personal-deploy`
   - **Instance Type**: Free
5. Add environment variables (next section)
6. Click **Create Web Service**

### Environment variables to set in Render

| Variable | Value |
|----------|-------|
| `WF_LISTEN_ADDR` | `0.0.0.0:10000` (Render's default expected port for Docker services) |
| `WF_DB_PATH` | `/data/wealthfolio.db` |
| `WF_STATIC_DIR` | `dist` |
| `WF_CORS_ALLOW_ORIGINS` | Your Render URL, e.g. `https://wealthfolio-xxxx.onrender.com` |
| `WF_SECRET_KEY` | The value from Step 2 |
| `WF_AUTH_PASSWORD_HASH` | The argon2 hash from Step 2 |
| `WF_AUTH_TOKEN_TTL_MINUTES` | `480` (or your preference) |
| `LITESTREAM_REPLICA_BUCKET` | Your Tigris bucket name (e.g. `wealthfolio-backup`) |
| `LITESTREAM_REPLICA_ENDPOINT` | `https://t3.storage.dev` |
| `LITESTREAM_ACCESS_KEY_ID` | Your Tigris access key (`tid_...`) |
| `LITESTREAM_SECRET_ACCESS_KEY` | Your Tigris secret key (`tsec_...`) |

**Important:** For `WF_CORS_ALLOW_ORIGINS`, you won't know the exact Render URL
until the service is created. Deploy first, then update this variable with the
assigned `.onrender.com` URL and redeploy.

---

## Step 4: Verify

1. Wait for the build to complete on Render (first build takes a few minutes)
2. Visit your service URL: `https://wealthfolio-xxxx.onrender.com`
3. Log in with the password you hashed in Step 2
4. Add some test data
5. **Test persistence:** Go to Render dashboard → your service → **Manual Deploy** →
   **Clear build cache & deploy**. After the cold start, your data should still
   be there (restored from R2).

---

## Updating Wealthfolio

The Dockerfile pulls `wealthfolio/wealthfolio:latest`. To update:

1. Go to your service in Render dashboard
2. Click **Manual Deploy** → **Deploy latest commit**
3. Render rebuilds, pulling the newest official image

To pin a version, change the `FROM` line in the Dockerfile:
```dockerfile
FROM wealthfolio/wealthfolio:3.3.0
```

---

## Disabling authentication (not recommended)

If you want to skip the login screen (e.g., for quick testing):

Replace `WF_AUTH_PASSWORD_HASH` with:
```
WF_AUTH_REQUIRED=false
```

This disables authentication entirely. **Do not use this in production.**

---

## Troubleshooting

### "No replica found. Starting fresh"
This is expected on the very first deploy — there's nothing to restore yet.
Litestream will start replicating as soon as the server writes to the database.

### Data lost after redeploy
Check Render logs for Litestream errors. Common causes:
- Wrong bucket name or endpoint (should be `https://t3.storage.dev` for Tigris)
- Invalid access keys (should start with `tid_` / `tsec_`)
- Bucket doesn't exist — verify with `tigris ls`

### Cold start takes too long
The restore downloads your entire database from S3. For a personal portfolio
tracker the DB is typically <10 MB, so this should take 1-2 seconds. If your DB
grows large, consider compacting it periodically via the app's built-in backup
feature.

### Container exits immediately
Check `docker logs` or Render logs. Likely causes:
- Missing `WF_SECRET_KEY` (must be exactly 32 bytes base64)
- Malformed `WF_AUTH_PASSWORD_HASH` (regenerate with `printf`, not `echo`)

---

## File overview

```
render.yaml              # Render Blueprint (at repo root for auto-detection)
personal-deploy/
├── Dockerfile           # Wraps official image + adds Litestream
├── entrypoint.sh        # Restore-on-boot + start server under Litestream
├── litestream.yml       # Litestream replication config (uses env vars)
└── README.md            # This file
```
