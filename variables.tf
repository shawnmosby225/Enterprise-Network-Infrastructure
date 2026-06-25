variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "Target AWS Region for deployment"
}

variable "vpc_cidr" {
  type        = string
  default     = "192.168.0.0/16"
  description = "Main corporate CIDR block for the VPC"
}