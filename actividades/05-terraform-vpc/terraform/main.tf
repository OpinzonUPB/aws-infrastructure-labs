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
# Datos que YA existen (solo se consultan)
# ---------------------------------------------------------------------------

# Fijamos la zona "a" porque algunas zonas no ofrecen todos los tipos de
# instancia (p. ej. t3.micro).
locals {
  az = "${var.aws_region}a"
}

# Lista de prefijos administrada por AWS con las direcciones del servicio
# EC2 Instance Connect en esta región.
data "aws_ec2_managed_prefix_list" "instance_connect" {
  name = "com.amazonaws.${var.aws_region}.ec2-instance-connect"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

# ---------------------------------------------------------------------------
# Red: lo NUEVO de esta actividad
# ---------------------------------------------------------------------------

# 1. VPC: nuestra red privada dentro de AWS
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "vpc-docker-sizing"
  }
}

# 2. Subnet pública: un pedazo de la VPC donde vivirá la instancia
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = local.az
  map_public_ip_on_launch = true

  tags = {
    Name = "subnet-publica-docker-sizing"
  }
}

# 3. Internet Gateway: la puerta de la VPC hacia Internet
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "igw-docker-sizing"
  }
}

# 4. Route Table: "todo lo que no sea de la VPC sale por el Internet Gateway"
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "rt-publica-docker-sizing"
  }
}

# 5. Asociación: esta tabla de rutas gobierna a la subnet pública
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# Security Group: mismas reglas que en la Actividad 04
# ---------------------------------------------------------------------------

resource "aws_security_group" "app" {
  name        = "docker-sizing-vpc-sg"
  description = "SSH solo desde EC2 Instance Connect y app en el puerto 8000 solo desde mi IP"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "docker-sizing-vpc-sg"
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

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.app.id
  description       = "Salida a Internet"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------------------------------------------------------------------------
# Instancia EC2: exactamente la misma aplicación y el mismo User Data
# ---------------------------------------------------------------------------

resource "aws_instance" "app" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.app.id]
  associate_public_ip_address = true

  user_data                   = file("${path.module}/../../03-user-data/user-data.sh")
  user_data_replace_on_change = true

  root_block_device {
    volume_type = "gp3"
    volume_size = var.volume_size
  }

  # La instancia necesita la ruta a Internet lista antes de arrancar, porque
  # el User Data descarga paquetes y clona el repositorio.
  depends_on = [aws_route_table_association.public]

  tags = {
    Name = "docker-sizing-vpc"
  }
}
