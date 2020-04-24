#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

for d in "$(dirname "${BASH_SOURCE[0]}")" . /usr/local/share/sdi; do
    if [[ -e "$d/lib/common.sh" ]]; then
        eval "source '$d/lib/common.sh'"
    fi
done
if [[ "${_SDI_LIB_SOURCED:-0}" == 0 ]]; then
    printf 'FATAL: failed to source lib/common.sh!\n' >&2
    exit 1
fi
common_init

readonly GITHUB_REPOSITORY=https://github.com/tnozicka/openshift-acme
readonly DEFAULT_REVISION=master

readonly USAGE="$(basename "${BASH_SOURCE[0]}") [options]

Deploy letsencrypt controller.

Options:
  -h | --help    Show this message and exit.
  -w | --wait    Block until all resources are available.
  --dry-run      Only log the actions that would have been executed. Do not perform any changes to
                 the cluster. Overrides DRY_RUN environment variable.
  --namespace NAMESPACE
                 Desired k8s NAMESPACE where to deploy the letsencrypt. Defaults to the first
                 environment variable that is set:
                    - LETSENCRYPT_NAMESPACE
                    - SDI_NAMESPACE
                 Unless set, defaults to the current project.
 (-e | --environment) ENVIRONMENT
                 Can be one of \"live\" and \"staging\". Defaults to the former. The latter is
                 useful for debugging of deployment scripts. Overrides LETSENCRYPT_ENVIRONMENT
                 environment variable.
 (-r | --repository) REPOSITORY
                 URL pointing to the git repository. Overrides LETSENCRYPT_REPOSITORY environment
                 variable. Defaults to $DEFAULT_LETSENCRYPT_REPOSITORY if it exists. Defaults
                 to $GITHUB_REPOSITORY otherwise.
  --revision REVISION
                 Revision to check out in the git repository. Overrides LETSENCRYPT_REVISION.
                 Defaults to $DEFAULT_REVISION branch.
 (-p | --projects) P1,P2,...
                 Additional projects that shall be monitored by letsencrypt controller.
                 The project names shall be separated with commas. Alternatively, the flag can
                 be specified multiple times. Will be merged with PROJECTS_TO_MONITOR environment
                 variable.
  --dont-grant-project-permissions
                 Do not create roles and role bindings in monitored projects in order for the
                 controller to manage routes. The act of granting letsencrypt's serviceaccount
                 permissions to manage routes in the monitored projects is someone's else
                 responsibility.
"

readonly longOptions=(
    help wait namespace: environment: repository: revision: projects:
    dont-grant-project-permissions dry-run
)

function waitForReady() {
     oc rollout status --timeout 300s -w deploy/openshift-acme
}

TMPREPODIR=""

function doesLocalRepositoryExist() {
    local location="${1:-}"
    if [[ -z "${location:-}" ]]; then
        return 1
    fi
    local location="${location#file://}"
    if ! [[ -e "${location}" && -d "${location}" ]]; then
        log 'Given repository location "%s" does not exist!' "$location"
        return 1
    fi
}

function ensureRemoteRepository() {
    local repo="${1}"
    TMPREPODIR="$(mktemp -d)"
    log 'Cloning repository %s to temporary directory "%s" and checking out revision "%s" ...' \
        "$repo" "$TMPREPODIR" "$REVISION"
    git clone --depth 5 --single-branch --branch "$REVISION" "$repo" "$TMPREPODIR"
    ORIGINAL_REPOSITORY="$repo"
    REPOSITORY="$TMPREPODIR"
    export ORIGINAL_REPOSITORY REPOSITORY
}

function ensureRepository() {
    if [[ -n "${REPOSITORY:-}" ]]; then
        if isPathLocal "$REPOSITORY"; then
            doesLocalRepositoryExist "$REPOSITORY"
        else
            ensureRemoteRepository "${REPOSITORY}"
        fi
        return $?
    fi
    if [[ -n "${LETSENCRYPT_REPOSITORY:-}" ]]; then
        REPOSITORY="${LETSENCRYPT_REPOSITORY}"
        if isPathLocal "$REPOSITORY"; then
            doesLocalRepositoryExist "$REPOSITORY"
        else
            ensureRemoteRepository "${REPOSITORY}"
        fi
        return $?
    fi
    if doesLocalRepositoryExist "$DEFAULT_LETSENCRYPT_REPOSITORY"; then
        REPOSITORY="$DEFAULT_LETSENCRYPT_REPOSITORY"
        return 0 
    fi
    ensureRemoteRepository "$GITHUB_REPOSITORY"
}

function copyRoleToProject() {
    local project="$1"
    local rc=0
    if [[ "$project" != "$NAMESPACE" ]]; then
        createOrReplace -n "$project" <<<"$roleSpec" || rc=$?
    fi
    oc create rolebinding --namespace="$project" openshift-acme --role=openshift-acme \
        --serviceaccount="$NAMESPACE:openshift-acme" --dry-run -o json | \
            createOrReplace || rc=$?
    return "$rc"
}
export -f copyRoleToProject

function ensureProject() {
    set -x
    local cm
    if ! doesResourceExist "project/$NAMESPACE"; then
        runOrLog oc new-project "$NAMESPACE"
    else
        # delete a conflicting ConfigMap if it exists
        while IFS='' read -r cm; do
            [[ "$cm" =~ -$ENVIRONMENT$ ]] && continue
            runOrLog oc delete "$cm"
        done < <(oc get cm -o name | grep '/letsencrypt-\(live\|staging\)')
    fi
    set +x
}

