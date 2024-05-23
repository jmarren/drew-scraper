

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}




provider "aws" {
  region = "us-west-1"
}

variable "secret_arn" {
  description = "ARN of the AWS secret"
  type        = string
}

resource "aws_eip" "one" {
  instance = aws_instance.app_instance.id
  domain   = "vpc"
}

resource "aws_eip_association" "eip_assoc" {
  instance_id   = aws_instance.app_instance.id
  allocation_id = aws_eip.one.id
}

resource "aws_iam_policy" "secretsmanager_policy" {
  name        = "SecretsManagerAccessPolicy"
  description = "Allows access to the Secrets Manager service"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = "secretsmanager:GetSecretValue",
        Resource = var.secret_arn
      }
    ]
  })
}

resource "aws_iam_role" "ec2_secrets_role" {
  name = "EC2SecretsManagerRole"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole",
      "Sid" : ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "secrets_policy_attach" {
  role       = aws_iam_role.ec2_secrets_role.name
  policy_arn = aws_iam_policy.secretsmanager_policy.arn
}

resource "aws_iam_instance_profile" "ec2_secrets_profile" {
  name = "EC2SecretsProfile"
  role = aws_iam_role.ec2_secrets_role.name
}




resource "aws_instance" "app_instance" {
  ami           = "ami-0e88f21371b39efa8" # Example AMI ID, replace with a valid one for your region
  instance_type = "t2.micro"
  key_name      = "thelambofjohn" # Ensure you have a key pair for SSH access

  iam_instance_profile = aws_iam_instance_profile.ec2_secrets_profile.name

  security_groups = [aws_security_group.instance_sg.name]

  tags = {
    Name = "droopy-instance"
  }

  user_data = <<-EOF
#!/bin/bash
# set -eo pipefail
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1
# Update package list
sudo apt update -y
# Install required packages
sudo apt install -y nginx unzip jq || { echo 'Failed to install packages'; exit 1; }
# Download and install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip || { echo 'Failed to unzip AWS CLI'; exit 1; }
sudo ./aws/install || { echo 'Failed to install AWS CLI'; exit 1; }
# Update package list again
sudo apt update
# Install the specified packages with apt
sudo apt install -y \
  libasound2 \
  libatk-bridge2.0-0 \
  libatk1.0-0 \
  libc6 \
  libcairo2 \
  libcups2 \
  libdbus-1-3 \
  libdrm2 \
  libexpat1 \
  libgbm1 \
  libglib2.0-0 \
  libnspr4 \
  libnss3 \
  libpango-1.0-0 \
  libpangocairo-1.0-0 \
  libstdc++6 \
  libx11-6 \
  libx11-xcb1 \
  libxcb-dri3-0 \
  libxcb1 \
  libxcomposite1 \
  libxcursor1 \
  libxdamage1 \
  libxext6 \
  libxfixes3 \
  libxi6 \
  libxkbcommon0 \
  libxrandr2 \
  libxrender1 \
  libxshmfence1 \
  libxss1 \
  libxtst6 || { echo 'Failed to install libraries'; exit 1; }
# Fetch SSL certificate from AWS Secrets Manager
SECRET=$(aws secretsmanager get-secret-value --secret-id "droopy_ssl_cert" --region "us-west-1" --output json)
FULLCHAIN=$(echo $SECRET | jq -r '.SecretString | fromjson.fullchain')
PRIVKEY=$(echo $SECRET | jq -r '.SecretString | fromjson.privkey')
# Create directory for SSL certificates
sudo mkdir -p /etc/letsencrypt/live/droopy.mechanicalturk.one
# Format and save SSL certificates
formatted_fullchain=$(echo "$FULLCHAIN" | sed -e 's/-----END CERTIFICATE-----/\n-----END CERTIFICATE-----/' -e 's/-----BEGIN CERTIFICATE-----/-----BEGIN CERTIFICATE-----\n/')
final_fullchain=$(echo "$formatted_fullchain" | sed 's/-----END CERTIFICATE----------BEGIN CERTIFICATE-----/-----END CERTIFICATE-----\n-----BEGIN CERTIFICATE-----/')
formatted_privkey=$(echo "$PRIVKEY" | sed -e 's/-----BEGIN PRIVATE KEY-----/-----BEGIN PRIVATE KEY-----\n/' -e 's/-----END PRIVATE KEY-----/\n-----END PRIVATE KEY-----/')
echo "$formatted_privkey" > /etc/letsencrypt/live/droopy.mechanicalturk.one/privkey.pem
echo "$final_fullchain" > /etc/letsencrypt/live/droopy.mechanicalturk.one/fullchain.pem
# Configure Nginx
echo 'server {
    listen 80;
    server_name droopy.mechanicalturk.one;

    location / {
      return 301 https://$host$request_uri;
    }
  }
  server {
    listen 443 ssl;
    server_name droopy.mechanicalturk.one;

    ssl_certificate /etc/letsencrypt/live/droopy.mechanicalturk.one/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/droopy.mechanicalturk.one/privkey.pem;

    location /api {
      rewrite ^/api(/.*)$ $1 break;
      proxy_pass http://localhost:3014;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
    }
    location / {
      proxy_pass http://localhost:3007;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
    }
}' | sudo tee /etc/nginx/conf.d/default.conf
# Enable and start Nginx
sudo systemctl enable nginx
sudo systemctl start nginx || { echo 'Failed to start Nginx'; exit 1; }
# Install Node.js
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - &&\
sudo apt install -y nodejs || { echo 'Failed to install Node.js'; exit 1; }
# Install Puppeteer globally
sudo npm install puppeteer -g || { echo 'Failed to install Puppeteer'; exit 1; }
# Install Git
sudo apt install -y git || { echo 'Failed to install git'; exit 1; }
# Clone the repository and build the project
cd /home/ubuntu
git clone https://github.com/jmarren/drew-scraper.git || { echo 'Failed to clone repository'; exit 1; }
# Build and start the Next.js app
cd drew-scraper/nextjs
npm install || { echo 'Failed to install npm packages for Next.js'; exit 1; }
npm run build || { echo 'Failed to build Next.js app'; exit 1; }
echo "-------------- setting output to /var/log/nextjs-app -----------------"
nohup npm start > /var/log/nextjs-app.log 2>&1 &
sleep 5  # Adjust timing as necessary
if ! pgrep -f "npm start"; then
    echo 'Failed to start Next.js app'
    exit 1
fi
# Build and start the Express app
cd ../express
npm install || { echo 'Failed to install npm packages for Express'; exit 1; }
echo "-------------- setting output to /var/log/express-app -----------------"
nohup npm start > /var/log/express-app.log 2>&1 &
sleep 5  # Adjust timing as necessary
if ! pgrep -f "npm start"; then
    echo 'Failed to start Express app'
    exit 1
fi
# Test and restart Nginx
echo "-------------- Testing Nginx --------------"
sudo nginx -t || { echo 'Failed to test Nginx configuration'; exit 1; }
echo "-------------- Restarting Nginx --------------"
sudo systemctl restart nginx || { echo 'Failed to restart Nginx'; exit 1; }
EOF
}

resource "aws_security_group" "instance_sg" {
  name        = "allow_web_and_ssh"
  description = "Allow SSH inbound traffic"

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
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

