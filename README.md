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

## Daily systemd schedule

The files in `deploy/` run the backup once per day at **02:00 UTC** on a persistent Linux production server. Install the repository at `/opt/dit-student-companion`, create a restricted `ditbackup` service account, install `config/backup.env` as `/etc/dit-student-companion/backup.env`, and ensure the account can write to `/var/backups/dit-student-companion` and read the passphrase file.

As root on the production server:

```sh
install -d -o ditbackup -g ditbackup -m 700 /var/backups/dit-student-companion
install -d -m 700 /etc/dit-student-companion
install -m 600 config/backup.env /etc/dit-student-companion/backup.env
install -m 644 deploy/dit-student-companion-backup.service /etc/systemd/system/
install -m 644 deploy/dit-student-companion-backup.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now dit-student-companion-backup.timer
systemctl list-timers dit-student-companion-backup.timer
```

Run a one-time test after securely configuring the environment:

```sh
systemctl start dit-student-companion-backup.service
journalctl -u dit-student-companion-backup.service --since today --no-pager
```

Do not put database credentials, passphrases, or backup files in Git. The sandbox used to prepare this repository is not a persistent production scheduler.

## GitHub Actions alternative

`/.github/workflows/database-backup.yml` provides an alternative to the systemd timer. It runs daily at **02:00 UTC** and can also be started manually from the GitHub Actions tab. Do not enable both schedulers unless you intentionally want two backups per day.

Before using it, add these **Actions secrets** in the repository settings:

- `DATABASE_URL`: the production PostgreSQL connection URL
- `BACKUP_ENCRYPTION_PASSPHRASE`: the passphrase used to encrypt backups

The workflow installs `pg_dump` and GnuPG, creates and verifies the encrypted backup, and uploads only the encrypted dump and checksum as a GitHub artifact with 30-day retention. GitHub Actions artifacts are not a complete off-site disaster-recovery strategy; for critical production data, copy encrypted artifacts to durable object storage with an independent retention policy. Never place either secret in workflow files or commit them to Git.
