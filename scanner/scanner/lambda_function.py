import json
import boto3
import os
import io
import urllib.request
import zipfile
import subprocess
import re
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
            results.append(re.findall('\[(.*?)\]', line))
    print(results)
    print("Done!")
    return {
        'statusCode': 200
    }