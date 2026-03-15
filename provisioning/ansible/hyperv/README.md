# Hyper-V Provisioning (Ansible)

This directory contains Hyper-V provisioning automation and keeps machine lifecycle outside `configuration/`.

## Scope
- Prepare Hyper-V host for remote automation (WinRM, service account, permissions, firewall)
- Create/update/remove Hyper-V VMs
- Manage VM state (`Running`, `Off`, or `absent` with safety guard)

## Layout
- `playbooks/host_prep.yml` - prepare Hyper-V host
- `playbooks/vm_lifecycle.yml` - create/update/state/remove VMs
- `playbooks/pipeline.yml` - run host prep and VM lifecycle in order
- `roles/hyperv_host/` - host preparation role
- `roles/hyperv_vm/` - VM lifecycle role
- `inventory/` - sample and production inventory files
- `group_vars/` - variables and Vault secrets

## Prerequisites
1. Install collections:
   ```bash
   cd provisioning/ansible/hyperv
   ansible-galaxy collection install -r collections/requirements.yml
   chmod +x bin/ansible-safe bin/ansible-playbook-safe
   ```
2. Create inventory from sample:
   - copy `inventory/sample.ini` to `inventory/production.ini`
3. Create secrets from sample:
   - copy `group_vars/hyperv_hosts/secrets.example.yml` to `group_vars/hyperv_hosts/secrets.yml`
   - set `ansible_password` (WinRM connection password)
   - set `hyperv_host_service_user_password` (password for local service account; preferred)
   - encrypt with Ansible Vault

## Usage
Always validate syntax first:

```bash
cd provisioning/ansible/hyperv
./bin/ansible-playbook-safe --syntax-check playbooks/host_prep.yml
./bin/ansible-playbook-safe --syntax-check playbooks/vm_lifecycle.yml
```

Prepare host:

```bash
cd provisioning/ansible/hyperv
./bin/ansible-playbook-safe playbooks/host_prep.yml
```

Create/update VMs:

```bash
cd provisioning/ansible/hyperv
./bin/ansible-playbook-safe playbooks/vm_lifecycle.yml
```

Run end-to-end:

```bash
cd provisioning/ansible/hyperv
./bin/ansible-playbook-safe playbooks/pipeline.yml
```

WinRM connectivity check:

```bash
cd provisioning/ansible/hyperv
./bin/ansible-safe hyperv_hosts -m ansible.windows.win_ping --vault-password-file ~/.ansible/vault_pass.txt
```

## macOS stability note
On macOS, Homebrew Ansible can crash worker processes during WinRM execution due to Objective-C fork safety.
The wrappers in `bin/` automatically set `OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES` on macOS only.

## Safety
- VM destroy requires both:
  - VM entry with `state: absent`
   - `hyperv_vm_allow_destroy: true`
- Keep secrets only in Vault-encrypted files.
