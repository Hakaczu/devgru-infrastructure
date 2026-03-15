variable "vm_name" {
  type        = string
  description = "Name of the virtual machine in Hyper-V"
}

variable "generation" {
  type        = number
  description = "Virtual machine generation (1 or 2)"
  default     = 2
}

variable "memory" {
  type        = number
  description = "Amount of RAM (in megabytes)"
  default     = 2048
}

variable "processors" {
  type        = number
  description = "Number of virtual processor cores (vCPU)"
  default     = 2
}

variable "network_switch_name" {
  type        = string
  description = "Name of the Virtual Switch in Hyper-V"
}

variable "vhd_path" {
  type        = string
  description = "Absolute path to the previously created VHDX disk"
}

variable "state" {
  type        = string
  description = "Target state of the machine (Running, Off)"
  default     = "Running"
}

variable "create_switch" {
  type        = bool
  description = "Determines whether the module should create the Virtual Switch"
  default     = false
}

variable "switch_type" {
  type        = string
  description = "Specifies the type of switch (Internal, Private, External)"
  default     = "Internal"
}

variable "switch_notes" {
  type        = string
  description = "Optional notes/description for the switch"
  default     = ""
}
