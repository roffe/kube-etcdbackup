#!/usr/bin/env bash

set -x

# Timestamp for backup
export FDATE=$(date '+%Y-%m-%d-%H-%M-%S')
export GPGHOME=/tmp/gnupg

# Create some temp folders
mkdir -p /tmp/etcd-backup-${FDATE}
mkdir -p /root/.mc/share

# Global config 
export ETCDCTL_API=3
export TARFILENAME="etcd-backup-${FDATE}.tar.gz"

# Required variables for container to work
REQUIRED=('ETCDCTL_ENDPOINTS', 'S3_ALIAS', 'S3_ENDPOINT', 'S3_BUCKET', 'S3_ACCESS_KEY', 'S3_SECRET_KEY')

if [[ "${INSECURE:-0}" == 1 ]]; then
	MC_ARGS="--insecure"
fi

function crypt_compress_backup() {
	# no gpg key set, skip encryption
	tar czf /tmp/${TARFILENAME} -C /tmp etcd-backup-${FDATE}
	if [[ ! -z "${GPG_PUBKEY}" ]]; then
		# pgp --recipient-file does not work, use old method
		rm -rf $GPGHOME
		mkdir -p $GPGHOME
		chmod 700 $GPGHOME
		cat <<< $GPG_PUBKEY > $GPGHOME/key.pub

		gpg --homedir $GPGHOME --import $GPGHOME/key.pub
		KEYID=`gpg --list-public-keys --batch --with-colons --homedir $GPGHOME |  grep "pub:" | cut -d: -f5`

		echo "PGP encrypting for: $KEYID"
		gpg --batch --yes --trust-model always --homedir $GPGHOME -r $KEYID -e /tmp/$TARFILENAME
		if [ $? != 0 ]; then
			echo "Encryption failed. Aborting backup"
			exit 3
		fi
		export TARFILENAME=${TARFILENAME}.gpg
	fi
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
etcdctl snapshot save /tmp/etcd-backup-${FDATE}/etcd-dump.bin || exit 1

# Compress the backups to save some storage
crypt_compress_backup

S3_PATH="${S3_BUCKET}"

if [[ ! -z "${S3_FOLDER}" ]]; then
  S3_PATH="${S3_PATH}/${S3_FOLDER}/${TARFILENAME}"
fi

# Transfer backups to S3 storage & remove it before pod shutdown as pods are not deleted directly but scheduled for GC
cd /tmp
mc $MC_ARGS --no-color cp ${TARFILENAME} ${S3_ALIAS}/${S3_PATH} || exit 2
cd ..
rm -rf /tmp

echo "Backup Done ✓"

if [[ $AUTOCLEAN == "1" ]]; then
	echo "Cleaning old backups"
	/cleanup.py ${AUTOCLEAN_ARGS}
fi
