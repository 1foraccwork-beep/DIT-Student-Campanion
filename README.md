# DIT Student Companion database backup

This repository contains the encrypted PostgreSQL production database backup runner.

## Prerequisites

Install PostgreSQL client tools (`pg_dump`) and GnuPG (`gpg`) on the backup host. The backup host must have network access to the production database and a secret-manager-provided `DATABASE_URL`.

Create a protected passphrase file outside the repository and set its permissions to `600`:

```sh
sudo install -d -m 700 /etc/dit-student-companion
sudo install -m 600 /dev/null /etc/dit-student-companion/backup-passphrase
# Populate the file through your approved secret-management process.
```

Copy `config/backup.env.example` to `config/backup.env`, replace the placeholders through your deployment process, and run:

```sh
chmod 600 config/backup.env
pnpm backup:database
```

The script creates an AES-256 GPG-encrypted PostgreSQL custom-format dump, verifies that it can be decrypted, writes a SHA-256 checksum, and removes artifacts older than `BACKUP_RETENTION_DAYS`. It never prints the database URL or passphrase.

For production, set `BACKUP_DIR` to durable storage with restricted access and arrange an off-host replication/retention policy. Test restoration periodically with `pg_restore` in an isolated environment.
