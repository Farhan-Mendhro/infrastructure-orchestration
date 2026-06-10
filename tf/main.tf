terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  owners = ["099720109477"] # Canonical owner ID
}

locals {
  instances = {
    instance1 = { ami = data.aws_ami.ubuntu.id, instance_type = "t3.micro" }
    instance2 = { ami = data.aws_ami.ubuntu.id, instance_type = "t3.micro" }
    instance3 = { ami = data.aws_ami.ubuntu.id, instance_type = "t3.micro" }
    instance4 = { ami = data.aws_ami.ubuntu.id, instance_type = "t3.micro" }
    instance5 = { ami = data.aws_ami.ubuntu.id, instance_type = "t3.micro" } # Central Monitoring Node
  }
}

resource "aws_key_pair" "ssh_key" {
  key_name   = "infra-key"
  public_key = file(var.public_key)
}

resource "aws_security_group" "main" {
  name        = "spacelift-orchestration-sg"
  description = "Allow SSH, Docker apps, and Prometheus monitoring traffic"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Opens Prometheus UI dashboard
  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Opens Grafana UI dashboard
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "this" {
  for_each               = local.instances
  ami                    = each.value.ami
  instance_type          = each.value.instance_type
  key_name               = aws_key_pair.ssh_key.key_name
  vpc_security_group_ids = [aws_security_group.main.id]
  associate_public_ip_address = true

  tags = {
    Name = each.key
  }
}