output "instance_id" {
  description = "ID de la instancia (para encontrarla en la consola)"
  value       = aws_instance.app.id
}

output "public_ip" {
  description = "IP pública de la instancia"
  value       = aws_instance.app.public_ip
}

output "private_ip" {
  description = "IP privada de la instancia"
  value       = aws_instance.app.private_ip
}

output "health_url" {
  description = "URL para probar la aplicación (espera 2-4 minutos tras el apply)"
  value       = "http://${aws_instance.app.public_ip}:8000/health"
}
