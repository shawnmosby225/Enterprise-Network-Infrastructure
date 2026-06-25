data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"] # Canonical (Official Ubuntu Owner ID)
}


resource "aws_security_group" "app_sg" {
  name        = "application-security-group"
  description = "Managed firewall rules for private app instance"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow internal HTTP traffic from our network block"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr] # Restricts access to 192.168.0.0/16
  }

  ingress {
    description = "Allow internal SSH management traffic"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Outbound rules: Allow the server to talk out via the NAT Gateway for OS patches
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "app-security-boundary"
  }
}

# 3. The Isolated Linux Server Instance
resource "aws_instance" "app_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro" # Keeps it free-tier or very low cost

  # Drop it directly into our private network block
  subnet_id                   = aws_subnet.private_1.id
  vpc_security_group_ids      = [aws_security_group.app_sg.id]
  associate_public_ip_address = false

  tags = {
    Name        = "production-app-linux-01"
    Environment = "Production"
    ManagedBy   = "Terraform"
  }
}