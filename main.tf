terraform {
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "james-personal-account"

    workspaces {
      prefix = "aws-nuclei"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "us-west-2"
}

resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_lambda_function" "test_lambda" {
  # If the file is not in the current working directory you will need to include a 
  # path.module in the filename.
  filename      = "artifacts/lambda_function_payload.zip"
  function_name = "hello_world"
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "hello.lambda_handler"

  source_code_hash = filebase64sha256("artifacts/lambda_function_payload.zip")

  runtime = "python3.9"

  environment {
    variables = {
      foo = "bar"
    }
  }
}