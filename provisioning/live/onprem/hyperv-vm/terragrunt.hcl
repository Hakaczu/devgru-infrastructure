include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../modules/hyperv_vm"

  # Load variables from secrets.tfvars if it exists
  extra_arguments "secrets" {
    commands = get_terraform_commands_that_need_vars()
    optional_var_files = [
      "${get_terragrunt_dir()}/secrets.tfvars"
    ]
  }
}

# Dynamically generate the provider block for Hyper-V so we don't hardcode credentials in modules
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "hyperv" {
  user        = var.hyperv_user
  password    = var.hyperv_password
  host        = var.hyperv_host
  port        = 5986
  https       = true
  insecure    = true
  use_ntlm    = false
  script_path = "C:/Temp/terraform_%RAND%.cmd"  # C:\Temp is created by prepare-hyperv.ps1 with TerraformUser FullControl
}

variable "hyperv_user" {
  type        = string
  description = "Hyper-V server username"
}

variable "hyperv_password" {
  type        = string
  description = "Hyper-V server password"
  sensitive   = true
}

variable "hyperv_host" {
  type        = string
  description = "Hyper-V server IP address or hostname"
}
EOF
}

inputs = {
  # VM Configuration
  vm_name             = "devgru-test-01"
  memory              = 2048
  processors          = 2
  
  # Configure Virtual Switch 
  create_switch       = true
  network_switch_name = "DevGru-Test-Switch"
  switch_type         = "Internal"
  switch_notes        = "Created specifically for devgru-test-01 tests"
  
  # Ensure to adapt this to an existing base VHDX path on your host
  vhd_path            = "D:\\Hyper-V\\Virtual Hard Disks\\devgru-test-01.vhdx"
}
