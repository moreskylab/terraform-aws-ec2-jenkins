provider "aws" {
  region = "ap-south-1"
}

# Create a VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "tf-jenkins-main-vpc"
  }
}

# Create a public subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "ap-south-1a"

  tags = {
    Name = "tf-jenkins-public-subnet"
  }
}

# Create an internet gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "tf-jenkins-main-igw"
  }
}

# Create a route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "tf-jenkins-public-rt"
  }
}

# Associate route table with subnet
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Create a security group
resource "aws_security_group" "web" {
  name        = "tf-jenkins-web-sg"
  description = "Allow web traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # In production, restrict this to your IP
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Generate a random suffix for global uniqueness
resource "random_id" "suffix" {
  byte_length = 4
}

# Create an S3 bucket for logs
resource "aws_s3_bucket" "logs" {
  bucket = "tf-jenkins-server-logs-${random_id.suffix.hex}"
  force_destroy = true

  tags = {
    Name = "tf-jenkins-server-logs"
  }
}

# Block public access to the bucket
resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Create an S3 bucket for Jenkins backups
resource "aws_s3_bucket" "jenkins_backup" {
  bucket = "tf-jenkins-backup-${random_id.suffix.hex}"
  force_destroy = true

  tags = {
    Name = "tf-jenkins-backup"
  }
}

# Block public access to the backup bucket
resource "aws_s3_bucket_public_access_block" "jenkins_backup" {
  bucket = aws_s3_bucket.jenkins_backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning for backup bucket
resource "aws_s3_bucket_versioning" "jenkins_backup" {
  bucket = aws_s3_bucket.jenkins_backup.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Lifecycle configuration for backup retention
resource "aws_s3_bucket_lifecycle_configuration" "jenkins_backup" {
  bucket = aws_s3_bucket.jenkins_backup.id

  rule {
    id     = "backup_retention"
    status = "Enabled"

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# Create the IAM Policy Document (MERGED - includes both logs and backup bucket access)
data "aws_iam_policy_document" "ec2_s3_upload_policy" {
  statement {
    sid = "AllowEC2ToUploadLogs"
    actions = [
      "s3:PutObject",
    ]
    resources = [
      "${aws_s3_bucket.logs.arn}/*",
    ]
  }

  statement {
    sid = "AllowEC2ToListBucket"
    actions = [
      "s3:ListBucket",
    ]
    resources = [
      "${aws_s3_bucket.logs.arn}",
    ]
  }

  statement {
    sid = "AllowJenkinsBackupAccess"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      "${aws_s3_bucket.jenkins_backup.arn}",
      "${aws_s3_bucket.jenkins_backup.arn}/*"
    ]
  }
}

# Create the IAM Policy
resource "aws_iam_policy" "ec2_s3_upload_policy" {
  name   = "EC2S3UploadLogsPolicy" # Give your policy a descriptive name
  policy = data.aws_iam_policy_document.ec2_s3_upload_policy.json
}

# Create an IAM Role and Attach the Policy
resource "aws_iam_role" "ec2_s3_uploader_role" {
  name = "EC2S3UploaderRole" # Give your role a descriptive name

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ec2_s3_upload_attachment" {
  role       = aws_iam_role.ec2_s3_uploader_role.name
  policy_arn = aws_iam_policy.ec2_s3_upload_policy.arn
}

# Create an IAM Instance Profile (If attaching to an existing EC2 instance)
resource "aws_iam_instance_profile" "ec2_s3_uploader_profile" {
  name = "EC2S3UploaderProfile"
  role = aws_iam_role.ec2_s3_uploader_role.name
}

# Try to find existing Elastic IP by tag (handle case when none exists)
data "aws_eips" "existing" {
  filter {
    name   = "tag:Name"
    values = ["tf-jenkins-server-eip"]
  }
}

# Check if existing EIP was found
locals {
  existing_eip_found = length(data.aws_eips.existing.allocation_ids) > 0
  eip_allocation_id  = local.existing_eip_found ? data.aws_eips.existing.allocation_ids[0] : aws_eip.web[0].id
}

# Get details of existing EIP if found
data "aws_eip" "existing_details" {
  count = local.existing_eip_found ? 1 : 0
  id    = data.aws_eips.existing.allocation_ids[0]
}

# Create a new Elastic IP only if not found
resource "aws_eip" "web" {
  count  = local.existing_eip_found ? 0 : 1
  domain = "vpc"

  tags = {
    Name = "tf-jenkins-server-eip"
  }

  depends_on = [aws_internet_gateway.igw]

 lifecycle {
   prevent_destroy = true
   ignore_changes = [
     tags,
   ]
 }
}

# Create an EC2 instance (MERGED - single instance definition)
resource "aws_instance" "web" {
  iam_instance_profile   = aws_iam_instance_profile.ec2_s3_uploader_profile.name
  ami                    = "ami-0f918f7e67a3323f0"
  instance_type          = "t3.medium"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]
  key_name               = "ap-south-1"
  user_data = base64encode(templatefile("${path.module}/jenkins-setup.sh", {
    backup_bucket = aws_s3_bucket.jenkins_backup.bucket
  }))

  root_block_device {
    volume_type = "gp3"
    volume_size = 50
    encrypted   = true
    delete_on_termination = true
  }

  tags = {
    Name = "tf-jenkins-server"
  }
}

# Associate Elastic IP with EC2 instance
resource "aws_eip_association" "web" {
  instance_id   = aws_instance.web.id
  allocation_id = local.eip_allocation_id
}

# Output the web server's public IP (from either new or existing EIP)
output "web_server_public_ip" {
  description = "Elastic IP address of the web server"
  value       = local.existing_eip_found ? data.aws_eip.existing_details[0].public_ip : aws_eip.web[0].public_ip
}

output "web_server_eip_allocation_id" {
  description = "Allocation ID of the Elastic IP"
  value       = local.eip_allocation_id
}

# Output the S3 bucket name
output "logs_bucket" {
  value = aws_s3_bucket.logs.bucket
}

# Output the backup bucket name
output "jenkins_backup_bucket" {
  description = "S3 bucket for Jenkins backups"
  value       = aws_s3_bucket.jenkins_backup.bucket
}

# Output backup commands
output "backup_commands" {
  description = "Commands to manage Jenkins backups"
  value = {
    manual_backup = "sudo /opt/jenkins-backup/backup-jenkins.sh ${aws_s3_bucket.jenkins_backup.bucket}"
    list_backups  = "/opt/jenkins-backup/list-backups.sh ${aws_s3_bucket.jenkins_backup.bucket}"
    restore_example = "sudo /opt/jenkins-backup/restore-jenkins.sh ${aws_s3_bucket.jenkins_backup.bucket} jenkins-backup-YYYYMMDD_HHMMSS.tar.gz"
  }
}