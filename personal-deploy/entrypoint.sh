#!/bin/sh
set -e

DB_PATH="${WF_DB_PATH:-/data/wealthfolio.db}"
DB_DIR=$(dirname "$DB_PATH")

# Ensure the data directory exists (ephemeral filesystem on Render free tier)
mkdir -p "$DB_DIR"

# Restore the database from the replica if it doesn't exist locally.
# On Render free tier, the filesystem is ephemeral — every cold start needs this.
if [ ! -f "$DB_PATH" ]; then
  echo "[entrypoint] No local database found. Attempting restore from replica..."
  litestream restore -if-replica-exists -config /etc/litestream.yml "$DB_PATH"
  if [ -f "$DB_PATH" ]; then
    echo "[entrypoint] Database restored successfully."
  else
    echo "[entrypoint] No replica found. Starting fresh (first run)."
  fi
else
  echo "[entrypoint] Local database exists. Skipping restore."
fi

# Start the server under Litestream's supervision.
# Litestream will continuously replicate WAL changes to your S3 bucket.
# When the process exits, Litestream flushes remaining WAL before shutting down.
exec litestream replicate -exec "/usr/local/bin/wealthfolio-server" -config /etc/litestream.yml
