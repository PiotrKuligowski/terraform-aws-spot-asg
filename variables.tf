variable "component" {
  description = "Component name, will be used to generate names for created resources"
  type        = string
}

variable "project" {
  description = "Project name, will be used to generate names for created resources"
  type        = string
}

variable "tags" {
  description = "Tags to attach to resources"
  default     = {}
}

variable "ami_id" {
  description = "AMI ID to use for EC2 instances created by AutoScaling Group"
  type        = string
}

variable "ssh_key_name" {
  description = "Key pair name for SSH"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where EC2 instances should be created"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet ids where EC2 instances should be created"
  type        = list(string)
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t4g.micro"
}

variable "user_data" {
  description = "EC2 bootstrap script that will be executed at instance boot"
  type        = string
}

variable "policy_statements" {
  description = "Policy statements to attach to IAM role used by EC2 Instances"
  default     = {}
}

variable "asg_min_size" {
  description = "Min number of running instances"
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Max number of running instances"
  type        = number
  default     = 1
}

variable "asg_desired_capacity" {
  description = "Desired number of running instances"
  type        = number
  default     = 1
}

variable "domain" {
  description = "If supplied, EC2 instance will put its public ip to public Route53 zone"
  type        = string
  default     = null
}

variable "private_domain" {
  description = "If supplied, EC2 instance will put its private ip to private Route53 zone"
  type        = string
  default     = null
}

variable "record_ttl" {
  description = "Time to live for DNS entries created by EC2 instance"
  type        = number
  default     = 30
}

variable "record_name" {
  description = "If supplied domain is 'example.com' and record_name set to 'sub' then 'sub.example.com' will be put to Route53 zone"
  type        = string
  default     = null
}

variable "install_awscliv2" {
  description = "Flag indicating whether AWS CLI v2 should be installed"
  default     = false
}

variable "create_sg" {
  description = "Flag indicating whether security group should be created"
  type        = bool
  default     = false
}

variable "security_groups" {
  description = "List of additional security groups to attach to EC2 instances"
  type        = list(string)
  default     = []
}

variable "associate_public_ip_address" {
  description = "Flag indicating whether public ip should be associated"
  default     = true
}

variable "disable_source_dest_check" {
  description = "Flag indicating whether source/dest check should be disabled"
  default     = false
}