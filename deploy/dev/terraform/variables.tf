variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "authentik-dev"
}

variable "domain_name" {
  description = "Domain name for the Authentik instance"
  type        = string
  default     = "dev-auth.testimonialtree.com"
}

variable "hosted_zone_id" {
  description = "Route 53 Hosted Zone ID for the domain"
  type        = string
  default     = ""
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_1_cidr" {
  description = "CIDR block for public subnet 1"
  type        = string
  default     = "10.0.1.0/24"
}

variable "public_subnet_2_cidr" {
  description = "CIDR block for public subnet 2"
  type        = string
  default     = "10.0.2.0/24"
}

variable "private_subnet_1_cidr" {
  description = "CIDR block for private subnet 1"
  type        = string
  default     = "10.0.3.0/24"
}

variable "private_subnet_2_cidr" {
  description = "CIDR block for private subnet 2"
  type        = string
  default     = "10.0.4.0/24"
}

# GitHub repository variables for CodePipeline
variable "github_owner" {
  description = "GitHub repository owner/organization"
  type        = string
  default     = "goauthentik"
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "authentik"
}

variable "github_branch" {
  description = "GitHub branch to track"
  type        = string
  default     = "main"
}

# Image to deploy for authentik server/worker
variable "image_uri" {
  description = "Docker image URI for authentik (e.g., ghcr.io/goauthentik/server:2024.8.3)"
  type        = string
  default     = "ghcr.io/goauthentik/server:2024.8.3"
}
