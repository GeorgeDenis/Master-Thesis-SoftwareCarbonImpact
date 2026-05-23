# variables.tf — Inputs for the PetRescue AWS deployment.

variable "aws_region" {
  description = "AWS region. Pick one close to you with free-tier eligibility."
  type        = string
  default     = "eu-central-1" # Frankfurt, same geography as your OCI setup
}

variable "ssh_public_key" {
  description = "Contents of your SSH public key file (the .pub one)."
  type        = string
  validation {
    condition     = can(regex("^(ssh-rsa|ssh-ed25519|ecdsa-sha2-) ", var.ssh_public_key))
    error_message = "Must be a valid OpenSSH public key."
  }
}

variable "instance_name" {
  description = "Name tag for the EC2 instance."
  type        = string
  default     = "petrescue-cloud"
}

variable "boot_volume_size_gb" {
  description = "Root EBS volume size in GB. Free tier includes 30 GB gp2/gp3."
  type        = number
  default     = 30
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH. Default 0.0.0.0/0; tighten to your IP for security."
  type        = string
  default     = "0.0.0.0/0"
}

variable "allowed_http_cidr" {
  description = "CIDR allowed to hit the API (8080) and sidecar (5055)."
  type        = string
  default     = "0.0.0.0/0"
}
