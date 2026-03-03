import json
import os
import time
import uuid

import boto3

DDB_TABLE = os.environ["DDB_TABLE"]
SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]
EMAIL = os.environ["EMAIL"]
REPO_URL = os.environ["REPO_URL"]
EXEC_REGION = os.environ.get("EXEC_REGION", "unknown")
SNS_PUBLISH_REGION = os.environ.get("SNS_PUBLISH_REGION", "us-east-1")

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(DDB_TABLE)

# Force SNS client to us-east-1 because the topic is in us-east-1
sns = boto3.client("sns", region_name=SNS_PUBLISH_REGION)

def handler(event, context):
    req_id = str(uuid.uuid4())
    now_ms = int(time.time() * 1000)

    table.put_item(
        Item={
            "pk": f"{req_id}",
            "ts": now_ms,
            "region": EXEC_REGION,
            "path": event.get("rawPath", ""),
        }
    )

    payload = {
        "email": EMAIL,
        "source": "Lambda",
        "region": EXEC_REGION,
        "repo": REPO_URL,
    }

    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Message=json.dumps(payload),
    )

    return {
        "statusCode": 200,
        "headers": {"content-type": "application/json"},
        "body": json.dumps({"region": EXEC_REGION}),
    }