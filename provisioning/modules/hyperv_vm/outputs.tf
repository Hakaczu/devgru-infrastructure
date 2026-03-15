output "vm_name" {
  value       = hyperv_machine_instance.this.name
  description = "ID / Name of the created virtual machine"
}

output "vm_state" {
  value       = hyperv_machine_instance.this.state
  description = "Current state of the virtual machine"
}
