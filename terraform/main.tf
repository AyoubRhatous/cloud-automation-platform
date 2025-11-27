#################################
#  PROVIDER (LOCALSTACK)
#################################
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    ec2           = "http://localhost:4566"
    autoscaling   = "http://localhost:4566"
    iam           = "http://localhost:4566"
    s3            = "http://localhost:4566"
    lambda        = "http://localhost:4566"
    events        = "http://localhost:4566"
    cloudwatch    = "http://localhost:4566"
    sts           = "http://localhost:4566"
  }
}

#################################
#  KEY PAIR
#################################
resource "aws_key_pair" "devkey" {
  key_name   = "devkey"
  public_key = file("eckey.pub")
}

#################################
#  IAM ROLE FOR EC2
#################################
resource "aws_iam_role" "ec2_role" {
  name = "ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "ec2_policy" {
  name   = "ec2-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = "*",
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ec2_policy.arn
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-profile"
  role = aws_iam_role.ec2_role.name
}

#################################
#  NETWORK: VPC + SUBNETS + IGW
#################################
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "private_1" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.3.0/24"
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

#################################
#  SECURITY GROUPS
#################################
resource "aws_security_group" "public_sg" {
  name   = "public-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "private_sg" {
  name   = "private-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.public_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#################################
#  PUBLIC EC2 AS MOCK LOAD BALANCER
#################################
resource "aws_instance" "proxy" {
  ami                    = "ami-12345678"
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_1.id
  key_name               = aws_key_pair.devkey.key_name
  security_groups        = [aws_security_group.public_sg.name]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  tags = {
    Name = "proxy-nginx"
    App  = "proxy"
    Env  = "dev"
  }
}

#################################
#  LAUNCH TEMPLATES FOR PRIVATE APPS
#################################
resource "aws_launch_template" "app1" {
  name_prefix   = "app1-"
  image_id      = "ami-12345678"
  instance_type = "t3.micro"
  key_name      = aws_key_pair.devkey.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "app1-instance"
      App  = "app1"
      Env  = "dev"
    }
  }
}

resource "aws_launch_template" "app2" {
  name_prefix   = "app2-"
  image_id      = "ami-12345678"
  instance_type = "t3.micro"
  key_name      = aws_key_pair.devkey.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "app2-instance"
      App  = "app2"
      Env  = "dev"
    }
  }
}

#################################
#  AUTOSCALING GROUPS
#################################
resource "aws_autoscaling_group" "asg_app1" {
  name               = "asg-app1"
  desired_capacity   = 2
  max_size           = 4
  min_size           = 1
  vpc_zone_identifier = [aws_subnet.private_1.id]

  launch_template {
    id      = aws_launch_template.app1.id
    version = "$Latest"
  }
}

resource "aws_autoscaling_group" "asg_app2" {
  name               = "asg-app2"
  desired_capacity   = 2
  max_size           = 4
  min_size           = 1
  vpc_zone_identifier = [aws_subnet.private_1.id]

  launch_template {
    id      = aws_launch_template.app2.id
    version = "$Latest"
  }
}

#################################
# OUTPUTS
#################################
output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet" {
  value = aws_subnet.public_1.id
}

output "private_subnet" {
  value = aws_subnet.private_1.id
}

output "proxy_public_ip" {
  value = aws_instance.proxy.public_ip
}

output "asg_app1_name" {
  value = aws_autoscaling_group.asg_app1.name
}

output "asg_app2_name" {
  value = aws_autoscaling_group.asg_app2.name
}
