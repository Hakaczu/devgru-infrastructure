# Base role

Minimal shared role to keep base nodes consistent.

## Responsibilities
- Deploy a consistent message-of-the-day template.
- Ensure `/opt/devgru/dotfiles` exists for future automation hooks.
- Keep the role safe to re-run by only managing idempotent resources.

## Usage
Include the role from a playbook with:

```yaml
- hosts: all
  roles:
    - role: base
```

Credentials and network specifics belong in `production.ini`, `secrets.yml`, or your vault-managed variables.
