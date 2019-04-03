#!/usr/bin/env python3

import sys
import os
import datetime
import re
import boto3

import argparse

parser = argparse.ArgumentParser(description='Cleanup old etc backups')
parser.add_argument('--api-key', default=os.environ.get('S3_ACCESS_KEY'),
                    help='API key')
parser.add_argument('--api-secret', default=os.environ.get('S3_SECRET_KEY'),
                    help='API secret')
parser.add_argument('--bucket', default=os.environ.get('S3_BUCKET'))
parser.add_argument('--endpoint', default=os.environ.get('S3_ENDPOINT'))
parser.add_argument('--keep-n', dest="keep_n", type=int, default=144)
parser.add_argument('--keep-hourly', dest="keep_hourly",  type=int,  default=168)
parser.add_argument('--keep-daily', dest="keep_daily", type=int, default=30)
parser.add_argument('--no-delete', dest="no_delete", action="store_true", default=False)
parser.add_argument('--folder', dest="folder", default=os.environ.get('S3_FOLDER'))
args = parser.parse_args()


session = boto3.session.Session()

s3_client = session.client(
    service_name='s3',
    aws_access_key_id=args.api_key,
    aws_secret_access_key=args.api_secret,
    endpoint_url=args.endpoint
)

# get a list of all backups
backups = []
prefix = "etcd-backup-"
if args.folder:
    prefix = args.folder + "/" + prefix

for obj in s3_client.list_objects(Bucket=args.bucket, Prefix=prefix)['Contents']:
    key = obj["Key"][len(prefix):]
    sdate = key[:key.find(".tar")]
    try:
        date = datetime.datetime.strptime(sdate, "%Y-%m-%d-%H-%M-%S")
        backups.append(
            {
                "key": obj["Key"],
                "date": date,
            }   
        )
    except ValueError as e:
        print("ignore unparsable filename: %s (%s)" %(obj["Key"], e))

# sort the backups by date

backups.sort(key=lambda x: x["date"], reverse=True)

HOUR = datetime.timedelta(hours=1)
DAY = datetime.timedelta(days=1)
# prune old backups
last_hour = None

keep = set()
all = set()
last = None

keep_frame = 0
tf = HOUR
keep_max = args.keep_hourly
done = False

for i, b in enumerate(backups):
    all.add(b["key"])
    if done:
        continue
    # always keep last n backups
    if i < args.keep_n:
        keep.add(b["key"])
        last = b["date"]
        continue
    # only keep one backup in each timeframe
    if not last or last - tf > b["date"]:
        last = b["date"]
        keep.add(b["key"])
        keep_frame += 1
    # when we have enough in our current timeframe, switch to the next
    if keep_frame >= keep_max:
        if tf == DAY:
            # last period reached. delete rest
            done = True
            continue
        # collect for next time period
        keep_frame = 0
        tf = DAY
        keep_max = args.keep_daily

delete = all - keep

def sprint(s):
    x = list(s)
    x.sort()
    return str(x)


if not args.no_delete and len(delete):
    response = s3_client.delete_objects(
        Bucket=args.bucket,
        Delete={
            'Objects': [ { "Key": x } for x in (delete)]
        }
    )
    print(response)
else:
    print("WOULD keep: %s" %sprint(keep))
    print("WOULD delete: %s" %sprint(delete))

