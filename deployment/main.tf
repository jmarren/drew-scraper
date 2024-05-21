

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
  ami           = "ami-02404fb4d4dc3c0c7" # Example AMI ID, replace with a valid one for your region
  instance_type = "t4g.micro"
  key_name      = "thelambofjohn" # Ensure you have a key pair for SSH access

  iam_instance_profile = aws_iam_instance_profile.ec2_secrets_profile.name

  security_groups = [aws_security_group.instance_sg.name]

  tags = {
    Name = "droopy-instance"
  }

  user_data = <<-EOF
    #!/bin/bash
    # set -eo pipefail
    exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
    apt update -y
    apt install -y nginx unzip jq || { echo 'Failed to install packages'; exit 1; }
    curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip" || { echo 'Failed to download AWS CLI'; exit 1; }
    unzip awscliv2.zip || { echo 'Failed to unzip AWS CLI'; exit 1; }
    sudo ./aws/install || { echo 'Failed to install AWS CLI'; exit 1; }
    SECRET=$(aws secretsmanager get-secret-value --secret-id "droopy_ssl_cert" --region "us-west-1" --output json)
    FULLCHAIN=$(echo $SECRET | jq -r '.SecretString | fromjson.fullchain')
    PRIVKEY=$(echo $SECRET | jq -r '.SecretString | fromjson.privkey')
    mkdir -p /etc/letsencrypt/live/droopy.mechanicalturk.one
    formatted_fullchain=$(echo "$FULLCHAIN" | sed -e 's/-----END CERTIFICATE-----/\n-----END CERTIFICATE-----/' -e 's/-----BEGIN CERTIFICATE-----/-----BEGIN CERTIFICATE-----\n/')
    final_fullchain=$(echo "$formatted_fullchain" | sed 's/-----END CERTIFICATE----------BEGIN CERTIFICATE-----/-----END CERTIFICATE-----\n-----BEGIN CERTIFICATE-----/')
    formatted_privkey=$(echo "$PRIVKEY" | sed -e 's/-----BEGIN PRIVATE KEY-----/-----BEGIN PRIVATE KEY-----\n/' -e 's/-----END PRIVATE KEY-----/\n-----END PRIVATE KEY-----/')
    echo $formatted_privkey || { echo 'Failed to format certificates'; exit 1; }
    echo $final_fullchain || { echo 'Failed to format certificates'; exit 1; }
    echo "$formatted_privkey" > /etc/letsencrypt/live/droopy.mechanicalturk.one/privkey.pem
    echo "$final_fullchain" > /etc/letsencrypt/live/droopy.mechanicalturk.one/fullchain.pem
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
    sudo systemctl enable nginx
    sudo systemctl start nginx || { echo 'Failed to start Nginx'; exit 1; }
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - &&\
    sudo apt install -y nodejs|| { echo 'Failed to install Node.js'; exit 1; }
    apt install -y git || { echo 'Failed to install git'; exit 1; }
    cd /home/ubuntu
    git clone https://github.com/jmarren/drew-scraper.git || { echo 'Failed to clone repository'; exit 1; }
    cd drew-scraper/nextjs
    npm install || { echo 'Failed to install npm packages for Next.js'; exit 1; }
    npm run build || { echo 'Failed to build Next.js app'; exit 1; }
    nohup npm start > /dev/null 2>&1 &
    sleep 5  # Adjust timing as necessary
    if ! pgrep -f "npm start"; then
        echo 'Failed to start Next.js app'
        exit 1
    fi
    cd ../express
    npm install || { echo 'Failed to install npm packages for Express'; exit 1; }
    nohup npm start > /dev/null 2>&1 &
    sleep 5  # Adjust timing as necessary
    if ! pgrep -f "npm start"; then
        echo 'Failed to start Express app'
        exit 1
    fi
    sudo nginx -t || { echo 'Failed to test Nginx configuration'; exit 1; }
    sudo systemctl restart nginx
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

