provider "aws" {
  region = "us-east-1"
}

locals {
  app_name        = "my-app"
  instance_type   = "t3.micro"
  # subnet_cidr     = "10.2.0.0/24"
  vpc_cidr        = "10.2.0.0/16"
  security_group  = "${local.app_name}-security-group"
  key_pair_name   = "my-app-key-pair"  # Replace with your actual SSH key pair name
}

# Only use good Availabilit Zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Identify latest Amazon Linux 2023 Image
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}


# VPC creation
resource "aws_vpc" "main" {
  cidr_block           = local.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.app_name}-VPC"
  }
}

# IGW
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "main-igw"
  }
}


#Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = {
    Name = "public-rt"
  }
}

#Private Route Table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "private-rt"
  }
}

#Public Subnets
resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.2.${count.index + 1}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "public-subnet-${count.index + 1}"
  }
}

#Private Subnets
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.2.${count.index + 3}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
    tags = {
    Name = "private-subnet-${count.index + 1}"
  }
}

# Route Table association for Public
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Create Elastic IP for NAT GW
resource "aws_eip" "nat" {
  domain   = "vpc"

  tags = {
    Name = "nat-eip"
  }
}

# Create NAT Gateway
resource "aws_nat_gateway" "nat-gw" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "nat-gateway"
  }

  depends_on = [aws_internet_gateway.gw]
}

# Create Route for Private Subnets to NAT GW for Internet Access
resource "aws_route" "private_nat_access" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat-gw.id
}

# Create Route Table Association for Private Subnets
resource "aws_route_table_association" "private" {
  # subnet_id      = aws_subnet.private.id
  # route_table_id = aws_route_table.private.id
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Create a security group for the load balancer
resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Security group for ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
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

# Security group for web traffic
resource "aws_security_group" "web" {
  name                 = local.security_group
  vpc_id               = aws_vpc.main.id

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

# Security group for SSH access
resource "aws_security_group" "ssh" {
  name                 = "${local.security_group}-ssh"
  vpc_id               = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
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

# Create IAM Role to be used later in EC2 Instance Profile
resource "aws_iam_role" "my_app_ec2_role" {
  name               = "my-app-launch-template-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Effect = "Allow"
      }
    ]
  })
}

# Create IAM Policy to be used later in IAM Role
resource "aws_iam_policy" "my_app_inline_policy" {
  name        = "my-app-launch-template-policy"
  description = "My app policy for launch template"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:Describe*",
          "elasticloadbalancing:Describe*",
          "autoscaling:Describe*",
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# Attach IAM Policy to IAM Role
resource "aws_iam_role_policy_attachment" "my_app_inline_policy_attach" {
  role       = aws_iam_role.my_app_ec2_role.name
  policy_arn = aws_iam_policy.my_app_inline_policy.arn
}

# Attach SSM Managed Policy the IAM Role
resource "aws_iam_role_policy_attachment" "my_app_managed_policy_attach" {
  role       = aws_iam_role.my_app_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Create EC2 Instance Profile
resource "aws_iam_instance_profile" "my_app_instance_profile" {
  name = "my-app-launch-template-profile"
  role = aws_iam_role.my_app_ec2_role.name
}

# Create Launch Template
resource "aws_launch_template" "my_app_lt" {
  name_prefix   = "${local.app_name}-launch-template-"
  # image_id      = "ami-0c55babe7a7b8107f"  # Replace with a suitable AMI ID
  image_id      = data.aws_ami.amazon_linux_2023.id
  instance_type = local.instance_type
  key_name      = var.key_pair_name

  placement {
    availability_zone = data.aws_availability_zones.available.names[0] # Replace with your desired AZ
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.my_app_instance_profile.name
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.web.id]  # Only expose to web traffic
    subnet_id                   = aws_subnet.private[0].id
  }

  # user_data = base64encode("${path.module}/user_data.tpl")
  # user_data = base64(data.template_file.user_data.rendered)
  # user_data = base64encode(templatefile("${path.module}/user_data.tpl", {
  #   instance_id   = "i-xxxxxxxxxxxxxxxxx" # Replace with a real instance ID for testing, or leave it dynamic if needed
  #   instance_type = var.instance_type
  # }))
  user_data = base64encode(file("${path.module}/user_data.tpl"))
# )
}


# Create Auto Scaling Group
resource "aws_autoscaling_group" "my_app_asg" {
  # name                 = "example-asg"
  availability_zones   = [data.aws_availability_zones.available.names[0]]
  # vpc_zone_identifier  = data.aws_subnet_ids.default.ids
  desired_capacity     = 1
  max_size             = 2
  min_size             = 0
  health_check_type    = "ELB"

  launch_template {
    id      = aws_launch_template.my_app_lt.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.my_app_lb_tg.arn]
  # load_balancers = [aws_lb.my_app_lb.name] #Use only for Classic LB

  tag {
    key                 = "Name"
    value               = "example-asg-instance"
    propagate_at_launch = true
  }
}


# Create Application Load Balancer in Public Subnet
resource "aws_lb" "my_app_lb" {
  name               = "${local.app_name}-load-balancer"
  load_balancer_type = "application"
  internal           = false

  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public[0].id, aws_subnet.public[1].id]

  enable_deletion_protection = false
}


# Create Target Group for the Load Balancer
resource "aws_lb_target_group" "my_app_lb_tg" {
  name                = "${local.app_name}-target-group"
  port                = 80
  protocol            = "HTTP"
  target_type         = "instance"
  vpc_id              = aws_vpc.main.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-299"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}


# Create ALB Listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.my_app_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.my_app_lb_tg.arn
  }
}


# Outputs
output "alb_dns_name" {
  value = aws_lb.my_app_lb.dns_name
}

