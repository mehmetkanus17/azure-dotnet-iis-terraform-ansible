# variables.tf
variable "admin_username" {}

variable "linux_vm_size" {
  type        = string
  description = "Linux VM size"
}

variable "windows_vm_size" {
  type        = string
  description = "Windows VM size"
}

variable "ssh_public_key_path" {}
variable "ssh_private_key_path" {}

# VM isimleri listesi güncellendi
variable "vm_names" {
  type    = list(string)
  default = ["postgresql-db", "windows-kaynak"]
}

variable "admin_password" {
  description = "Windows VM admin password"
  sensitive   = true
}

variable "rg_name" {
  default = "rg-case"
}

variable "location" {
  default = "East US"
}

variable "control_public_ip" {
  description = "Public IP of Ansible control node (to allow WinRM access)"
  type        = string
}