# main.tf — PetRescue AWS deployment (free-tier fallback).
#
# Creates: VPC, public subnet, internet gateway, route table, security group,
# and a single m7i-flex.large EC2 instance running Ubuntu 22.04 x86_64.
#
# The instance is bootstrapped via cloud-init.yaml (adapted for AWS/x86).

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# -----------------------------------------------------------------------------
# Resolve the latest Ubuntu 22.04 x86_64 AMI from Canonical.
# -----------------------------------------------------------------------------
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# -----------------------------------------------------------------------------
# Networking: VPC -> public subnet -> internet gateway -> route table.
# -----------------------------------------------------------------------------

resource "aws_vpc" "petrescue" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "petrescue-vpc" }
}

resource "aws_internet_gateway" "petrescue" {
  vpc_id = aws_vpc.petrescue.id
  tags   = { Name = "petrescue-igw" }
}

resource "aws_route_table" "petrescue" {
  vpc_id = aws_vpc.petrescue.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.petrescue.id
  }

  tags = { Name = "petrescue-rt" }
}

resource "aws_subnet" "petrescue_public" {
  vpc_id                  = aws_vpc.petrescue.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"

  tags = { Name = "petrescue-public" }
}

resource "aws_route_table_association" "petrescue" {
  subnet_id      = aws_subnet.petrescue_public.id
  route_table_id = aws_route_table.petrescue.id
}

resource "aws_subnet" "petrescue_public_b" {
  vpc_id                  = aws_vpc.petrescue.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}b"

  tags = { Name = "petrescue-public-b" }
}

resource "aws_route_table_association" "petrescue_b" {
  subnet_id      = aws_subnet.petrescue_public_b.id
  route_table_id = aws_route_table.petrescue.id
}

# Security group: SSH, API (8080), CodeCarbon sidecar (5055), ICMP.
resource "aws_security_group" "petrescue" {
  name_prefix = "petrescue-"
  description = "PetRescue API + sidecar access"
  vpc_id      = aws_vpc.petrescue.id

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
    description = "SSH"
  }

  # API (port 8080) — .NET or FastAPI, one at a time
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.allowed_http_cidr]
    description = "PetRescue API (.NET or FastAPI)"
  }

  # CodeCarbon sidecar (port 5055)
  ingress {
    from_port   = 5055
    to_port     = 5055
    protocol    = "tcp"
    cidr_blocks = [var.allowed_http_cidr]
    description = "CodeCarbon sidecar"
  }

  # ICMP (ping)
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "ICMP ping"
  }

  # Egress: allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound"
  }

  tags = { Name = "petrescue-sg" }
}

# -----------------------------------------------------------------------------
# SSH Key Pair.
# -----------------------------------------------------------------------------
resource "aws_key_pair" "petrescue" {
  key_name   = "petrescue-key"
  public_key = var.ssh_public_key
}

# -----------------------------------------------------------------------------
# EC2 Instance — m7i-flex.large (Free Tier eligible: 2 vCPU, 8 GB RAM).
# -----------------------------------------------------------------------------
resource "aws_instance" "net_m7i" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "m7i-flex.large"
  key_name               = aws_key_pair.petrescue.key_name
  subnet_id              = aws_subnet.petrescue_public.id
  vpc_security_group_ids = [aws_security_group.petrescue.id]

  root_block_device {
    volume_size = var.boot_volume_size_gb
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = file("${path.module}/cloud-init.yaml")

  tags = { Name = "net-m7i" }

  lifecycle {
    ignore_changes = [ami]
  }
}

resource "aws_instance" "flask_m7i" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "m7i-flex.large"
  key_name               = aws_key_pair.petrescue.key_name
  subnet_id              = aws_subnet.petrescue_public.id
  vpc_security_group_ids = [aws_security_group.petrescue.id]

  root_block_device {
    volume_size = var.boot_volume_size_gb
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = file("${path.module}/cloud-init.yaml")

  tags = { Name = "flask-m7i" }

  lifecycle {
    ignore_changes = [ami]
  }
}
# -----------------------------------------------------------------------------
# EC2 Instances — c7i-flex.large (2 instances: 1 .NET, 1 Flask)
# Each VM runs both baseline + optimized (script handles config switching).
# -----------------------------------------------------------------------------

resource "aws_instance" "net_c7i" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "c7i-flex.large"
  key_name               = aws_key_pair.petrescue.key_name
  subnet_id              = aws_subnet.petrescue_public_b.id
  vpc_security_group_ids = [aws_security_group.petrescue.id]

  root_block_device {
    volume_size = var.boot_volume_size_gb
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = file("${path.module}/cloud-init.yaml")
  tags = { Name = "net-c7i" }
  lifecycle { ignore_changes = [ami] }
}

resource "aws_instance" "flask_c7i" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "c7i-flex.large"
  key_name               = aws_key_pair.petrescue.key_name
  subnet_id              = aws_subnet.petrescue_public_b.id
  vpc_security_group_ids = [aws_security_group.petrescue.id]

  root_block_device {
    volume_size = var.boot_volume_size_gb
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = file("${path.module}/cloud-init.yaml")
  tags = { Name = "flask-c7i" }
  lifecycle { ignore_changes = [ami] }
}

# -----------------------------------------------------------------------------
# EC2 Instances — t3.small (2 instances: 1 .NET, 1 Flask)
# Burstable, 2 vCPU, 2 GB RAM — natural CPU/RAM bottleneck.
# -----------------------------------------------------------------------------

resource "aws_instance" "net_t3" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.small"
  key_name               = aws_key_pair.petrescue.key_name
  subnet_id              = aws_subnet.petrescue_public.id
  vpc_security_group_ids = [aws_security_group.petrescue.id]

  root_block_device {
    volume_size = var.boot_volume_size_gb
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = file("${path.module}/cloud-init.yaml")
  tags = { Name = "net-t3" }
  lifecycle { ignore_changes = [ami] }
}

resource "aws_instance" "flask_t3" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.small"
  key_name               = aws_key_pair.petrescue.key_name
  subnet_id              = aws_subnet.petrescue_public.id
  vpc_security_group_ids = [aws_security_group.petrescue.id]

  root_block_device {
    volume_size = var.boot_volume_size_gb
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = file("${path.module}/cloud-init.yaml")
  tags = { Name = "flask-t3" }
  lifecycle { ignore_changes = [ami] }
}
