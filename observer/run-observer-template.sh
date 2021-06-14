#!/usr/bin/env bash

# OCP Template for SDI Observer

set -euo pipefail

NAMESPACE=sdi-observer
DRY_RUN=false
SDI_NAMESPACE=sdi
OCP_MINOR_RELEASE=4.6
DEPLOY_SDI_REGISTRY=true
INJECT_CABUNDLE=true
MANAGE_VSYSTEM_ROUTE=true
#VSYSTEM_ROUTE_HOSTNAME=vsystem-<SDI_NAMESPACE>.<clustername>.<base_domain>
SDI_NODE_SELECTOR="node-role.kubernetes.io/sdi="

# (recommended) (a must for production), set the following variable (use UBI8 for the base image)
REDHAT_REGISTRY_SECRET_NAME=""
# otherwise, comment it out and uncomment the following lines 
#SOURCE_IMAGE_PULL_SPEC=registry.centos.org/centos:8
#SOURCE_IMAGESTREAM_NAME=centos8
#SOURCE_IMAGESTREAM_TAG=latest


# whether the observer shall deploy a container image registry in its NAMESPACE
DEPLOY_SDI_REGISTRY=false
#SDI_REGISTRY_STORAGE_CLASS_NAME=       # use the default sc unless set
# change to ReadWriteMany if supported by the storage class
SDI_REGISTRY_VOLUME_ACCESS_MODE=ReadWriteOnce   # ReadWriteMany
SDI_REGISTRY_VOLUME_CAPACITY=120Gi
#SDI_REGISTRY_ROUTE_HOSTNAME=container-image-registry-<NAMESPACE>-apps.<cluster_name>.<base_domain>
SDI_REGISTRY_AUTHENTICATION=basic       # "none" disables the authentication
#SDI_REGISTRY_USERNAME=                 # auto-generated unless set
#SDI_REGISTRY_PASSWORD=                 # auto-generated unless set
#SDI_REGISTRY_HTPASSWD_SECRET_NAME=     # auto-generated unless set

INJECT_CABUNDLE=false
CABUNDLE_SECRET_NAME=openshift-ingress-operator/router-ca

# build the latest revision; change to a particular tag if needed (e.g. 0.1.13)
SDI_OBSERVER_GIT_REVISION=master
# uncomment to always use the git repository
# set to path/to/a/local/checkout to use a local file
# leave commented to autodecect (prefer local file, fallback to the remote git repository)
# NOTE: OCP build cannot use local checkout
#SDI_OBSERVER_REPOSITORY=https://github.com/redhat-sap/sap-data-intelligence

#################################################################################################
# DO NOT EDIT THE LINES BELOW
#################################################################################################

readonly gitRepo=https://github.com/redhat-sap/sap-data-intelligence

readonly envVars=(
    NAMESPACE
    DRY_RUN
    SDI_NAMESPACE
    OCP_MINOR_RELEASE
    DEPLOY_SDI_REGISTRY
    MANAGE_VSYSTEM_ROUTE
    VSYSTEM_ROUTE_HOSTNAME
    REDHAT_REGISTRY_SECRET_NAME
    SDI_NODE_SELECTOR
    SDI_OBSERVER_REPOSITORY
    SDI_OBSERVER_GIT_REVISION

    DEPLOY_SDI_REGISTRY
    SDI_REGISTRY_STORAGE_CLASS_NAME
    SDI_REGISTRY_VOLUME_ACCESS_MODE
    SDI_REGISTRY_VOLUME_CAPACITY
    SDI_REGISTRY_ROUTE_HOSTNAME
    SDI_REGISTRY_AUTHENTICATION
    SDI_REGISTRY_USERNAME
    SDI_REGISTRY_PASSWORD
    SDI_REGISTRY_HTPASSWD_SECRET_NAME

    INJECT_CABUNDLE
    CABUNDLE_SECRET_NAME
)

function join() { local IFS="$1"; shift; echo "$*"; }

template=ocp-template
sourceLocation="$gitRepo"
root="$(dirname "$(dirname "${BASH_SOURCE[0]}")")"
if [[ -n "${SDI_OBSERVER_REPOSITORY:-}" ]]; then
    sourceLocation="${SDI_OBSERVER_REPOSITORY:-}"
elif [[ -e "$root/observer/${template}.json" ]]; then
    sourceLocation="$root"
fi

if [[ -z "${REDHAT_REGISTRY_SECRET_NAME:-}" && ( \
            -n "${SOURCE_IMAGE_PULL_SPEC:-}" || \
            -n "${SOURCE_IMAGESTREAM_NAME:-}" || \
            -n "${SOURCE_IMAGESTREAM_TAG:-}" ) ]];
then
    template=ocp-custom-source-image-template
fi

args=( -f )
if [[ "${sourceLocation:-}" =~ ^https:// ]]; then
    args+=(
        "$(join / "$sourceLocation" \
            "${SDI_OBSERVER_GIT_REVISION:-master}" \
            "observer/${template}.json")"
    )
else
    args+=(
        "$(join / "$sourceLocation" \
            "observer/${template}.json")"
    )
fi

for var in "${envVars[@]}"; do
    eval 'value="${'"$var"':-}"'
    if [[ -z "${value:-}" ]]; then
        continue
    fi
    case "$var" in
        SDI_OBSERVER_REPOSITORY)
            if ! [[ "${value}" =~ ^(http|ftp|https):// ]]; then
                value="$gitRepo"
            fi
            ;;
    esac
    args+=( "$var=$value" )
done

oc process "${args[@]}" | oc apply -f -
