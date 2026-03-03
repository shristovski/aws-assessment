import json
import os

import boto3

EXEC_REGION = os.environ.get("EXEC_REGION", "unknown")
CLUSTER_ARN = os.environ["CLUSTER_ARN"]
TASK_DEF_ARN = os.environ["TASK_DEF_ARN"]
SUBNETS = os.environ["SUBNETS"].split(",")
SECURITY_GRP = os.environ["SECURITY_GRP"]

ecs = boto3.client("ecs")

def handler(event, context):
    resp = ecs.run_task(
        cluster=CLUSTER_ARN,
        taskDefinition=TASK_DEF_ARN,
        launchType="FARGATE",
        networkConfiguration={
            "awsvpcConfiguration": {
                "subnets": SUBNETS,
                "securityGroups": [SECURITY_GRP],
                "assignPublicIp": "ENABLED",
            }
        },
        count=1,
    )

    task_arn = None
    if resp.get("tasks"):
        task_arn = resp["tasks"][0].get("taskArn")

    return {
        "statusCode": 200,
        "headers": {"content-type": "application/json"},
        "body": json.dumps({"region": EXEC_REGION, "taskArn": task_arn}),
    }