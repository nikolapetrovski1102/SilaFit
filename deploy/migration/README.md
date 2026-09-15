# Server migration

Run `bash deploy/migrate-server.sh <phase>` from the Mac with SSH access to both servers.

1. `prepare`: install Docker (including the .NET runtime images and SQL Server), nginx and Certbot; copy the deployed release and secrets; load matching application images and pin the existing SQL image by digest.
2. Build any missing tool images on the destination with `cd /opt/silen/deploy && docker compose --profile tools build silen-monthly-review silen-admin-provision`.
3. `copy-db`: disable old scheduled jobs, stop API writers and SQL, copy the complete SQL volume, then start the new SQL/API containers. This phase deliberately refuses to overwrite an existing destination database.
4. Verify `/health/ready` on destination port 5010 and run `migration/verify-database.sql` through sqlcmd on both servers before/after migration. Compare table totals and require `DBCC CHECKDB` to succeed.
5. `activate`: switch the old hostname's API proxy to the new server using verified HTTPS; disable old container auto-start; install the existing scheduled jobs on the new server.
6. Publish A records for `sila.fitness` and `api.sila.fitness` to `46.224.235.167`, with no conflicting AAAA records, then run `tls` to issue HTTPS certificates and enable renewal.

The public website and admin portal use `sila.fitness`; `/api/` remains proxied there for same-origin admin cookies. The API also has a dedicated `api.sila.fitness` virtual host. The existing `silafit.tappit.click` address continues through the old server's compatibility proxy. Its certificate copied to the destination must be renewed/copied again if the old hostname remains in use long term, or move that hostname's DNS and certificate renewal to the destination.

This migration copies the **deployed production release**, not the numerous local uncommitted application changes. All SQL system databases and encryption secrets are retained together with `.env`, TDE backups, service-account files, website and application source. No schema scripts or seed-data reset runs during migration.

## Recovery

Keep `/opt/silen-migration` private: it contains deployment secrets and an encrypted database snapshot. The old SQL volume remains intact. Before activation, a failed migration can be rolled back by stopping both destination containers, starting the old SQL/API, restoring the old cron files from `/opt/silen-migration`, and verifying readiness. **After the destination accepts writes, do not restart the old database**: rollback requires moving the newest database back, otherwise data diverges.

`prepare` is only for a fresh destination; do not rerun it after activation because it copies the old deployment configuration. `copy-db` intentionally has a one-time guard. `activate` and `tls` can be repeated.
