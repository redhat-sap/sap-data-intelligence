#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

readonly USAGE="$(basename "${BASH_SOURCE[0]}") [options] BACKUP_NAME

Backup vsystem-vrep layers of SAP DI instance to the checkpoint store.

BACKUP_NAME is an integer (e.g. 1640175206) representing seconds from Epoch when a valid DI
Backup had been taken. The vsystem-vrep layers tarball will be uploaded to the location
    <REMOTE_PATH>/<DI_Cluster_ID>/<BACKUP_NAME>/vrep/layers.tar.gz
where
    <REMOTE_PATH> is usually an S3 bucket name optionally suffixed with a path prefix.

SAP DI can be stopped.

Prerequisites:
- SAP DI 3.1 or higher installed
- DI backups must be enabled
- user logged in to OpenShift 4 cluster
- admin access to SDI's k8s namespace
- jq and oc binaries in PATH

Options:
  -h | --help   Show this message and quit.
  -n | --namespace SDI_NAMESPACE
                Kubernetes namespace where SAP DI is deployed to. Defaults to the current
                namespace.
  -c | --cluster-id CLUSTER_ID
                SAP DI's ClusterID. Unless specified, it will be determined from
                datahub.installers.datahub.sap.com resource. Affects the tarball's destination
                location."

readonly jobName="sdi-manual-vrep-layers-backup"
readonly rconfSecretName="com.sap.datahub.installers.br.rclone-configuration"
readonly baseJob='{
    "kind": "Job",
    "apiVersion": "batch/v1",
    "metadata": {
        "name": "sdi-manual-vrep-layers-backup"
    },
    "spec": {
        "parallelism": 1,
        "completions": 1,
        "activeDeadlineSeconds": 3600,
        "backoffLimit": 1,
        "template": {
            "metadata": {
                "creationTimestamp": null
            },
            "spec": {
                "volumes": [
                    {
                        "name": "volume-64nrb",
                        "persistentVolumeClaim": {
                            "claimName": "layers-volume-vsystem-vrep-0"
                        }
                    }
                ],
                "containers": [
                    {
                        "name": "script",
                        "image": " ",
                        "command": [
                            "/usr/bin/sleep",
                            "infinity"
                        ],
                        "workingDir": "/scripts",
                        "env": [
                            {
                                "name": "POD_NAME",
                                "valueFrom": {
                                    "fieldRef": {
                                        "apiVersion": "v1",
                                        "fieldPath": "metadata.name"
                                    }
                                }
                            },
                            {
                                "name": "NAMESPACE",
                                "valueFrom": {
                                    "fieldRef": {
                                        "apiVersion": "v1",
                                        "fieldPath": "metadata.namespace"
                                    }
                                }
                            }
                        ],
                        "resources": {},
                        "volumeMounts": [
                            {
                                "name": "volume-64nrb",
                                "mountPath": "/vrep-layers"
                            }
                        ],
                        "terminationMessagePath": "/dev/termination-log",
                        "terminationMessagePolicy": "File",
                        "imagePullPolicy": "IfNotPresent"
                    }
                ],
                "restartPolicy": "Never",
                "terminationGracePeriodSeconds": 30,
                "dnsPolicy": "ClusterFirst",
                "serviceAccountName": "datahub-postaction-sa",
                "serviceAccount": "datahub-postaction-sa",
                "securityContext": {},
                "imagePullSecrets": [
                    {
                        "name": "slp-docker-registry-pull-secret"
                    }
                ],
                "schedulerName": "default-scheduler"
            }
        }
    }
}'

# shellcheck disable=SC2016
readonly script='set -euo pipefail

rc="rclone --config /config/rclone/rclone.conf"
if [[ -z "${REMOTE_PATH:-}" && -n "${RESTORE_REMOTE_PATH:-}" ]]; then
    REMOTE_PATH="${RESTORE_REMOTE_PATH:-}"
fi
if [[ -z "${REMOTE_PATH:-}" ]]; then
    printf "REMOTE_PATH must be set!\n" >&2
    exit 1
fi
rmt="REMOTE:$REMOTE_PATH/$CLUSTER_ID/$BACKUP_NAME"
set -x
if ! $rc cat "$rmt/.metadata.json"; then
    printf "Could not find .metadata.json file!\n"
fi
printf "\nCompressing /vrep-layers and uploading to S3 bucket ...\n"
tar -C /vrep-layers -czv tenant/ user/ | $rc rcat "$rmt/vrep/layers.tar.gz"
$rc lsl "$rmt/"
'

