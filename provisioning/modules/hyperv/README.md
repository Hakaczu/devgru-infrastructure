# Hyper-V PowerShell Executors

This directory contains reusable PowerShell executors for Hyper-V provisioning.

## Scope
- `Library.ps1` - shared helper functions for result reporting and disk path normalization
- `switch/Ensure-HyperVSwitch.ps1` - idempotent switch executor
- `vm/Ensure-HyperVVm.ps1` - idempotent VM lifecycle executor

## Execution Model
- Source of truth stays in this repository.
- Ansible copies this directory to the Hyper-V host on each run.
- The Hyper-V Ansible role only merges YAML definitions, validates them, and invokes these executors.

## Contract
- Switch definition fragments must be merged into objects with `name`, `type`, optional `adapter_name`, and optional `notes`.
- VM definition fragments must be merged into objects with `host`, `vm_name`, `generation`, `memory`, `processors`, `network_switch_name`, `disks`, optional `iso_path`, and `state`.
- VM removal still requires both `state: absent` and `hyperv_vm_allow_destroy: true`.

## Validation
Before applying changes, validate playbooks from `provisioning/ansible/hyperv`:

```bash
./bin/ansible-playbook-safe --syntax-check playbooks/vm_lifecycle.yml
./bin/ansible-playbook-safe --syntax-check playbooks/pipeline.yml
```