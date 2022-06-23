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

resource "aws_default_vpc" "default" {}

resource "aws_default_subnet" "default_az1" {
  availability_zone = "us-west-2a"
}

resource "aws_default_subnet" "default_az2" {
  availability_zone = "us-west-2b"
}

resource "aws_subnet" "private_az1" {
  availability_zone = "us-west-2a"
  vpc_id            = aws_default_vpc.default.id
  cidr_block        = "172.31.64.0/27"
}

resource "aws_subnet" "private_az2" {
  availability_zone = "us-west-2b"
  vpc_id            = aws_default_vpc.default.id
  cidr_block        = "172.31.64.32/27"
}

resource "aws_db_subnet_group" "public" {
  name       = "public"
  subnet_ids = [aws_default_subnet.default_az1.id, aws_default_subnet.default_az2.id]

  tags = {
    Name = "My public DB subnet group"
  }
}

resource "aws_db_subnet_group" "private" {
  name       = "private"
  subnet_ids = [aws_subnet.private_az1.id, aws_subnet.private_az2.id]

  tags = {
    Name = "My private DB subnet group"
  }
}

resource "aws_eip" "natgw_eip" {
  vpc = true
}

resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.natgw_eip.id
  subnet_id     = aws_default_subnet.default_az1.id
  tags = {
    "Name" = "nat_gateway"
  }
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_default_vpc.default.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }
}

resource "aws_route_table_association" "subnet1_rt" {
  subnet_id      = aws_subnet.private_az1.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "subnet2_rt" {
  subnet_id      = aws_subnet.private_az2.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_default_security_group" "default" {
  vpc_id = aws_default_vpc.default.id

  ingress {
    protocol  = -1
    self      = true
    from_port = 0
    to_port   = 0
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_policy" "sqs_publish_policy" {
  name        = "sqs_publish_policy"
  path        = "/"
  description = "Grants permission to publish to the crawled_urls SQS queue"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sqs:SendMessage",
        ]
        Effect   = "Allow"
        Resource = "${aws_sqs_queue.crawled_urls.arn}"
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

resource "aws_iam_policy" "rds_connect_policy" {
  name        = "rds_connect_policy"
  path        = "/"
  description = "Grants permission to publish to the vuln_db RDS cluster"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "rds-db:connect",
        ]
        Effect   = "Allow"
        Resource = "arn:aws:rds-db:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:dbuser:*/${aws_rds_cluster.vuln_db_cluster.master_username}"
      },
    ]
  })
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

