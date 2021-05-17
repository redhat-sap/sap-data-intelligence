#!/bin/bash

oc project sdi-infra
for claimName in sdi-checkpoint-store sdi-data-lake; do
   printf 'Bucket/claim %s:\n  Endpoint:\thttp://s3.openshift-storage.svc.cluster.local\n  Bucket name:\t%s\n' "$claimName" "$(oc get obc -o jsonpath='{.spec.bucketName}' "$claimName")"
   for key in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY; do
     printf '  %s:\t%s\n' "$key" "$(oc get secret "$claimName" -o jsonpath="{.data.$key}" | base64 -d)"
   done
done | column -t -s $'\t' | tee storage-credentials.txt
