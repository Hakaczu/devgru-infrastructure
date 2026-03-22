# n8n_docker_compose

Ansible role that deploys an N8N workflow automation stack using Docker Compose with PostgreSQL (pgvector) as the database backend.

## Stack

| Container  | Image                      | Purpose                     |
|------------|----------------------------|-----------------------------|
| db         | pgvector/pgvector:pg15     | PostgreSQL with vector ext  |
| n8n        | n8nio/n8n:latest           | N8N workflow engine         |
| watchtower | nickfedor/watchtower       | Automatic image updates     |

## Requirements

- Ansible `geerlingguy.docker` collection (installs Docker)
- `community.general` collection (for cron module)

## Role Variables

| Variable                    | Default             | Description                         |
|-----------------------------|---------------------|-------------------------------------|
| `n8n_port`                  | `5678`              | Host port exposed for N8N UI        |
| `n8n_domain`                | `n8n.example.com`   | Domain used for webhook URLs        |
| `n8n_image`                 | `n8nio/n8n:latest`  | N8N Docker image                    |
| `n8n_db_name`               | `n8n`               | PostgreSQL database name            |
| `n8n_db_user`               | `n8n`               | PostgreSQL user                     |
| `n8n_db_password`           | `n8n`               | PostgreSQL password (override!)     |
| `n8n_data_dir`              | `/root/.n8n`        | N8N data persistence directory      |
| `n8n_pg_data_dir`           | `/root/.pg_n8n`     | PostgreSQL data directory           |
| `n8n_compose_dir`           | `/opt/n8n`          | Directory for docker-compose.yml    |
| `n8n_timezone`              | `Europe/Warsaw`     | Container timezone                  |
| `n8n_executions_prune`      | `true`              | Enable execution history pruning    |
| `n8n_executions_prune_max_age` | `336`            | Execution retention (hours)         |
| `n8n_runners_enabled`       | `true`              | Enable N8N task runners             |
| `n8n_watchtower_enabled`    | `true`              | Deploy Watchtower for auto-updates  |
| `n8n_watchtower_interval`   | `259200`            | Watchtower poll interval (seconds)  |
| `n8n_backup_enabled`        | `true`              | Enable automated backups            |
| `n8n_backup_dir`            | `/backup/n8n`       | Backup destination directory        |
| `n8n_backup_retention_days` | `7`                 | Days to keep backups                |
| `n8n_diagnostics_enabled`   | `false`             | Enable N8N diagnostics/telemetry    |

## Example Playbook

```yaml
- name: Deploy N8N via Docker Compose
  hosts: n8n_compose
  roles:
    - n8n_docker_compose
  become: true
```

## Example Inventory

```yaml
n8n_compose:
  vars:
    n8n_domain: n8n.mycompany.com
    n8n_port: "8080"
    n8n_db_password: "supersecret"
  hosts:
    my-server:
      ansible_host: 1.2.3.4
      ansible_user: ansible
```

## Tags

| Tag            | Description                      |
|----------------|----------------------------------|
| `docker`       | Docker installation              |
| `n8n`          | N8N stack deployment             |
| `n8n_backup`   | Backup script and cron setup     |

## Backup

The backup script is deployed to `/usr/local/bin/n8n_backup` and runs daily at 4:XX AM via cron. It performs a `pg_dump` of the N8N database and retains backups for `n8n_backup_retention_days` days.

Manual backup run:
```bash
bash /usr/local/bin/n8n_backup RUN
```