resource "aws_iam_role_policy_attachment" "scanner_policy_attach_vpc_access" {
  role       = aws_iam_role.scanner_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "scanner_policy_attach_efs_access" {
  role       = aws_iam_role.scanner_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonElasticFileSystemClientReadWriteAccess"
}

resource "aws_iam_role_policy_attachment" "scanner_policy_attach_rds_access" {
  role       = aws_iam_role.scanner_role.name
  policy_arn = aws_iam_policy.rds_connect_policy.arn
}

resource "aws_iam_role" "db_init_role" {
  name = "db_init_role"

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

resource "aws_iam_role_policy_attachment" "db_init_policy_attach_rds_access" {
  role       = aws_iam_role.db_init_role.name
  policy_arn = aws_iam_policy.rds_connect_policy.arn
}

resource "aws_iam_role_policy_attachment" "db_init_policy_attach_vpc_access" {
  role       = aws_iam_role.db_init_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "db_init_policy_attach_lambda_basic" {
  role       = aws_iam_role.db_init_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_cloudwatch_log_group" "test_lambda" {
  name = "/aws/lambda/${aws_lambda_function.test_lambda.function_name}"

  retention_in_days = 3
}

resource "aws_cloudwatch_log_group" "crawler" {
  name = "/aws/lambda/${aws_lambda_function.crawler.function_name}"

  retention_in_days = 3
}

resource "aws_cloudwatch_log_group" "scanner" {
  name = "/aws/lambda/${aws_lambda_function.scanner.function_name}"

  retention_in_days = 3
}

resource "aws_cloudwatch_log_group" "db_init" {
  name = "/aws/lambda/${aws_lambda_function.db_init.function_name}"

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
  authorization_type = "NONE"
}

resource "aws_lambda_function" "crawler" {
  filename      = "artifacts/crawler_lambda.zip"
  function_name = "crawler"
  role          = aws_iam_role.crawler_role.arn
  handler       = "crawler.lambda_function.lambda_handler"
  timeout       = 10
  layers        = [aws_lambda_layer_version.boto3_layer.arn]

  source_code_hash = filebase64sha256("artifacts/crawler_lambda.zip")

  runtime = "python3.9"

  environment {
    variables = {
      sqsUrl = aws_sqs_queue.crawled_urls.url
    }
  }
}

resource "aws_lambda_layer_version" "boto3_layer" {
  filename   = "artifacts/boto3_layer.zip"
  layer_name = "boto3_layer"

  compatible_runtimes = ["python3.9"]
}

resource "aws_lambda_function" "scanner" {
  filename      = "artifacts/scanner_lambda.zip"
  function_name = "scanner"
  role          = aws_iam_role.scanner_role.arn
  handler       = "scanner.lambda_function.lambda_handler"
  timeout       = 300
  memory_size   = 1028
  layers        = [aws_lambda_layer_version.boto3_layer.arn]
  vpc_config {
    security_group_ids = [aws_default_security_group.default.id]
    subnet_ids         = [aws_subnet.private_az1.id, aws_subnet.private_az2.id]
  }
  file_system_config {
    arn              = aws_efs_access_point.nuclei_efs_access_point.arn
    local_mount_path = "/mnt/nuclei"
  }

  source_code_hash = filebase64sha256("artifacts/scanner_lambda.zip")

  runtime = "python3.9"

  environment {
    variables = {
      APP_DB_NAME = aws_rds_cluster.vuln_db_cluster.database_name
      DB_HOST     = aws_rds_cluster.vuln_db_cluster.endpoint
      DB_USER     = aws_rds_cluster.vuln_db_cluster.master_username
      HOME        = "/tmp/"
      sqsUrl      = aws_sqs_queue.crawled_urls.url
      mountPath   = "/mnt/nuclei"
      nucleiUrl   = "https://github.com/projectdiscovery/nuclei/releases/download/v2.7.2/nuclei_2.7.2_linux_amd64.zip"
    }
  }

  depends_on = [
    aws_efs_mount_target.nuclei_efs_mount_target1,
    aws_efs_mount_target.nuclei_efs_mount_target2
  ]
}

resource "aws_lambda_function" "db_init" {
  filename      = "artifacts/db_init.zip"
  function_name = "db_init"
  role          = aws_iam_role.db_init_role.arn
  handler       = "db_init.lambda_function.lambda_handler"
  timeout       = 300
  layers        = [aws_lambda_layer_version.boto3_layer.arn]
  vpc_config {
    security_group_ids = [aws_default_security_group.default.id]
    subnet_ids         = [aws_subnet.private_az1.id, aws_subnet.private_az2.id]
  }

  source_code_hash = filebase64sha256("artifacts/db_init.zip")

  runtime = "python3.9"

  environment {
    variables = {
      APP_DB_NAME = aws_rds_cluster.vuln_db_cluster.database_name
      DB_HOST     = aws_rds_cluster.vuln_db_cluster.endpoint
      DB_USER     = aws_rds_cluster.vuln_db_cluster.master_username
    }
  }
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

resource "aws_sqs_queue" "crawled_urls" {
  name = "crawled_urls"
  # delay_seconds             = 90
  max_message_size           = 2048
  message_retention_seconds  = 7200
  receive_wait_time_seconds  = 20
  visibility_timeout_seconds = 305
  # redrive_policy = jsonencode({
  #   deadLetterTargetArn = aws_sqs_queue.terraform_queue_deadletter.arn
  #   maxReceiveCount     = 4
  # })
  # redrive_allow_policy = jsonencode({
  #   redrivePermission = "byQueue",
  #   sourceQueueArns   = [aws_sqs_queue.terraform_queue_deadletter.arn]
  # })
}

resource "aws_lambda_event_source_mapping" "example" {
  event_source_arn = aws_sqs_queue.crawled_urls.arn
  function_name    = aws_lambda_function.scanner.arn
}

resource "aws_efs_file_system" "nuclei_efs" {}

resource "aws_efs_mount_target" "nuclei_efs_mount_target1" {
  file_system_id  = aws_efs_file_system.nuclei_efs.id
  subnet_id       = aws_subnet.private_az1.id
  security_groups = [aws_default_security_group.default.id]
}

resource "aws_efs_mount_target" "nuclei_efs_mount_target2" {
  file_system_id  = aws_efs_file_system.nuclei_efs.id
  subnet_id       = aws_subnet.private_az2.id
  security_groups = [aws_default_security_group.default.id]
}

resource "aws_efs_access_point" "nuclei_efs_access_point" {
  file_system_id = aws_efs_file_system.nuclei_efs.id

  posix_user {
    gid = 1000
    uid = 1000
  }

  root_directory {
    path = "/lambda"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "0777"
    }
  }
}

resource "aws_rds_cluster" "vuln_db_cluster" {
  cluster_identifier                  = "vuln-db-cluster"
  engine                              = "aurora-mysql"
  engine_mode                         = "provisioned"
  engine_version                      = "8.0.mysql_aurora.3.02.0"
  database_name                       = "vuln_db"
  master_username                     = "test"
  master_password                     = "must_be_eight_characters"
  skip_final_snapshot                 = true
  backup_retention_period             = 0
  apply_immediately                   = true
  iam_database_authentication_enabled = true
  db_subnet_group_name                = aws_db_subnet_group.private.id

  serverlessv2_scaling_configuration {
    max_capacity = 1.0
    min_capacity = 0.5
  }
}

resource "aws_rds_cluster_instance" "vuln_db_instance" {
  cluster_identifier   = aws_rds_cluster.vuln_db_cluster.id
  instance_class       = "db.serverless"
  engine               = aws_rds_cluster.vuln_db_cluster.engine
  engine_version       = aws_rds_cluster.vuln_db_cluster.engine_version
  db_subnet_group_name = aws_db_subnet_group.private.id
}

resource "aws_lambda_invocation" "db_init" {
  function_name = aws_lambda_function.db_init.function_name
  depends_on = [
    aws_rds_cluster.vuln_db_cluster,
    aws_rds_cluster_instance.vuln_db_instance,
    aws_lambda_function.db_init
  ]
  input = jsonencode({
    key1 = "value1"
  })
}