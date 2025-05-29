terraform {
  required_providers {
    vsphere = {
      source  = "hashicorp/vsphere"
      version = "2.4.1"
    }
  }
}

# provider "vsphere" {
#   user                 = "root"
#   password             = var.esxi_password
#   vsphere_server       = var.esxi_host
#   allow_unverified_ssl = true
# }

variable "esxi_hosts" {
  description = "List of ESXi host IPs"
  type        = list(string)
}

variable "esxi_password" {
  description = "ESXi root password"
  type        = string
  sensitive   = true
}

variable "esxi_ssh_port" {
  description = "ESXi SSH port"
  type        = number
  default     = 22
}

variable "datastore_name" {
  description = "Manual datastore name"
  type        = string
}

variable "hardening_script_path" {
  description = "Local path to hardening.sh"
  type        = string
  default     = "./hardening.sh"
}

resource "null_resource" "esxi_harden_setup" {
  for_each = toset(var.esxi_hosts)

  triggers = {
    script_hash = filesha256(var.hardening_script_path)
  }

  connection {
    type     = "ssh"
    host     = each.key
    user     = "root"
    password = var.esxi_password
    port     = var.esxi_ssh_port
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p /tmp/harden",
      "chmod 755 /tmp/harden",
      "hostname > /tmp/harden/hostname.txt"
    ]
  }

  provisioner "file" {
    source      = var.hardening_script_path
    destination = "/tmp/harden/hardening.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/harden/hardening.sh",
      "chown root:root /tmp/harden/hardening.sh",
      "/tmp/harden/hardening.sh"
    ]
  }

  provisioner "file" {
    source      = "/tmp/harden/hostname.txt"
    destination = "output/${each.key}_hostname.txt"
  }

  provisioner "remote-exec" {
    inline = [
      "host=$(cat /tmp/harden/hostname.txt)",
      "cp /tmp/harden/${host}_output.txt /tmp/harden/output.txt"
    ]
  }

  provisioner "file" {
    source      = "/tmp/harden/output.txt"
    destination = "output/${each.key}_output.txt"
  }
}

output "harden_directory_path" {
  value = "/tmp/harden"
}

output "datastore_used" {
  value = var.datastore_name
}
