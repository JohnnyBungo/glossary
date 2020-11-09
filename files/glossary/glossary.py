import boto3
import pandas as pd
import json
import os

def lambda_handler(event, context):
    s3_client = boto3.client('s3')
    s3_bucket = os.environ['Bucket'] if not "s3_bucket" in event["queryStringParameters"] else event["queryStringParameters"]["s3_bucket"] 
    s3_file = event["queryStringParameters"]["source_lang"] + "_" + event["queryStringParameters"]["target_lang"] + ".csv"
    obj = s3_client.get_object(Bucket=s3_bucket, Key=s3_file)
    df = pd.read_csv(obj['Body'], sep=";")
    if event["resource"] == "/select":
        result = select(event, df)
    else:
        result = list(event, df)
    
    return {
        'statusCode': 200,
        'body': json.dumps(result)
    }
    
def select(event, df):
    term = event["queryStringParameters"]["term"]
    result = ""
    for translation in df[df["Quellsprache"] == term]["Zielsprache"]:
        result += translation + ";"
    return "No results" if result == "" else result
    
    
    
def list(event, df):
    windowsize = 0 if not "window_size" in event["queryStringParameters"] else event["queryStringParameters"]["window_size"]
    all_windows = True if not "all_windows" in event["queryStringParameters"] else event["queryStringParameters"]["all_windows"]
    start = 0 if not "start" in event["queryStringParameters"] else event["queryStringParameters"]["start"]
    
    if windowsize > 0 and len(df) > start + windowsize:
        windows = df[start:start+windowsize].to_dict(orient="records")
        if(all_windows):
            counter = 1
            windows = {0:windows}
            start = start + windowsize
            while(len(df) > start + windowsize):
                windows[counter] = df[start:start+windowsize].to_dict(orient="records")
                start = start + windowsize
                counter += 1
            windows[counter] = df[start:].to_dict(orient="records")
            result = {"continue":False, "windows":windows}
        else:
            result = {"continue":True, "window":windows}
    else:
        result = {"continue":False, "window":df[start:].to_dict(orient="records")}   
    return result