import boto3
import os
import pymysql
import base64
from botocore.exceptions import ClientError

connection = None
def get_connection():
    try:
        print("Connecting to database")
        DBEndPoint = os.environ.get("DB_HOST")
        DBUserName = os.environ.get("DB_USER", "test")
        DBName = os.environ.get("APP_DB_NAME")
        password = get_password()
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
def get_password():
    print("Fetching DB password")
    secret_name = os.environ.get("APP_DB_PW")
    region_name = os.environ.get("APP_REGION")

    # Create a Secrets Manager client
    session = boto3.session.Session()
    client = session.client(
        service_name='secretsmanager',
        region_name=region_name
    )
    print("Secrets manager client created")
    # In this sample we only handle the specific exceptions for the 'GetSecretValue' API.
    # See https://docs.aws.amazon.com/secretsmanager/latest/apireference/API_GetSecretValue.html
    # We rethrow the exception by default.

    try:
        print("Attempting to fetch secret from client")
        get_secret_value_response = client.get_secret_value(
            SecretId=secret_name
        )
    except ClientError as e:
        print("Error:")
        print(e)
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
        print("Returning Secret")
        if 'SecretString' in get_secret_value_response:
            return get_secret_value_response['SecretString']
        else:
            return base64.b64decode(get_secret_value_response['SecretBinary'])

def lambda_handler(event, context):
    global connection
    TableName = os.environ.get("APP_DB_NAME")
    try:
        if connection is None:
            print("No existing DB connection, connecting..")
            connection = get_connection()
        if connection is None:
            print("Connection to DB could not be established, aborting")
            return {"status": "Error", "message": "Failed"}
        print("instantiating the cursor from connection")
        response = ""
        with connection:
            with connection.cursor() as cursor:
                # query = "SELECT * FROM vuln_db"
                query = "DROP TABLE IF EXISTS {0}".format(TableName)
                print("Query:\n"+query)
                cursor.execute(query)
                query = "CREATE TABLE {0} (id INT PRIMARY KEY AUTO_INCREMENT, timestamp_of_discovery TIMESTAMP, severity ENUM('info', 'low', 'medium', 'high', 'critical', 'unknown'), cve_or_name varchar(255), category varchar(255), url varchar(255), additional_info varchar(255))".format(TableName)
                print("Query:\n"+query)
                cursor.execute(query)
                results = cursor.fetchall()
                print("Results:")
                for row in results:
                    print(row)
                # retry = False
                response = {"status": "Success"}
            connection.commit()
        return response
    except Exception as e:
        print("Failed due to :{0}".format(str(e)))
        try:
            connection.close()
        except Exception as e:
            connection = None