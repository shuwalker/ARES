# ─────────────────────────────────────────────────────────────────────────────
# Networking module outputs
# ─────────────────────────────────────────────────────────────────────────────

output "vpc_id" {
  description = "ID of the provisioned VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "public_security_group_ids" {
  description = "Security group IDs for public-facing resources (LB)"
  value       = [aws_security_group.public.id]
}

output "private_security_group_ids" {
  description = "Security group IDs for private resources (containers)"
  value       = [aws_security_group.private.id]
}

output "storage_security_group_ids" {
  description = "Security group IDs for persistent storage"
  value       = [aws_security_group.storage.id]
}

output "nat_gateway_ip" {
  description = "Public IP of the NAT gateway"
  value       = aws_eip.nat.public_ip
}

output "internet_gateway_id" {
  description = "ID of the internet gateway"
  value       = aws_internet_gateway.main.id
}

output "availability_zones" {
  description = "Availability zones used for deployment"
  value       = local.availability_zones
}