function cleanup() {
    common_cleanup
    if [[ -n "${TMPREPODIR:-}" ]]; then
        rm -rf "$TMPREPODIR"
    fi
}
trap cleanup EXIT

function deployLetsencrypt() {
    ensureRepository
    set +x
    ensureProject
    parallel createOrReplace -i "${REPOSITORY#file://}/{}" ::: \
        "${LETSENCRYPT_DEPLOY_FILES[@]//@environment@/$ENVIRONMENT}"
    if evalBool DONT_GRANT_PROJECT_PERMISSIONS; then
        return 0
    fi
    # shellcheck disable=SC2034
    roleSpec="$(oc get -o json role openshift-acme)"
    export roleSpec 
    parallel copyRoleToProject '{}' ::: "${PROJECTS[@]}"
    unset roleSpec
}

function canSACreateRoutes() {
    local token="$1"
    local project="$2"
    if ! oc --token="$token" auth can-i -n "$project" create route >/dev/null; then
        log -n    'ERROR: Letsencrypt controller running under service account'
        log -d -n ' "%s:%s"' "$NAMESPACE" "openshift-acme"
        log -d    ' cannot manage routes in project "%s"' "$project"
        return 1
    fi
}
export -f canSACreateRoutes

function check() {
    local secretName
    secretName="$(oc get -o json sa/openshift-acme | \
        jq -r '.secrets[] | select(.name | test("token")).name')"
    local token
    token="$(oc get -o jsonpath='{.data.token}' "secret/$secretName" | base64 -d)"
    parallel canSACreateRoutes "$token" '{}' ::: "${PROJECTS[@]}"
}

PROJECTS=()
function addProjects() {
    local values="${1:-}"
    local ps=()
    [[ -z "${values:-}" ]] && return 0
    readarray -d , -t ps <<<"${values:-}"
    for p in "${ps[@]}"; do
        [[ -z "${p:-}" ]] && continue
        PROJECTS+=( "$p" )
    done
}

if [[ -n "${LETSENCRYPT_NAMESPACE:-}" ]]; then
    NAMESPACE="${LETSENCRYPT_NAMESPACE:-}"
fi
export NAMESPACE

REVISION=master

addProjects "${PROJECTS_TO_MONITOR:-}"

TMPARGS="$(getopt -o he:wr:p: -l "$(join , "${longOptions[@]}")" -n "${BASH_SOURCE[0]}" -- "$@")"
eval set -- "$TMPARGS"

while true; do
    case "$1" in
        -h | --help)
            printf '%s' "$USAGE"
            exit 0
            ;;
        --dry-run)
            DRY_RUN=true
            export DRY_RUN
            shift
            ;;
        -w | --wait)
            # shellcheck disable=SC2034
            WAIT_UNTIL_ROLLEDOUT=1
            shift
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -r | --repository)
            REPOSITORY="$2"
            shift 2
            ;;
        --revision)
            REVISION="$2"
            shift 2
            ;;
        -e | --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -p | --projects)
            addProjects "$2"
            shift 2
            ;;
        --dont-grant-project-permissions)
            # shellcheck disable=SC2034
            DONT_GRANT_PROJECT_PERMISSIONS=1
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            log 'FATAL: unknown option "%s"! See help.' "$1"
            exit 1
            ;;
    esac
done

if [[ -z "${ENVIRONMENT:-}" ]]; then
    ENVIRONMENT="${LETSENCRYPT_ENVIRONMENT:-live}"
fi
if ! [[ "${ENVIRONMENT}" =~ ^(live|staging)$ ]]; then
    log 'FATAL: environment must be either "live" or "staging", not "%s"' "$ENVIRONMENT"
    exit 1
fi

if evalBool DEPLOY_LETSENCRYPT true && [[ -z "${DEPLOY_LETSENCRYPT:-}" ]]; then
    DEPLOY_LETSENCRYPT=true
fi

if [[ -n "${NAMESPACE:-}" ]]; then
    if evalBool DEPLOY_LETSENCRYPT; then
        log 'Deploying SDI registry to namespace "%s"...' "$NAMESPACE"
        if ! doesResourceExist "project/$NAMESPACE"; then
            runOrLog oc new-project --skip-config-write "$NAMESPACE"
        fi
    fi
    if [[ "$(oc project -q)" != "${NAMESPACE}" ]]; then
        oc project "${NAMESPACE}"
    fi
fi
export NAMESPACE
TMP_PROJECTS=( "$NAMESPACE" )
[[ "${#PROJECTS[@]}" -gt 0 ]] && TMP_PROJECTS+=( "${PROJECTS[@]}" )

readarray -t PROJECTS < <(printf '%s\n' "${PROJECTS[@]}" | sort -u | grep -v '^\s*$')

if [[ -z "${REVISION:-}" ]]; then
    REVISION="${LETSENCRYPT_REVISION:-$DEFAULT_REVISION}"
fi

if evalBool DEPLOY_LETSENCRYPT; then
    deployLetsencrypt
fi

check

if evalBool WAIT_UNTIL_ROLLEDOUT; then
    waitForReady
fi
