import json
import boto3
import os
import io
import urllib.request
import zipfile
import subprocess
from os.path import exists

sqsUrl = os.environ.get('sqsUrl')
mountPath = os.environ.get('mountPath')
nucleiBinaryPath = mountPath+"/nuclei"

# Get the nuclei binary if it doesn't already exist
if not exists(nucleiBinaryPath):
    print("Downloading nuclei to EFS as it is not already present")
    nucleiUrl = os.environ.get('nucleiUrl')
    zipPath = mountPath + "/nuclei.zip"
    urllib.request.urlretrieve(nucleiUrl, filename = zipPath)
    print("Nuclei Downloaded")
    with zipfile.ZipFile(zipPath,"r") as zip_ref:
        zip_ref.extractall(mountPath)
    os.system("chmod 754 "+nucleiBinaryPath)
    print("Nuclei installed")

def lambda_handler(event, context):
    targets = []
    if "Records" in event:
        targets.extend([record["body"] for record in event["Records"]])
    else:
        print("No records found in event:"+json.dumps(event))
    # results = []
    for target in targets:
        print("Scanning URL:\n"+target["url"])
        args = (nucleiBinaryPath, "-u", target["url"], "-silent", "-nc")
        popen = subprocess.Popen(args, stdout=subprocess.PIPE)
        popen.wait()
        print("Scanned URL:\n"+target["url"])
        print("Scan result:")
        popen.wait()
        for line in io.TextIOWrapper(popen.stdout, encoding="utf-8"):
            print(line)
    return {
        'statusCode': 200
    }