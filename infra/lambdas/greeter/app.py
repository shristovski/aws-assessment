import json
import os
import time
import uuid
import boto3

# Prefer the real runtime region if available
EXEC_REGION = (
    os.environ.get("EXEC_REGION")
    or os.environ.get("AWS_REGION")
    or os.environ.get("AWS_DEFAULT_REGION")
    or "unknown"
)

# Optional config (do not crash on import)
DDB_TABLE = os.environ.get("DDB_TABLE")
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN")
EMAIL = os.environ.get("EMAIL", "")
REPO_URL = os.environ.get("REPO_URL", "")

# SNS topic is in us-east-1 in your comment; keep override
SNS_PUBLISH_REGION = os.environ.get("SNS_PUBLISH_REGION", "us-east-1")

dynamodb = boto3.resource("dynamodb", region_name=EXEC_REGION)
sns = boto3.client("sns", region_name=SNS_PUBLISH_REGION)

def handler(event, context):
    req_id = str(uuid.uuid4())
    now_ms = int(time.time() * 1000)

    # Best-effort DynamoDB write (don't fail the request)
    try:
        if DDB_TABLE:
            table = dynamodb.Table(DDB_TABLE)
            table.put_item(
                Item={
                    "pk": req_id,
                    "ts": now_ms,
                    "region": EXEC_REGION,
                    "path": event.get("rawPath") or event.get("path") or "",
                }
            )
    except Exception as e:
        print(f"DDB put_item failed: {e}")

    # Best-effort SNS publish (don't fail the request)
    try:
        if SNS_TOPIC_ARN:
            payload = {
                "email": EMAIL,
                "source": "Lambda",
                "region": EXEC_REGION,
                "repo": REPO_URL,
            }
            sns.publish(TopicArn=SNS_TOPIC_ARN, Message=json.dumps(payload))
    except Exception as e:
        print(f"SNS publish failed: {e}")

    return {
        "statusCode": 200,
        "headers": {"content-type": "application/json"},
        "body": json.dumps({"region": EXEC_REGION}),
    }