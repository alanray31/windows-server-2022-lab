terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "Shasta-UCertify-Windows-Server-Lab"
      ManagedBy   = "Terraform"
      Environment = "Learning"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

# AWS maintains this public parameter with the current Windows Server 2022 AMI.
data "aws_ssm_parameter" "windows_server_2022" {
  name = "/aws/service/ami-windows-latest/Windows_Server-2022-English-Full-Base"
}

resource "aws_vpc" "lab" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id

  tags = {
    Name = "${var.name_prefix}-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = var.subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.name_prefix}-public-subnet"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }

  tags = {
    Name = "${var.name_prefix}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "servers" {
  name        = "${var.name_prefix}-servers"
  description = "Lab server access; RDP is allowed only from the configured admin CIDR."
  vpc_id      = aws_vpc.lab.id

  # Allows the DC and member server to communicate with each other for AD DS,
  # DNS, domain join, and lab exercises. This rule is limited to instances
  # assigned this security group.
  ingress {
    description = "Lab server to lab server"
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    self        = true
  }

  dynamic "ingress" {
    for_each = var.admin_cidr == null ? [] : [var.admin_cidr]

    content {
      description = "RDP from the administrator's approved CIDR"
      protocol    = "tcp"
      from_port   = 3389
      to_port     = 3389
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    description = "Outbound access for Windows updates and Systems Manager"
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-servers-sg"
  }
}

data "aws_iam_policy" "ssm_core" {
  name = "AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role" "ssm" {
  name = "${var.name_prefix}-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ssm.name
  policy_arn = data.aws_iam_policy.ssm_core.arn
}

resource "aws_iam_instance_profile" "ssm" {
  name = "${var.name_prefix}-instance-profile"
  role = aws_iam_role.ssm.name
}

resource "aws_instance" "dc" {
  ami                         = data.aws_ssm_parameter.windows_server_2022.value
  instance_type               = var.domain_controller_instance_type
  subnet_id                   = aws_subnet.public.id
  private_ip                  = var.domain_controller_private_ip
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.servers.id]
  iam_instance_profile        = aws_iam_instance_profile.ssm.name

  user_data = templatefile("${path.module}/dc-bootstrap.ps1.tftpl", {
    domain_name             = var.domain_name
    netbios_name            = var.netbios_name
    local_admin_password_b64 = base64encode(var.local_admin_password)
    dsrm_password_b64       = base64encode(var.dsrm_password)
  })

  root_block_device {
    volume_size           = 60
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = {
    Name = "${var.name_prefix}-dc01"
    Role = "DomainController"
  }

  depends_on = [
    aws_route_table_association.public,
    aws_iam_role_policy_attachment.ssm_core
  ]
}

resource "aws_instance" "member" {
  count = var.create_member_server ? 1 : 0

  ami                         = data.aws_ssm_parameter.windows_server_2022.value
  instance_type               = var.member_server_instance_type
  subnet_id                   = aws_subnet.public.id
  private_ip                  = var.member_server_private_ip
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.servers.id]
  iam_instance_profile        = aws_iam_instance_profile.ssm.name

  user_data = templatefile("${path.module}/member-bootstrap.ps1.tftpl", {
    domain_name              = var.domain_name
    netbios_name             = var.netbios_name
    domain_controller_ip     = aws_instance.dc.private_ip
    local_admin_password_b64 = base64encode(var.local_admin_password)
  })

  root_block_device {
    volume_size           = 50
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = {
    Name = "${var.name_prefix}-member01"
    Role = "DomainMember"
  }

  depends_on = [
    aws_instance.dc,
    aws_iam_role_policy_attachment.ssm_core
  ]
}