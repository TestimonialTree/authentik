# Use existing VPC and subnets from account 597332957026
data "aws_vpc" "existing" {
  id = "vpc-0aa69c7dfc14d4148"  # vpc-dev
}

data "aws_subnet" "public_1" {
  id = "subnet-074a9082c9a6d2b7c" # Public subnet 1a (10.0.0.0/18)
}

data "aws_subnet" "public_2" {
  id = "subnet-0c1210f21108bc847" # Public subnet 1b (10.0.64.0/18)
}

data "aws_subnet" "private_1" {
  id = "subnet-0853305679f0dfb1e" # Private subnet 1a (10.0.128.0/18)
}

data "aws_subnet" "private_2" {
  id = "subnet-03488d1eba867dc11" # Private subnet 1b (10.0.192.0/18)
}