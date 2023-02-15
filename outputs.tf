output "security_group_id" {
  value = var.create_sg ? aws_security_group.this[0].id : null
}

output "iam_role_arn" {
  value = aws_iam_role.this.arn
}

output "iam_role_name" {
  value = aws_iam_role.this.name
}

output "asg_name" {
  value = aws_autoscaling_group.this.name
}