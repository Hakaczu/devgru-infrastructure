devgru-infrastructure orchestrates the Hybrid Cloud deployment that spans three VPS hosts and the local Proxmox homelab. Terragrunt wrappers, reusable Terraform modules, and Ansible configuration live in one monorepo so provisioning, configuration, and auditing all share the same history.

## Repository layout
- [provisioning](provisioning/)
  - [modules](provisioning/modules/) – DRY Terraform building blocks for networking, compute, and storage. Each module should document inputs and outputs, expose reusable contracts, and stay agnostic of live stacks.
  - [live](provisioning/live/)
    - [cloud](provisioning/live/cloud/) – Terragrunt roots for the public VPS fleet (Cloudflare/Tailscale). Only terragrunt.hcl files live here so all Terraform logic stays under modules.
    - [onprem](provisioning/live/onprem/) – Terragrunt roots wired to the Proxmox homelab. Prefix parent Terragrunt blocks with shared backend "gcs" configuration so every environment writes state to the same GCS bucket.
- [configuration](configuration/)
  - [inventory](configuration/inventory/) – Sample inventory, production copy (gitignored), and vault password helpers.
  - [group_vars](configuration/group_vars/) – Environment-specific overrides for the controllers that target cloud vs homelab groups.
  - [roles](configuration/roles/) – The [base](configuration/roles/base/) role templates `/etc/motd` and scaffolds `/opt/devgru/dotfiles` so every node starts with the same hygiene.
- [.github](.github/) – CI workflows for linting, validating Terragrunt plans, and gatekeeping releases.
- secrets/ (ignored) – Vault-encrypted data referenced by Ansible plays.

## Getting started
1. Authenticate with Google Cloud, export `GOOGLE_APPLICATION_CREDENTIALS`, and ensure Terragrunt has permission to read and write the shared GCS backend bucket.
2. Use [configuration/inventory/sample.ini](configuration/inventory/sample.ini) as the basis for your inventory, then copy it to [configuration/inventory/production.ini](configuration/inventory/production.ini) once you have real hostnames.
3. Store sensitive variables in [configuration/inventory/secrets.yml](configuration/inventory/secrets.yml) protected by Ansible Vault so passwords, tokens, and private keys never land in plain text.

## Terragrunt workflow
Terragrunt roots live under [provisioning/live](provisioning/live/), so pick the stack you want to inspect before running the command.

```bash
cd provisioning/live/cloud
terragrunt plan
```

Switch to [provisioning/live/onprem](provisioning/live/onprem/) to preview the homelab configuration. Always read the plan output before running `terragrunt apply` to catch drift across GCP, Cloudflare, and Tailscale.

## Ansible workflow
Target your hosts with the inventory in [configuration/inventory](configuration/inventory/) so production hostnames, IPs, and credentials stay outside source control.

```bash
ansible-playbook -i configuration/inventory/production.ini site.yml --vault-password-file configuration/inventory/secrets.yml
```

Drop shared variables into [configuration/group_vars](configuration/group_vars/) so the cloud and on-prem groups receive the right TLS, NTP, and logging settings. The [roles/base](configuration/roles/base/) role demonstrates how to stay idempotent while templating `/etc/motd` and creating directories under `/opt/devgru`.

## Next steps
- Fill [provisioning/modules](provisioning/modules/) with tested Terraform code and keep each module README up to date so other teams know exactly which inputs and outputs exist.
- Flesh out each terragrunt.hcl file under [provisioning/live](provisioning/live/) with the correct inputs and remote state references before running plans.
- Use [configuration/group_vars](configuration/group_vars/) and vault-protected secrets to separate cloud versus on-prem tweaks while letting the same playbook run everywhere.
