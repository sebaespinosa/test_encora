
#Providers
terraform {
  required_providers {
    aws = {
        source = "hashicorp/aws"
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

data "aws_caller_identity" "current" {}


#VPC
resource "aws_vpc" "example" {
  cidr_block = "10.0.0.0/16" # Demo CIDR
  enable_dns_support = true
  enable_dns_hostnames = true
}

#2 Subnets
resource "aws_subnet" "subnet_a" {
  count                  = 2
  vpc_id                 = aws_vpc.example.id
  availability_zone      = element(data.aws_availability_zones.available.names, count.index)
  cidr_block             = "10.0.${count.index}.0/24"
  map_public_ip_on_launch = true
}

#Route Table
resource "aws_route_table" "custom_route_table" {
  vpc_id = aws_vpc.example.id
}

##Internet Gateway for routing through internet and not local routing
resource "aws_internet_gateway" "example" {
  vpc_id = aws_vpc.example.id
}

resource "aws_route" "internet_route" {
  route_table_id         = aws_route_table.custom_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.example.id
}

#Policy to restrict access
resource "aws_iam_instance_profile" "example" {
  name = "my-instance-profile"
}

resource "aws_iam_policy" "restrict_owner_access" {
  name        = "restrict-owner-access"
  description = "Deny access to non-owners"
  
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "*",
        Effect = "Deny",
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

resource "aws_iam_role" "example" {
  name = "my-role"
  
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
    name = "restrict-access"
    policy = aws_iam_policy.restrict_owner_access.policy
  }
}


#Autoscaling group with their launch configuration
resource "aws_lb_target_group" "example" {
  name        = "my-target-group"
  port        = var.alb_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.example.id
  target_type = "instance"
}

resource "aws_autoscaling_group" "example" {
  name = "my-asg"
  launch_configuration = aws_launch_configuration.example.name
  min_size = 2
  max_size = 4
  desired_capacity = 2
  #availability_zones = data.aws_availability_zones.available.names
  target_group_arns = [aws_lb_target_group.example.arn]

  #vpc_zone_identifier = [aws_subnet.example1.id, aws_subnet.example2.id]
  vpc_zone_identifier = aws_subnet.subnet_a[*].id

  default_cooldown = 300
  health_check_grace_period = 300
  termination_policies = ["OldestLaunchConfiguration"]
}

##Launch configuration definition for both instances (auto scaling group handle the minimum of 2)
resource "aws_launch_configuration" "example" {
  name_prefix = "my-lc"
  image_id = "ami-011899242bb902164"  # Specify your desired AMI ID
  instance_type = "t2.micro"

  iam_instance_profile = aws_iam_instance_profile.example.name
}

#Aplication Load Balancers
#Aplication Load Balancer
resource "aws_lb" "example" {
  name = "my-alb"
  internal = false
  load_balancer_type = "application"
  enable_deletion_protection = false
  subnets = aws_subnet.subnet_a[*].id

  enable_http2 = true
}

resource "aws_lb_listener" "example" {
  load_balancer_arn = aws_lb.example.arn
  port = var.alb_port
  protocol = "HTTP"
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      status_code = "200"
      message_body = "OK"
    }
  }
}





data "aws_availability_zones" "available" {}



output "vpc_id" {
  value = aws_vpc.example.id
}

output "subnet_ids" {
  value = aws_subnet.subnet_a[*].id
}

output "route_table_id" {
  value = aws_route_table.custom_route_table.id
}

output "internet_route" {
  value = aws_route.internet_route.id
}

output "internet_gateway_id" {
  value = aws_internet_gateway.example.id
}




#provider "aws" {
#  region = "us-east-1"
#}
#
#resource "aws_instance" "example" {
#  ami = "ami-011899242bb902164" # Ubuntu 20.04 LTS // us-east-1
#  instance_type = "t2.micro"
#  provider = aws
#}