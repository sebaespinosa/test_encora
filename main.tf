terraform {
  required_providers {
    aws = {
        source = "hashicorp/aws"
        version = "~> 3.0"
    }
  }
}

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

#VPC
resource "aws_vpc" "example" {
  cidr_block = "10.0.0.0/16" # Modify the CIDR block as needed
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