variable "aws_region" {
  description = "Región de AWS. Debe ser la misma del Sandbox."
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "Tipo de instancia EC2 (pequeño, permitido por el Sandbox)."
  type        = string
  default     = "t3.micro"
}

variable "volume_size" {
  description = "Tamaño del disco raíz en GiB (suficiente para las imágenes de Docker)."
  type        = number
  default     = 20
}

variable "my_ip_cidr" {
  description = "IP pública del estudiante en formato CIDR, por ejemplo 203.0.113.25/32. Solo esta IP podrá acceder al puerto 8000."
  type        = string

  validation {
    condition     = can(cidrhost(var.my_ip_cidr, 0))
    error_message = "Se debe indicar una IP en formato CIDR, por ejemplo 203.0.113.25/32."
  }
}
