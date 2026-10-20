#!/usr/bin/env bash
set -Eeuo pipefail

# Encrypted PostgreSQL backup. Secrets are supplied through environment variables
# or a permissions-restricted passphrase file; never commit them to the repository.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="${BACKUP_CONFIG_FILE:-$REPO_DIR/config/backup.env}"

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a
  source "$CONFIG_FILE"
  set +a
fi

: "${DATABASE_URL:?DATABASE_URL must be set (use a secret manager or protected environment file)}"
: "${BACKUP_ENCRYPTION_PASSPHRASE_FILE:?BACKUP_ENCRYPTION_PASSPHRASE_FILE must point to a protected passphrase file}"

BACKUP_DIR="${BACKUP_DIR:-$REPO_DIR/backups}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"
BACKUP_PREFIX="${BACKUP_PREFIX:-dit-student-companion}"

if ! command -v pg_dump >/dev/null 2>&1; then
  echo "ERROR: pg_dump is required but was not found" >&2
  exit 127
fi
if ! command -v gpg >/dev/null 2>&1; then
  echo "ERROR: gpg is required but was not found" >&2
  exit 127
fi

if [[ ! -f "$BACKUP_ENCRYPTION_PASSPHRASE_FILE" ]]; then
  echo "ERROR: encryption passphrase file does not exist" >&2
  exit 1
fi
if [[ "$(stat -c '%a' "$BACKUP_ENCRYPTION_PASSPHRASE_FILE" 2>/dev/null || echo 999)" != "600" ]]; then
  echo "ERROR: encryption passphrase file must have mode 600" >&2
  exit 1
fi

mkdir -p -- "$BACKUP_DIR"
chmod 700 -- "$BACKUP_DIR"

umask 077
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
base_name="${BACKUP_PREFIX}-${timestamp}"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/dit-backup.XXXXXX")"
dump_file="$tmp_dir/${base_name}.dump"
encrypted_file="$BACKUP_DIR/${base_name}.dump.gpg"
checksum_file="${encrypted_file}.sha256"

cleanup() {
  rm -rf -- "$tmp_dir"
}
trap cleanup EXIT

# Custom format is compressed by pg_dump and can be restored with pg_restore.
pg_dump --format=custom --no-owner --no-privileges --file="$dump_file" "$DATABASE_URL"

# GPG provides authenticated encryption and reads the passphrase from a file,
# avoiding exposure in process arguments or command logs.
gpg --batch --yes --quiet --pinentry-mode loopback \
  --passphrase-file "$BACKUP_ENCRYPTION_PASSPHRASE_FILE" \
  --symmetric --cipher-algo AES256 --output "$encrypted_file" "$dump_file"

# Verify that the encrypted artifact can be decrypted before publishing its checksum.
gpg --batch --quiet --pinentry-mode loopback \
  --passphrase-file "$BACKUP_ENCRYPTION_PASSPHRASE_FILE" \
  --decrypt "$encrypted_file" > /dev/null

sha256sum -- "$encrypted_file" > "$checksum_file"
find "$BACKUP_DIR" -maxdepth 1 -type f -name "${BACKUP_PREFIX}-*.dump.gpg" \
  -mtime "+$BACKUP_RETENTION_DAYS" -delete
find "$BACKUP_DIR" -maxdepth 1 -type f -name "${BACKUP_PREFIX}-*.dump.gpg.sha256" \
  -mtime "+$BACKUP_RETENTION_DAYS" -delete

printf 'Encrypted backup succeeded: %s\n' "$(basename -- "$encrypted_file")"
