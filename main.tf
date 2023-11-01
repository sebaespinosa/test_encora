
#Providers
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

#Variables
variable "aws_region" {
  description = "The AWS region in which to create the VPC."
  type        = string
  default     = "us-east-1" # Default to us-east-1 if no region is provided
}

variable "alb_port" {
  description = "The port number to use for the ALB listeners."
  type        = number
  default     = 80
}

provider "aws" {
  region = var.aws_region
}

#Data blocks
data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {}

#VPC
resource "aws_vpc" "vpc_ttest" {
  cidr_block           = "10.0.0.0/16" # Demo CIDR
  enable_dns_support   = true
  enable_dns_hostnames = true
}

#2 Subnets
resource "aws_subnet" "subnets_ttest" {
  count                   = 2
  vpc_id                  = aws_vpc.vpc_ttest.id
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  cidr_block              = "10.0.${count.index}.0/24"
  map_public_ip_on_launch = true
}

#Route Table
resource "aws_route_table" "custom_route_table_ttest" {
  vpc_id = aws_vpc.vpc_ttest.id
}

##Internet Gateway for routing through internet and not local routing
resource "aws_internet_gateway" "internet_gateway_ttest" {
  vpc_id = aws_vpc.vpc_ttest.id
}

resource "aws_route" "internet_route" {
  route_table_id         = aws_route_table.custom_route_table_ttest.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway_ttest.id
}

#Policy to restrict access
resource "aws_iam_instance_profile" "instance_profile_ttest" {
  name = "instance_profile_ttest"
}

resource "aws_iam_policy" "restrict_owner_access" {
  name        = "restrict-owner-access"
  description = "Deny access to non-owners"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = "*",
        Effect   = "Deny",
        Resource = "*",
        Condition = {
          StringNotEqualsIfExists = {
            "aws:RequestedOwner" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

resource "aws_iam_role" "iam_role_ttest" {
  name = "iam_role_ttest"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  inline_policy {
    name   = "restrict-access"
    policy = aws_iam_policy.restrict_owner_access.policy
  }
}


#Autoscaling group with their launch configuration
resource "aws_lb_target_group" "lb_target_group_ttest" {
  name        = "my-target-group"
  port        = var.alb_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.vpc_ttest.id
  target_type = "instance"
}

resource "aws_autoscaling_group" "autoscaling_group_ttest" {
  name                 = "autoscaling_group_ttest"
  launch_configuration = aws_launch_configuration.launch_configuration_ttest.name
  min_size             = 2
  max_size             = 4
  desired_capacity     = 2
  #availability_zones = data.aws_availability_zones.available.names
  target_group_arns = [aws_lb_target_group.lb_target_group_ttest.arn]

  #vpc_zone_identifier = [aws_subnet.example1.id, aws_subnet.example2.id]
  vpc_zone_identifier = aws_subnet.subnets_ttest[*].id

  default_cooldown          = 300
  health_check_grace_period = 300
  termination_policies      = ["OldestLaunchConfiguration"]
}

##Launch configuration definition for both instances (auto scaling group handle the minimum of 2)
resource "aws_launch_configuration" "launch_configuration_ttest" {
  name_prefix   = "my-lc"
  image_id      = "ami-011899242bb902164" # Specify your desired AMI ID
  instance_type = "t2.micro"

  iam_instance_profile = aws_iam_instance_profile.instance_profile_ttest.name
}

#Aplication Load Balancer
resource "aws_lb" "lb_ttest" {
  name                       = "lb-ttest"
  internal                   = false
  load_balancer_type         = "application"
  enable_deletion_protection = false
  subnets                    = aws_subnet.subnets_ttest[*].id

  enable_http2 = true
}

resource "aws_lb_listener" "lb_listener_ttest" {
  load_balancer_arn = aws_lb.lb_ttest.arn
  port              = var.alb_port
  protocol          = "HTTP"
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      status_code  = "200"
      message_body = "OK"
    }
  }
}