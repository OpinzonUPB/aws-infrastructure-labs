terraform {
  required_version = ">= 1.5"

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

# ---------------------------------------------------------------------------
# Datos que YA existen en el Sandbox (no se crean, solo se consultan)
# ---------------------------------------------------------------------------

# VPC por defecto de la cuenta
data "aws_vpc" "default" {
  default = true
}

# Subnet por defecto de la zona "a". Fijamos la zona porque algunas zonas de
# disponibilidad no ofrecen todos los tipos de instancia (p. ej. t3.micro).
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "availability-zone"
    values = ["${var.aws_region}a"]
  }
}

# Lista de prefijos administrada por AWS con las direcciones del servicio
# EC2 Instance Connect en esta región. AWS la mantiene actualizada por nosotros.
data "aws_ec2_managed_prefix_list" "instance_connect" {
  name = "com.amazonaws.${var.aws_region}.ec2-instance-connect"
}

# Imagen (AMI) más reciente de Ubuntu Server 24.04 publicada por Canonical
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

# ---------------------------------------------------------------------------
# Security Group: lo que antes hicimos a mano en la consola
# ---------------------------------------------------------------------------

resource "aws_security_group" "app" {
  name        = "docker-sizing-terraform-sg"
  description = "SSH solo desde EC2 Instance Connect y app en el puerto 8000 solo desde mi IP"
  vpc_id      = data.aws_vpc.default.id

  tags = {
    Name = "docker-sizing-terraform-sg"
  }
}

# Puerto administrativo (22): solo el servicio EC2 Instance Connect
resource "aws_vpc_security_group_ingress_rule" "ssh_instance_connect" {
  security_group_id = aws_security_group.app.id
  description       = "SSH desde EC2 Instance Connect"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  prefix_list_id    = data.aws_ec2_managed_prefix_list.instance_connect.id
}

# Puerto de la aplicación (8000): solo tu IP. Es una regla aparte del SSH.
resource "aws_vpc_security_group_ingress_rule" "app" {
  security_group_id = aws_security_group.app.id
  description       = "Aplicacion FastAPI desde mi IP"
  ip_protocol       = "tcp"
  from_port         = 8000
  to_port           = 8000
  cidr_ipv4         = var.my_ip_cidr
}

# Terraform elimina la regla de salida por defecto, así que la declaramos:
# la instancia necesita salir a Internet para instalar paquetes y clonar el repo.
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.app.id
  description       = "Salida a Internet"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------------------------------------------------------------------------
# Instancia EC2 con la misma aplicación Docker (User Data de la Actividad 03)
# ---------------------------------------------------------------------------

resource "aws_instance" "app" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.app.id]
  associate_public_ip_address = true

  user_data                   = file("${path.module}/../../03-user-data/user-data.sh")
  user_data_replace_on_change = true

  root_block_device {
    volume_type = "gp3"
    volume_size = var.volume_size
  }

  tags = {
    Name = "docker-sizing-terraform"
  }
}
