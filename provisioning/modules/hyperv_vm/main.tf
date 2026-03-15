# Optionally create a Virtual Switch
resource "hyperv_network_switch" "this" {
  count = var.create_switch ? 1 : 0

  name                = var.network_switch_name
  switch_type         = var.switch_type
  notes               = var.switch_notes
  allow_management_os = true
}

# For Hyper-V we typically define the virtual machine first,
# then attach the VHDX disk and the Virtual Switch.

resource "hyperv_machine_instance" "this" {
  name                 = var.vm_name
  generation           = var.generation
  processor_count      = var.processors
  static_memory        = true
  memory_startup_bytes = var.memory * 1024 * 1024 # Convert MB to bytes
  state                = var.state

  # Configure network adapter attached to the vSwitch
  network_adaptors {
    name = "eth0"

    # If create_switch is true, depend on the new resource, otherwise use the variable name
    switch_name = var.create_switch ? hyperv_network_switch.this[0].name : var.network_switch_name
  }

  # Configure disk (Gen2 uses SCSI controller)
  hard_disk_drives {
    controller_type     = "Scsi"
    controller_number   = 0
    controller_location = 0
    path                = var.vhd_path
  }
}
