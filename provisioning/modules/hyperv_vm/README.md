# Terraform Module: Hyper-V VM (`hyperv_vm`)

Module for creating reproducible virtual instances on a local Hyper-V server, in accordance with the `devgru-infrastructure` project guidelines.

## Requirements
- Configured Hyper-V host with an appropriate Virtual Switch.
- Prepared disk (e.g. cloned from a base VHDX) - the `taliesins/hyperv` provider can create empty disks, but for hybrid cloud it is more convenient to prepare the base disk yourself through other mechanisms (e.g. Packer) and attach it via `vhd_path`.

## Usage via Terragrunt
In the `live/onprem/hyperv-vm/terragrunt.hcl` file:
```hcl
terraform {
  source = "../../../../modules/hyperv_vm"
}

include "root" {
  path = find_in_parent_folders()
}

inputs = {
  vm_name             = "test-vm-1"
  memory              = 2048
  processors          = 2
  
  # Virtual Switch setup
  create_switch       = true
  network_switch_name = "DevGru-Switch"
  switch_type         = "Internal"
  
  # Disk configuration
  vhd_path            = "C:\\Hyper-V\\Virtual Hard Disks\\test-vm-1.vhdx"
}
```
