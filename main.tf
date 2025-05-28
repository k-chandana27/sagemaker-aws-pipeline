

resource "aws_vpc" "main" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "${var.project_name}-main"
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name ="${var.project_name}-public-subnet"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${var.project_name}-public-rt"
  }
}


resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id
}

resource "aws_route_table_association" "public_subnet_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_security_group" "sagemaker_sg" {
  name        = "${var.project_name}-sagemaker-sg"
  description = "Allow inbound traffic for SageMaker Notebook"
  vpc_id      = aws_vpc.main.id

  ingress {
    description      = "SSH inbound"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sagemaker-sg"
  }
}


resource "random_id" "bucket_id" {
  byte_length = 4
}

resource "aws_s3_bucket" "logs_bucket" {
  bucket = "${var.project_name}"
  acl    = "private"
  force_destroy = true

  tags = {
    Name        = "${var.project_name}-logs"
    Environment = "POC"
  }
}

resource "aws_s3_bucket_public_access_block" "logs_bucket_block" {
  bucket = aws_s3_bucket.logs_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_role" "sagemaker_execution_role" {
  name               = "${var.project_name}-execution-role"
  assume_role_policy = data.aws_iam_policy_document.sagemaker_assume_role_policy.json
}

data "aws_iam_policy_document" "sagemaker_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["sagemaker.amazonaws.com"]
    }
  }
}


resource "aws_iam_role_policy_attachment" "sagemaker_attach_policy_amazon_sagemaker_fullaccess" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
  role       = aws_iam_role.sagemaker_execution_role.name
}

resource "aws_iam_role_policy_attachment" "sagemaker_attach_policy_amazon_s3_fullaccess" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  role       = aws_iam_role.sagemaker_execution_role.name
}

resource "aws_iam_role_policy_attachment" "sagemaker_attach_policy_cloudwatch_logs" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
  role       = aws_iam_role.sagemaker_execution_role.name
}

resource "aws_sagemaker_notebook_instance" "poc_notebook" {
  name                = "${var.project_name}-notebook"
  instance_type       = "ml.t2.medium"
  role_arn            = aws_iam_role.sagemaker_execution_role.arn
  subnet_id           = aws_subnet.public_subnet.id
  security_groups  = [aws_security_group.sagemaker_sg.id]

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project_name}-notebook"
  }
}