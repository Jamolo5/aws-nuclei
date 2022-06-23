import boto3
import os
import pymysql.cursors
import base64
from botocore.exceptions import ClientError

connection = None
def get_connection():
    try:
        print("Connecting to database")
        client = boto3.client("rds")
        DBEndPoint = os.environ.get("DB_HOST")
        DBUserName = os.environ.get("DB_USER", "test")
        DBName = os.environ.get("APP_DB_NAME")
        password = client.generate_db_auth_token(
            DBHostname=DBEndPoint, Port=5432, DBUsername = DBUserName
        )
        conn = pymysql.connect(
            host=DBEndPoint,
            user=DBUserName,
            password=password,
            database=DBName,
            charset='utf8mb4',
            ssl_ca='rds-ca-2019-root.pem',
            ssl_verify_cert=True
        )
        return conn
    except Exception as e:
        print("While connecting failed due to :{0}".format(str(e)))
        return None

# Sample code straight from AWS
def get_secret():

    secret_name = "arn:aws:secretsmanager:us-west-2:847035122536:secret:vuln_db_creds-scYaoD"
    region_name = "us-west-2"

    # Create a Secrets Manager client
    session = boto3.session.Session()
    client = session.client(
        service_name='secretsmanager',
        region_name=region_name
    )

    # In this sample we only handle the specific exceptions for the 'GetSecretValue' API.
    # See https://docs.aws.amazon.com/secretsmanager/latest/apireference/API_GetSecretValue.html
    # We rethrow the exception by default.

    try:
        get_secret_value_response = client.get_secret_value(
            SecretId=secret_name
        )
    except ClientError as e:
        if e.response['Error']['Code'] == 'DecryptionFailureException':
            # Secrets Manager can't decrypt the protected secret text using the provided KMS key.
            # Deal with the exception here, and/or rethrow at your discretion.
            raise e
        elif e.response['Error']['Code'] == 'InternalServiceErrorException':
            # An error occurred on the server side.
            # Deal with the exception here, and/or rethrow at your discretion.
            raise e
        elif e.response['Error']['Code'] == 'InvalidParameterException':
            # You provided an invalid value for a parameter.
            # Deal with the exception here, and/or rethrow at your discretion.
            raise e
        elif e.response['Error']['Code'] == 'InvalidRequestException':
            # You provided a parameter value that is not valid for the current state of the resource.
            # Deal with the exception here, and/or rethrow at your discretion.
            raise e
        elif e.response['Error']['Code'] == 'ResourceNotFoundException':
            # We can't find the resource that you asked for.
            # Deal with the exception here, and/or rethrow at your discretion.
            raise e
    else:
        # Decrypts secret using the associated KMS key.
        # Depending on whether the secret is a string or binary, one of these fields will be populated.
        if 'SecretString' in get_secret_value_response:
            return get_secret_value_response['SecretString']
        else:
            return base64.b64decode(get_secret_value_response['SecretBinary'])

def lambda_handler(event, context):
    print("Initialising Database")
    global connection
    TableName = os.environ.get("APP_DB_NAME")
    try:
        if connection is None:
            print("No existing connection, connecting..")
            connection = get_connection()
        if connection is None:
            print("Connection could not be established, aborting")
            return {"status": "Error", "message": "Failed"}
        print("instantiating the cursor from connection")
        with connection:
            with connection.cursor() as cursor:
                cursor.execute("CREATE TYPE severity AS ENUM('info', 'low', 'medium', 'high', 'critical', 'unknown')")
                query = "CREATE TABLE {0} (id SERIAL, timestamp_of_discovery timestamptz, severity severity, cve_or_name text, url text, additional_info text)".format(TableName)
                print("Query:\n"+query)
                cursor.execute(query)
            connection.commit()
            with connection.cursor() as cursor:
                results = cursor.fetchall()
                print("Results:")
                results = []
                for row in results:
                    results.append(row)
                    print(row)
                # retry = False
                response = {"status": "Success", "results": str(results)}
                return response
    except Exception as e:
        try:
            connection.close()
        except Exception as e:
            connection = None
        print("Failed due to :{0}".format(str(e)))