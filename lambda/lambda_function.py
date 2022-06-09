import boto3

def lambda_handler(event, context):
    # TODO implement
    result = "Hello World!"
    return {
        'statusCode': 200,
        'body': result
    }