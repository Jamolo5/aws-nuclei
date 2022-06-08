import boto3

def lambda_handler(event, context):
    # TODO implement
    result = "Hellow World!"
    return {
        'statusCode': 200,
        'body': result
    }