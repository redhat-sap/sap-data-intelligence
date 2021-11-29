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

    # oc get -n SDI_NAMESPACE datahubs/default -o jsonpath='{.spec.restoreRemotePath}'
    sdi-checkpoint-store-db781d27-a218-47b4-9292-607e0a1a5c59

### Create a new storage bucket on your backend

In this example, we will create a new bucket on RGW matching the name of the previous one:

    # utils/mksdibuckets create \
            -n sdi-infra --sc ocs-storagecluster-ceph-rgw --no-generate \
            sdi-checkpoint-store-db781d27-a218-47b4-9292-607e0a1a5c59

### Migrate data from the old bucket to the new one

In this example, we will use rclone binary on the management host.

#### Provide a secure endpoint for RGW

The default route is insecure (plain HTTP). Let's expose the RGW service secured with TLS for the use with rclone:

    # oc create route edge --service=rook-ceph-rgw-ocs-storagecluster-cephobjectstore \
        -n openshift-storage --hostname=rgw-odf.apps.morrisville.ocp.vslen \
        --insecure-policy=Redirect 

Please make sure to modify the `hostname` parameter to match your wildcard apps domain. Unless specified, you will end up with the default hostname: `ocs-storagecluster-cephobjectstore-openshift-storage.apps.<clustername>.<basedomain>`

#### Configure the target (new) remote for rclone

1. Get the credentials:

        # utils/mksdibuckets list -n sdi-infra sdi-checkpoint-store-db781d27-a218-47b4-9292-607e0a1a5c59
        Bucket claim namespace/name:  sdi-infra/sdi-checkpoint-store-db781d27-a218-47b4-9292-607e0a1a5c59  (Status: Bound, Age: 3days 20h)
          Cluster internal URL:       http://rook-ceph-rgw-ocs-storagecluster-cephobjectstore.openshift-storage.svc.cluster.local
          Bucket name:                sdi-checkpoint-store-db781d27-a218-47b4-9292-607e0a1a5c59
          AWS_ACCESS_KEY_ID:          05NEQ24R63RRWSYANGCD
          AWS_SECRET_ACCESS_KEY:      CHANGEME

2. Configure the remote interactively with `rclone config`:

        # rclone config
        Name> morrisville-rgw
        n) New Remote
        Storage> s3
        provider> other
        env_auth> false
        access_key_id> 05NEQ24R63RRWSYANGCD
        secret_access_key> CHANGEME
        region>
        endpoint> https://rgw-odf.apps.morrisville.ocp.vslen
        location_constraint>
        acl>
        Edit Advanced Config (y/n)? n

Note that we use the endpoint exposed via the secure route created in the previous step. The cluster internal URL is not accessible from the management host.

#### Configure the source (original) remote for rclone

1. Get the credentials:

        # utils/mksdibuckets list -n sdi-infra sdi-checkpoint-store
        Bucket claim namespace/name:  sdi-infra/sdi-checkpoint-store  (Status: Bound, Age: 24days 20h)
          Cluster internal URL:       http://s3.openshift-storage.svc.cluster.local
          Bucket name:                sdi-checkpoint-store-db781d27-a218-47b4-9292-607e0a1a5c59
          AWS_ACCESS_KEY_ID:          2hYR2xUGP3wcobv2VA8r
          AWS_SECRET_ACCESS_KEY:      CHANGEME

2. Configure the remote interactively with `rclone config`:

        # rclone config
        Name> morrisville-noobaa
        n) New Remote
        Storage> s3
        provider> other
        env_auth> false
        access_key_id> 2hYR2xUGP3wcobv2VA8r
        secret_access_key> CHANGEME
        region>
        endpoint> https://s3-openshift-storage.apps.morrisville.ocp.vslen
        location_constraint>
        acl>
        Edit Advanced Config (y/n)? n

#### Copy the data

Let's now copy the checkpoint data from the old remote (NooBaa) to the new one (RGW).

1. Get the CA certificate of the OCP's Ingress Controller and make it trusted on the management host. The following is an example for RHEL 7 or newer:

        # oc get secret -n openshift-ingress-operator -o json router-ca | \
            jq -r '.data as $d | $d | keys[] |
                select(test("\\.crt$")) | $d[.] | @base64d' >morrisville-router-ca.cr
        # sudo cp -v morrisville-router-ca.crt /etc/pki/ca-trust/source/anchors/
        # sudo update-ca-trust

2. Please unset all the `AWS_*` environment variables first:

        # env | grep AWS_
        AWS_CA_BUNDLE=/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem
        AWS_CONFIG_FILE=/home/miminar/wsp/morrisville/morrisville/.aws/config
        AWS_SHARED_CREDENTIALS_FILE=/home/miminar/wsp/morrisville/.aws/credentials

        # # unless there is an empty output, unset the variables like this (bash)
        # unset $(env | sed -n -r 's/^([^=]*\s)?\<(AWS_[^=]+).*/\2/p' | sort -u)

3. Copy the data with rclone, please double check that the remote path is exactly the same for both source and target remotes.

        rclone sync --progress \
            morrisville-noobaa:sdi-checkpoint-store-db781d27-a218-47b4-9292-607e0a1a5c59/ \
            morrisville-rgw:sdi-checkpoint-rgw-b4c190b4-5ad4-4d54-a870-3873b17eeee8/

### Update SDI Secrets

DI stores access details in the checkpoint-store bucket in a couple of secrets. The `update-sdi-ob.sh` script can be used to change the details to the new remote.

On the management host, in the `sap-data-intelligence` local checkout, execute the following:

    # obmigrate/update-sdi-ob.sh -n SDI_NAMESPACE \
        --obc=sdi-infra/sdi-checkpoint-store-db781d27-a218-47b4-9292-607e0a1a5c59

The script will read all the access details from the object bucket claim (obc) and related k8s objects and will update the relevant secrets in `SDI_NAMESPACE` accordingly. Alternatively, the access details can be supplied manually. Please execute with `--help` parameter for more information.

### Start SDI

Start the DI instance again:

    # oc -n SDI_NAMESPACE patch datahub/default --type='json' \
            -p '[{"op":"replace","path":"/spec/runLevel","value":"Started"}]'
