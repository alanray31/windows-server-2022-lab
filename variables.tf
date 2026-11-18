variable "aws_region" {
  description = "AWS region for the lab."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for AWS resource names."
  type        = string
  default     = "ucertify-ws22"
}

variable "vpc_cidr" {
  description = "CIDR block for the lab VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the public lab subnet."
  type        = string
  default     = "10.20.1.0/24"
}

variable "domain_controller_private_ip" {
  description = "Private IPv4 address assigned to the domain controller."
  type        = string
  default     = "10.20.1.10"
}

variable "member_server_private_ip" {
  description = "Private IPv4 address assigned to the optional member server."
  type        = string
  default     = "10.20.1.20"
}

variable "domain_name" {
  description = "DNS name for the new AD forest."
  type        = string
  default     = "corp.example"

  validation {
    condition     = can(regex("^[A-Za-z0-9.-]+$", var.domain_name))
    error_message = "Use a DNS-style domain name containing only letters, numbers, dots, and hyphens."
  }
}

variable "netbios_name" {
  description = "NetBIOS name for the AD domain."
  type        = string
  default     = "CORP"

  validation {
    condition     = length(var.netbios_name) >= 1 && length(var.netbios_name) <= 15
    error_message = "NetBIOS name must be between 1 and 15 characters."
  }
}

variable "admin_cidr" {
  description = "Your public IPv4 CIDR allowed to RDP, preferably your address followed by /32. Leave null to disable inbound RDP."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.admin_cidr == null || can(cidrhost(var.admin_cidr, 0))
    error_message = "admin_cidr must be a valid IPv4 CIDR, for example 203.0.113.25/32."
  }
}

variable "create_member_server" {
  description = "Create a second Windows server that joins the new domain."
  type        = bool
  default     = true
}

variable "domain_controller_instance_type" {
  description = "EC2 instance type for the domain controller."
  type        = string
  default     = "t3.large"
}

variable "member_server_instance_type" {
  description = "EC2 instance type for the member server."
  type        = string
  default     = "t3.medium"
}

variable "local_admin_password" {
  description = "Strong password set for the Windows Administrator account. The domain Administrator uses this password after forest creation."
  type        = string
  sensitive   = true

  validation {
    condition = (
      length(var.local_admin_password) >= 14 &&
      can(regex("[A-Z]", var.local_admin_password)) &&
      can(regex("[a-z]", var.local_admin_password)) &&
      can(regex("[0-9]", var.local_admin_password)) &&
      can(regex("[^A-Za-z0-9]", var.local_admin_password))
    )
    error_message = "Use at least 14 characters with uppercase, lowercase, numeric, and special characters."
  }
}

variable "dsrm_password" {
  description = "Separate Directory Services Restore Mode password for the domain controller."
  type        = string
  sensitive   = true

  validation {
    condition = (
      length(var.dsrm_password) >= 14 &&
      can(regex("[A-Z]", var.dsrm_password)) &&
      can(regex("[a-z]", var.dsrm_password)) &&
      can(regex("[0-9]", var.dsrm_password)) &&
      can(regex("[^A-Za-z0-9]", var.dsrm_password))
    )
    error_message = "Use at least 14 characters with uppercase, lowercase, numeric, and special characters."
  }
}