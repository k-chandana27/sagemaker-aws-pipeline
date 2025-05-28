# GitHub connection for CodePipeline
resource "aws_codestarconnections_connection" "github" {
  name          = "${var.project_name}-gh-conn"
  provider_type = "GitHub"
}

# S3 bucket for CodePipeline artifacts
resource "aws_s3_bucket" "codepipeline_bucket" {
  bucket = "${var.project_name}-pipeline-${random_id.bucket_id.hex}"
  force_destroy = true
  tags = {
    Name = "${var.project_name}-pipeline-bucket"
  }
}

resource "aws_s3_bucket_public_access_block" "codepipeline_bucket_block" {
  bucket = aws_s3_bucket.codepipeline_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM role for CodePipeline
resource "aws_iam_role" "codepipeline_role" {
  name = "${var.project_name}-codepipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codepipeline.amazonaws.com"
        }
      }
    ]
  })
}

# Policy for CodePipeline role
resource "aws_iam_policy" "codepipeline_policy" {
  name = "${var.project_name}-codepipeline-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:GetBucketVersioning"
        ]
        Effect = "Allow"
        Resource = [
          aws_s3_bucket.codepipeline_bucket.arn,
          "${aws_s3_bucket.codepipeline_bucket.arn}/*",
          aws_s3_bucket.logs_bucket.arn,
          "${aws_s3_bucket.logs_bucket.arn}/*"
        ]
      },
      {
        Action = [
          "codestar-connections:UseConnection"
        ]
        Effect   = "Allow"
        Resource = aws_codestarconnections_connection.github.arn
      },
      {
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# Attach policy to CodePipeline role
resource "aws_iam_role_policy_attachment" "codepipeline_policy_attachment" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = aws_iam_policy.codepipeline_policy.arn
}

# IAM role for CodeBuild
resource "aws_iam_role" "codebuild_role" {
  name = "${var.project_name}-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
      }
    ]
  })
}

# Policy for CodeBuild role
resource "aws_iam_policy" "codebuild_policy" {
  name = "${var.project_name}-codebuild-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:CreateBucket", # Add this permission
          "s3:ListBucket"
        ]
        Effect = "Allow"
        Resource = [
          aws_s3_bucket.codepipeline_bucket.arn,
          "${aws_s3_bucket.codepipeline_bucket.arn}/*",
          aws_s3_bucket.logs_bucket.arn,
          "${aws_s3_bucket.logs_bucket.arn}/*",
          "arn:aws:s3:::sagemaker-*" # Allow access to SageMaker default buckets
        ]
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "logs:GetLogEvents"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = [
         "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:CreateBucket",
          "s3:ListBucket"
        ]
        Effect = "Allow"
        Resource = [
          aws_s3_bucket.codepipeline_bucket.arn,
          "${aws_s3_bucket.codepipeline_bucket.arn}/*",
          aws_s3_bucket.logs_bucket.arn,
          "${aws_s3_bucket.logs_bucket.arn}/*",
          "arn:aws:s3:::sagemaker-*",
          "arn:aws:s3:::sagemaker-*/*"
        ]
      },
      {
        Action = [
          "sagemaker:CreateTrainingJob",
          "sagemaker:DescribeTrainingJob",
          "sagemaker:CreateModel",
          "sagemaker:CreateEndpointConfig",
          "sagemaker:CreateEndpoint",
          "sagemaker:DescribeEndpoint",
          "sagemaker:UpdateEndpoint",
          "sagemaker:DeleteEndpoint",
          "sagemaker:DeleteEndpointConfig",
          "sagemaker:DeleteModel"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "iam:PassRole"
        ]
        Effect   = "Allow"
        Resource = aws_iam_role.sagemaker_execution_role.arn
      }
    ]
  })
}

# Attach policies to CodeBuild role
resource "aws_iam_role_policy_attachment" "codebuild_policy_attachment" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = aws_iam_policy.codebuild_policy.arn
}

# CodeBuild project for SageMaker model training and deployment
resource "aws_codebuild_project" "sagemaker_build" {
  name         = "${var.project_name}-sagemaker-build"
  description  = "CodeBuild project for SageMaker model training and deployment"
  service_role = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    type            = "LINUX_CONTAINER"
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/amazonlinux2-x86_64-standard:3.0"
    privileged_mode = true

    environment_variable {
      name  = "BUCKET_NAME"
      value = aws_s3_bucket.logs_bucket.bucket
    }

    environment_variable {
      name  = "EXECUTION_ROLE_ARN"
      value = aws_iam_role.sagemaker_execution_role.arn
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = <<EOF
version: 0.2

phases:
  install:
    runtime-versions:
      python: 3.8
    commands:
      - pip install boto3 pandas scikit-learn sagemaker

  build:
    commands:
      # Copy the CSV file to S3
      - aws s3 cp error_logs.csv s3://$BUCKET_NAME/data/error_logs.csv
      - |
        sed -i "s/role=sagemaker.get_execution_role()/role=os.environ.get('EXECUTION_ROLE_ARN')/g" train_and_deploy.py
        sed -i "s/endpoint_name=\"logs-error-endpoint\"/endpoint_name=\"logs-error-endpoint-$(date +%Y%m%d%H%M%S)\"/g" train_and_deploy.py
      # Run the existing script from the repository
      - python train_and_deploy.py
      
  post_build:
    commands:
      - echo "SageMaker model training and deployment completed"

artifacts:
  files:
    - error_logs.csv
    - train_and_deploy.py
    - train_script.py
  discard-paths: no
EOF
  }
}

# CodePipeline for the end-to-end workflow
resource "aws_codepipeline" "sagemaker_pipeline" {
  name     = "${var.project_name}-sagemaker-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.codepipeline_bucket.bucket
    type     = "S3"
  }

  # In your aws_codepipeline.sagemaker_pipeline resource, modify the Source stage:

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn        = aws_codestarconnections_connection.github.arn
        FullRepositoryId     = var.github_repo_name
        BranchName           = var.github_branch
        OutputArtifactFormat = "CODE_ZIP"
        # Remove the FilterPatterns configuration that was causing the error
      }
    }
  }

  stage {
    name = "Build"

    action {
      name            = "BuildAndDeploy"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["source_output"]

      configuration = {
        ProjectName = aws_codebuild_project.sagemaker_build.name
      }
    }
  }
}
