# db_stack runbook (Postgres 16 + PgBouncer + backups)

This stack deploys:

- PostgreSQL 16 (internal-only in Docker Compose network)
- PgBouncer (transaction pooling), exposed only on 127.0.0.1:6432
- Host-side daily backups (pg_dump + gzip) to /srv/backups/postgres with 7-day retention

## Prerequisites

- Ubuntu 22.04 or 24.04
- root/sudo and internet
- Ansible (2.14+)
- Install required Ansible collection:

```bash
ansible-galaxy collection install community.docker
```

## Inventory example

inventory.ini:

```ini
[db]
your-server ansible_user=ubuntu ansible_become=true
```

## Secrets (preferred: ansible-vault)

Create an encrypted vars file (example path: group_vars/db/vault.yml):

```yaml
postgres_password: "CHANGE_ME"
```

Encrypt it:

```bash
ansible-vault encrypt group_vars/db/vault.yml
```

Run your playbook:

```bash
ansible-playbook -i inventory.ini site.yml --ask-vault-pass
```

### Alternative secrets method: environment variable

If you don’t want vault for this exercise, you can set:

```bash
export DB_STACK_POSTGRES_PASSWORD='CHANGE_ME'
ansible-playbook -i inventory.ini site.yml
```

The role will use postgres_password if set; otherwise it will read DB_STACK_POSTGRES_PASSWORD.

## Minimal playbook example

site.yml:

```yaml
- hosts: db
  become: true
  collections:
    - community.docker
  roles:
    - role: db_stack
      vars:
        postgres_db: "app"
        postgres_user: "app"
        # postgres_password should come from vault or env var
```

## Deploy / Update

Run the playbook. It will:

- install Docker + Compose plugin
- render Compose + PgBouncer configs into /srv/db_stack
- deploy the stack
- install a cron job for backups

## Verify

### 1) Check containers + health

```bash
cd /srv/db_stack
docker compose ps
```

You should see postgres and pgbouncer with healthy status.

### 2) Validate exposure rules

- PgBouncer must be reachable only on localhost:

```bash
ss -lntp | grep 6432
# should show: 127.0.0.1:6432
```

- Postgres should not be published on the host:

```bash
ss -lntp | grep 5432 || true
```

### 3) Connect through PgBouncer

Install client if needed:

```bash
sudo apt-get update && sudo apt-get install -y postgresql-client
```

Connect (password is the one you set via vault/env):

```bash
psql "host=127.0.0.1 port=6432 dbname=app user=app"
```

## Backups

### Location

- Backups: /srv/backups/postgres
- Naming: pgdump_YYYY-MM-DD.sql.gz
- Retention: 7 days (configurable)

### Run a backup manually

```bash
sudo /usr/local/bin/pg_backup.sh
ls -lah /srv/backups/postgres
```

### Logs

Cron output goes to:

```bash
sudo tail -n 200 /var/log/pg_backup.log
```

## Restore

### 0) Pick a backup

```bash
ls -1 /srv/backups/postgres/pgdump_*.sql.gz
```

### 1) Stop your application traffic

Stop the services that write to the DB (your app). PgBouncer can stay up, but you should ensure no writes happen during restore.

### 2) Restore into the database

Example:

```bash
backup="/srv/backups/postgres/pgdump_2026-02-06.sql.gz"

cd /srv/db_stack
gunzip -c "${backup}" | docker compose exec -T postgres psql -U app -d app
```

If you want a clean restore, drop/recreate schema beforehand (be careful in production).

## Troubleshooting

- If the Postgres data dir already existed with a different init auth setup, you may need to reinitialize the volume (wipe /srv/db_stack/data/postgres) or adjust authentication settings.
- View logs:

```bash
cd /srv/db_stack
docker compose logs -n 200 --no-log-prefix postgres
docker compose logs -n 200 --no-log-prefix pgbouncer
```
