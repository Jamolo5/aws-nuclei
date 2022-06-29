import json
import boto3
import os
import io
import urllib.request
import zipfile
import subprocess
import re
import pymysql
import base64
from botocore.exceptions import ClientError
from os.path import exists

sqsUrl = os.environ.get('sqsUrl')
mountPath = os.environ.get('mountPath')
nucleiBinaryPath = mountPath+"/nuclei"
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
        print("Error:\n")
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

def install_nuclei():
    print("Downloading nuclei to EFS as it is not already present")
    nucleiUrl = os.environ.get('nucleiUrl')
    zipPath = mountPath + "/nuclei.zip"
    urllib.request.urlretrieve(nucleiUrl, filename = zipPath)
    print("Nuclei Downloaded")
    with zipfile.ZipFile(zipPath,"r") as zip_ref:
        zip_ref.extractall(mountPath)
    os.system("chmod 754 "+nucleiBinaryPath)
    print("Nuclei installed")

def add_to_db(results):
    print("Adding results to DB")
    global connection
    try:
        if connection is None:
            print("No existing DB connection, connecting..")
            connection = get_connection()
        if connection is None:
            print("Connection to DB could not be established, aborting")
            return {"status": "Error", "message": "Failed"}
        with connection:
            with connection.cursor() as cursor:
                for result in results:
                    query = "INSERT INTO vuln_db (timestamp_of_discovery, severity, cve_or_name, category, url, additional_info) VALUES ({ts}, {sev}, {name}, {category}, {url}, {info})".format(
                        ts = result[1],
                        sev = result[4],
                        category = result[3],
                        name = result[2],
                        url = result[0],
                        info = '' if result.len() == 5 else result[5]
                    )
                    print("Query:\n"+query)
                    cursor.execute(query)
                results = cursor.fetchall()
                print("Query Results:")
                results = []
                for row in results:
                    results.append(row)
                    print(row)
            connection.commit()
    except Exception as e:
        print("Failed adding to DB due to :{0}".format(str(e)))
        try:
            connection.close()
        except Exception as e:
            connection = None
            print("Failed to close DB connection due to :{0}".format(str(e)))
        raise e

def lambda_handler(event, context):
    print("Checking if Nuclei is installed")
    if not exists(nucleiBinaryPath):
        install_nuclei()
    print("Received event: "+json.dumps(event))
    targets = []
    if "Records" in event:
        targets.extend([json.loads(record["body"]) for record in event["Records"]])
    else:
        print("No records found in event:"+json.dumps(event))
    print("Targets to scan:")
    print(targets)
    results = []
    for target in targets:
        print("Scanning beginning for URL:\n"+target["url"])
        args = (nucleiBinaryPath, "-u", target["url"], "-silent", "-nc")
        popen = subprocess.Popen(args, stdout=subprocess.PIPE)
        popen.wait()
        print("Scanned completed for URL:\n"+target["url"])
        print("Scan results:")
        popen.wait()
        for line in io.TextIOWrapper(popen.stdout, encoding="utf-8"):
            print(line)
            result = [target["url"]]
            result.append(re.findall('\[(.*?)\]', line))
            results.append(result)
    print("Scan results:")
    print(results)
    return add_to_db(results)