readonly validationJobs=(
    datahub.backup.validate-backup datahub.backup.find-nearest-backup
    datahub.restore.validate-metadata datahub.backup.list-backups
)

function mkJobDef() {
    local job="$baseJob"
    local validateBackupJob
    for valJobName in "${validationJobs[@]}"; do
        validateBackupJob="$(oc get -n "${SDI_NAMESPACE}" -o json job/"$valJobName" \
            --ignore-not-found ||:)"
        if [[ -n "${validateBackupJob:-}" ]]; then
            break
        fi
    done
    if [[ -z "${validateBackupJob:-}" ]]; then
        printf 'Failed to get job %s!\n' datahub.backup.validate-backup
        return 1
    fi
    local vrepPod
    vrepPod="$(oc get -n "${SDI_NAMESPACE}" -o json pod/vsystem-vrep-0 ||:)"
    local clusterId
    if [[ -n "${CLUSTER_ID:-}" ]]; then
        clusterId="${CLUSTER_ID}"
    else
        clusterId="$(oc get -n "${SDI_NAMESPACE}" -o json datahubs/default | \
            jq -r '.spec.clusterID')"
    fi
    if [[ -z "${clusterId:-}" ]]; then
        printf 'Failed to DI'"'"'s cluster ID from Datahub resource!\n'
        return 1
    fi
    job="$(jq --argjson valJob "$validateBackupJob" --arg jobName "$jobName" \
        --argjson vrepPod "${vrepPod:-\{\}}" \
        --arg clusterId "$clusterId" \
        --arg backupName "$backupName" \
        --arg script "$script" \
        '.spec.template.spec.containers[0].image |=
                $valJob.spec.template.spec.containers[0].image |
        .spec.template.spec.containers[0].command |= [
            "/usr/bin/env", "bash", "-c", $script
        ] | .metadata.name |= $jobName | if $vrepPod != {} then
            .spec.template.spec.nodeName |= $vrepPod.spec.nodeName
        else
            .
        end | .spec.template.spec.containers[0].env |= (. + [
            {"name": "CLUSTER_ID",  "value": $clusterId},
            {"name": "BACKUP_NAME", "value": $backupName}
        ] + [$valJob.spec.template.spec.containers[0].env[] |
            select(.name | test("^(RCLONE|REMOTE|RESTORE)"))])' <<<"$job")"
    job="$(oc set volume -n "${SDI_NAMESPACE}" -f - --type=secret \
        --sub-path=rclone.conf --secret-name="$rconfSecretName" \
        --add -m /config/rclone/rclone.conf -o json --local <<<"$job")"
    printf '%s\n' "$job"
}

function getJobPodSelector() {
    oc get -n "$SDI_NAMESPACE" -o json "job/$jobName" | jq -r --arg jobName "$jobName" \
            '.spec.selector.matchLabels | .["job-name"] |= $jobName | to_entries |
            map("\(.key)=\(.value)") | join(",")'
}

readonly longOptions=(
    help namespace: cluster-id:
)

function join() { local IFS="$1"; shift; echo "$*"; }

TMPARGS="$(getopt -o hn:c: --longoptions "$(join , "${longOptions[@]}")" \
    -n "$(basename "${BASH_SOURCE[0]}")" -- "$@")"
eval set -- "$TMPARGS"

while true; do
    case "$1" in
        -h | --help)
            printf '%s\n' "$USAGE"
            exit 0
            ;;
        -n | --namespace)
            SDI_NAMESPACE="$2"
            shift 2
            ;;
        -c | --cluster-id)
            CLUSTER_ID="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            printf 'Unknown option "%s"! See help.\n' "$1"
            exit 1
            ;;
    esac
done

if [[ "$#" -lt 1 || -z "${1:-}" ]]; then
    printf 'Missing BACKUP_NAME argument!\n' >&2
    exit 1
fi
backupName="$1"

if [[ -z "${SDI_NAMESPACE:-}" ]]; then
    SDI_NAMESPACE="$(oc project -q)"
fi

mkJobDef | oc -n "$SDI_NAMESPACE" replace -f - --force

printf '\nJobs environment:\n'
oc set env -n "$SDI_NAMESPACE" --list "job/$jobName"
printf '\n'

printf 'Waiting for pod to become Ready...\n'
oc wait --for=condition=Ready -n "$SDI_NAMESPACE" "pod" -l "$(getJobPodSelector)"

oc logs -n "$SDI_NAMESPACE" -f "job/$jobName"
