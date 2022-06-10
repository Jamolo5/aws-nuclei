import boto3

def lambda_handler(event, context):
    # TODO implement
    result = "Hello World!"
    if 'Name' in event.queryStringParameters:
        result = 'Hello, ' + event.queryStringParameters['Name'] + '!'
    
    return {
        'statusCode': 200,
        'body': result
    }