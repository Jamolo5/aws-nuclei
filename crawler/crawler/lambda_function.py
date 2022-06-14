import json
import boto3
import os
import json

sqsUrl = os.environ.get('sqsUrl')
sqsClient = boto3.client('sqs')

def lambda_handler(event, context):
    result = []
    result.extend(crawl_lambda())

    for url in result:
        sqsClient.send_message(
            QueueUrl=sqsUrl,
            MessageBody=json.dumps({
                "url" : url,
                "service" : "lambda"
            })
        )
    
    return {
        'statusCode': 200,
        'body': result
    }


# Crawl all lambdas for their aliases and all URL configs
# for the lambdas themselves and their aliases
def crawl_lambda():
    client = boto3.client('lambda')

    # Get list of functions
    # TODO: Deal with results pagination
    functionArnList = [function['FunctionArn'] for function in client.list_functions()['Functions']]

    # Get URLs from each function
    # TODO: Deal with results pagination
    urls = []
    for functionArn in functionArnList:
        try:
            urls = [function['FunctionUrl'] for function in client.list_function_url_configs(FunctionName=functionArn)['FunctionUrlConfigs']]
        except client.exceptions.ResourceNotFoundException:
            print('No URL configs found for lambda: ',functionArn)
    
    print('\n\nFunction URLs found:\n',urls,'\n\n')

    # Get all aliases for each function
    # TODO: Deal with results pagination
    aliases = dict()
    for functionArn in functionArnList:
        try:
            for alias in client.list_aliases(FunctionName=functionArn)['Aliases']:
                aliases[alias["Name"]] = functionArn
        except client.exceptions.ResourceNotFoundException:
            print('No aliases found for lambda: ',functionArn)
    print('\n\nList of aliases:\n', aliases,'\n\n')

    # Get URLs from each alias
    for aliasName, functionArn in aliases.items():
        try:
            urls.append(client.get_function_url_config(FunctionName=functionArn, Qualifier=aliasName)['FunctionUrl'])
        except client.exceptions.ResourceNotFoundException:
            print('No URL config found for alias: ',aliasName)
    return (urls)