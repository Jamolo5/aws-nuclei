import boto3

def lambda_handler(event, context):
    # TODO implement db table creation
    print("Initialising Database")
    return {
        'statusCode': 200,
        'body': "Hello"
    }