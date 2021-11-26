# Migrate SDI object storage data to RGW

## Motivation

There may be issues with the object storage endpoint currently used by SAP Data Intelligence. For example failing backups. This guide allows for migration to another object storage endpoint.

## Prerequisites

- SAP Data Intelligence installed with configured backups and checkpoint store
- Linux based management host
- `jq` binary of version 1.6 or higher available on the management host
- `openshift-clients` installed
- OCP client logged in as a cluster-admin

## Procedure

**Note**: This guide aims to be generic but for the sake of simlicity, we will assume the user migrates from S3 NooBaa bucket to S3 RADOS gateway.  
**Note**: This guide assumes that the root path (aka bucket name) is the same for both the old and the new object storage endpoint.

### [Stop Data Intelligence](https://access.redhat.com/articles/5100521#ocp-up-stop-sdi)

And wait until all the pods disappear from the DI namespace. The following shall return no pods:

    # oc get pods -n SDI_NAMESPACE | grep -v 'Completed\|Error'

### Clone this repository to your management host

    # git clone https://github.com/redhat-sap/sap-data-intelligence
    # cd sap-data-intelligence

### Determine the current bucket name

The bucket name must be the same on the new storage backend. Make sure to first determine the existing bucket name. For example:

    TODO

### Create a new storage bucket on your backend

In this example, we will create new

TODO

### Migrate data from the old bucket to the new one

TODO

#### rclone configuration


```
rclone config
Name> morrisville-rgw
n) New Remote
Storage> s3
provider> other
env_auth> false
access_key_id> changeme
secret_access_key> changeme
region>
endpoint> https://rgw-odf.apps.morrisville.ocp.vslen
location_constraint>
acl>
Edit Advanced Config (y/n)? n
```

The default route is insecure. Let's expose the RGW service secured with TLS:

```
oc create route edge --service=rook-ceph-rgw-ocs-storagecluster-cephobjectstore \
    -n openshift-storage --hostname=rgw-odf.apps.morrisville.ocp.vslen \
    --insecure-policy=Redirect 
```

```
oc -n "sdi32" patch datahub default --type='json' \
    -p '[{"op":"replace","path":"/spec/runLevel","value":"Stopped"}]'
```

```
oc get secret -n openshift-ingress-operator -o json router-ca | \
    jq -r '.data as $d | $d | keys[] |
        select(test("\\.crt$")) | $d[.] | @base64d' >morrisville-router-ca.cr
sudo cp -v morrisville-router-ca.crt /etc/pki/ca-trust/source/anchors/morrisville-router-ca.crt && sudo update-ca-trust
```

```
# please make sure to unset all AWS_* environment variables first
rclone sync --progress --ca-cert=$(pwd)/router-ca.crt \
    morrisville-noobaa:sdi-checkpoint-store-db781d27-a218-47b4-9292-607e0a1a5c59/ \
    morrisville-rgw:sdi-checkpoint-rgw-b4c190b4-5ad4-4d54-a870-3873b17eeee8/
```

### Update SDI Secrets

TODO

### Start SDI

TODO
