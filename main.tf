terraform {
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "james-personal-account"

    workspaces {
      name = "aws-nuclei"
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

resource "aws_iam_policy" "sqs_publish_policy" {
  name        = "sqs_publish_policy"
  path        = "/"
  description = "Grants permission to publish to the crawled-urls SQS queue"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:Describe*",
        ]
        Effect   = "Allow"
        Resource = "${aws_sqs_queue.crawled-urls.arn}"
      },
    ]
  })
}

resource "aws_iam_role" "lambda_exec" {
  name = "serverless_lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Sid    = ""
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role" "crawler_role" {
  name = "crawler_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Sid    = ""
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "crawler_policy_attach_lambda_basic" {
  role       = aws_iam_role.crawler_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "crawler_policy_attach_readonly" {
  role       = aws_iam_role.crawler_role.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "crawler_policy_attach_sqs_publish" {
  role       = aws_iam_role.crawler_role.name
  policy_arn = aws_iam_policy.sqs_publish_policy.arn
}

resource "aws_iam_role" "scanner_role" {
  name = "scanner_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Sid    = ""
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "scanner_policy_attach_lambda_basic" {
  role       = aws_iam_role.scanner_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "scanner_policy_attach_sqs_execution" {
  role       = aws_iam_role.scanner_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"
}

resource "aws_cloudwatch_log_group" "test_lambda" {
  name = "/aws/lambda/${aws_lambda_function.test_lambda.function_name}"

  retention_in_days = 3
}

resource "aws_cloudwatch_log_group" "crawler" {
  name = "/aws/lambda/${aws_lambda_function.crawler.function_name}"

  retention_in_days = 3
}

resource "aws_lambda_function" "test_lambda" {
  filename      = "artifacts/hello_world_lambda.zip"
  function_name = "hello_world"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "lambda_function.lambda_handler"

  source_code_hash = filebase64sha256("artifacts/hello_world_lambda.zip")

  runtime = "python3.9"
}

resource "aws_lambda_function_url" "test_live" {
  # URL for the above Lambda
  function_name      = aws_lambda_function.test_lambda.function_name
  authorization_type = "AWS_IAM"
}

resource "aws_lambda_function" "crawler" {
  filename      = "artifacts/crawler_lambda.zip"
  function_name = "crawler"
  role          = aws_iam_role.crawler_role.arn
  handler       = "package.crawler.lambda_function.lambda_handler"
  timeout       = 10
  layers        = [aws_lambda_layer_version.boto3-layer.arn]

  source_code_hash = filebase64sha256("artifacts/crawler_lambda.zip")

  runtime = "python3.9"

  environment {
    variables = {
      sqsArn = aws_sqs_queue.crawled-urls.arn
    }
  }
}

resource "aws_lambda_layer_version" "boto3-layer" {
  filename   = "artifacts/boto3-layer.zip"
  layer_name = "boto3-layer"

  compatible_runtimes = ["python3.9"]
}

resource "aws_apigatewayv2_api" "lambda" {
  name          = "serverless_lambda_gw"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "lambda" {
  api_id = aws_apigatewayv2_api.lambda.id

  name        = "serverless_lambda_stage"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn

    format = jsonencode({
      requestId               = "$context.requestId"
      sourceIp                = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      protocol                = "$context.protocol"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
      }
    )
  }
}

resource "aws_apigatewayv2_integration" "test_lambda" {
  api_id = aws_apigatewayv2_api.lambda.id

  integration_uri    = aws_lambda_function.test_lambda.invoke_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "test_lambda" {
  api_id = aws_apigatewayv2_api.lambda.id

  route_key = "GET /hello"
  target    = "integrations/${aws_apigatewayv2_integration.test_lambda.id}"
}

resource "aws_cloudwatch_log_group" "api_gw" {
  name = "/aws/api_gw/${aws_apigatewayv2_api.lambda.name}"

  retention_in_days = 3
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.test_lambda.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.lambda.execution_arn}/*/*"
}

resource "aws_sqs_queue" "crawled-urls" {
  name = "crawled-urls"
  # delay_seconds             = 90
  max_message_size           = 2048
  message_retention_seconds  = 7200
  receive_wait_time_seconds  = 20
  visibility_timeout_seconds = 30
  # redrive_policy = jsonencode({
  #   deadLetterTargetArn = aws_sqs_queue.terraform_queue_deadletter.arn
  #   maxReceiveCount     = 4
  # })
  # redrive_allow_policy = jsonencode({
  #   redrivePermission = "byQueue",
  #   sourceQueueArns   = [aws_sqs_queue.terraform_queue_deadletter.arn]
  # })
}