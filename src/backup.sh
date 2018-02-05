#!/usr/bin/env bash

# Timestamp for backup
export FDATE=$(date '+%Y-%m-%d-%H-%M-%S')

# Create some temp folders
mkdir -p /tmp/etcd-backup-${FDATE}
mkdir -p /root/.mc/share

# Global config 
export ETCDCTL_API=3
export TARFILENAME="etcd-backup-${FDATE}.tar.gz"

# Required variables for container to work
REQUIRED=('ETCDCTL_ENDPOINTS', 'S3_ALIAS', 'S3_ENDPOINT', 'S3_BUCKET', 'S3_ACCESS_KEY', 'S3_SECRET_KEY')

function compress_backup() {
	tar czf /tmp/${TARFILENAME} -C /tmp etcd-backup-${FDATE}
}

# Check so all required params are set
for REQ in "${REQUIRED[@]}"; do
	if [ -z "$(eval echo \$$REQ)" ]; then
		echo "Missing required config value: ${REQ}"
		exit 1
	fi
done

# Setup Minio client
function setup_s3() {
	# This outputs less in the logs that using 'mc host config'
	cat > /root/.mc/config.json <<EOF
{
	"version": "8",
	"hosts": {
		"${S3_ALIAS}": {
			"url": "${S3_ENDPOINT}",
			"accessKey": "${S3_ACCESS_KEY}",
			"secretKey": "${S3_SECRET_KEY}",
			"api": "S3v4"
		}
	}
}
EOF
	tee /root/.mc/share/downloads.json > /root/.mc/share/uploads.json <<EOF
{
	"version": "1",
	"shares": {}
}
EOF
	# Setup bucket if it doesn't exist
	if mc ls ${S3_ALIAS}/${S3_BUCKET} 2>&1 | grep -qE "Bucket(.*)does not exist.$"
	then
		echo "${S3_BUCKET} does not exist, creating it"
		mc mb ${S3_ALIAS}/${S3_BUCKET}
	fi
}

# Setup Minio s3 client
setup_s3

# Dump the ETCD data store
etcdctl snapshot save /tmp/etcd-backup-${FDATE}/etcd-dump.bin

# Compress the backups to save some storage
compress_backup

# Transfer backups to S3 storage & remove it before pod shutdown as pods are not deleted directly but scheduled for GC
mc cp /tmp/${TARFILENAME} ${S3_ALIAS}/${S3_BUCKET} --no-color
rm -rf /tmp

echo "Backup Done ✓"
