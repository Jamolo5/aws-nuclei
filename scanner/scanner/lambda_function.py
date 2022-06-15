import json
import boto3
import os
import urllib.request
import zipfile
import subprocess
from os.path import exists

sqsUrl = os.environ.get('sqsUrl')
mountPath = os.environ.get('mountPath')

# Get the nuclei binary if it doesn't already exist
if not exists(mountPath+"/nuclei"):
    print("Downloading nuclei to EFS as it is not already present")
    nucleiUrl = os.environ.get('nucleiUrl')
    zipPath = nucleiUrl + "/nuclei.zip"
    urllib.request.urlretrieve(nucleiUrl, zipPath)
    with zipfile.ZipFile(zipPath,"r") as zip_ref:
        zip_ref.extractall(mountPath)

sqsClient = boto3.client('sqs')

def lambda_handler(event, context):
    targets = []
    if "Records" in event:
        targets.append([record["body"] for record in event["Records"]])
    else:
        print("No records found in event")
    # results = []
    for target in targets:
        args = (mountPath+"/nuclei", "-u", target["url"], "-silent", "-nc")
        popen = subprocess.Popen(args, stdout=subprocess.PIPE)
        popen.wait()
        output = popen.stdout.read()
        print("Scanned URL:\n"+target["url"])
        print("Scan result:\n"+output)
    return {
        'statusCode': 200,
        'body': json.dumps(event)
    }