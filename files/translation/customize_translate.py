import json
import boto3

def lambda_handler(event, context):
    bucket = event["Records"][0]["s3"]["bucket"]["name"]
    filename = event["Records"][0]["s3"]["object"]["key"]
    source_lang = filename.replace(".csv", "").split("_")[0]
    target_lang = filename.replace(".csv", "").split("_")[1]
    refactor(source_lang, target_lang, filename, bucket)
    return {
        'statusCode': 200
    }


def refactor(source, target, filename, bucket):
    s3 = boto3.client('s3')
    translate = boto3.client('translate')
    csvfile = s3.get_object(Bucket=bucket, Key=filename)
    f = csvfile['Body'].read().decode('utf-8').splitlines()
    first = True
    text = ""
    for line in f:
        if first:
            text += source + "," + target + "\n"
            first = False
        else:
            text += line.replace(",", '","').replace(";", ",") + "\n"
    translate.import_terminology(Name=filename.replace(".csv", ""), MergeStrategy='OVERWRITE',  TerminologyData={"File":  bytearray(text.encode("utf-8")), "Format": 'CSV'})