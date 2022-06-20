output "function_name" {
  description = "Name of the Lambda function."

  value = aws_lambda_function.test_lambda.function_name
}

output "base_url" {
  description = "Base URL for API Gateway stage."

  value = aws_apigatewayv2_stage.lambda.invoke_url
}

output "rds_arn" {
  description = "full ARN/username for rds cluster"

  value = "${aws_rds_cluster.vuln_db_cluster.arn}/${aws_rds_cluster.vuln_db_cluster.master_username}"
}