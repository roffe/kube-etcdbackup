# kube-etcdbackup

Docker image that takes a list of ETCD nodes and snapshots them and ships of to S3 storage.

## Features

* GPG encryption etcd data
* Autocleanup of old backups

## Encryption

The script can encrypt the database dump with pgp key.
Add the armored pgp key as `GPG_PUBKEY` in the configmap.


## Cleanup

The cleanup script is able to hold the last n backups, as well as hourly and daily backups available.
The default settings are:
```
 --keep-n=144 (one day)
 --keep-hourly=168 (one week)
 --keep-daily=30 (one month)
```

You can adjust the cleanup parameters by setting `AUTOCLEAN_ARGS`.

The default interval is 10 minutes, which results in approximately 10gb useage on a 30mb dump. 

The idea is to have very close backups at hand in case of disaster recovery, while still have a proper
window of one week backups to investigate and debug issues or recover partial data.
