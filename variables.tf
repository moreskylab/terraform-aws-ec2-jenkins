variable "use_existing_eip" {
  description = "Whether to use an existing Elastic IP instead of creating a new one"
  type        = bool
  default     = false
}

variable "existing_eip_allocation_id" {
  description = "The allocation ID of the existing Elastic IP to use"
  type        = string
  default     = ""
}