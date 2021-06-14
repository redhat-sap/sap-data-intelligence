# SDI Observer

The template spawns the "sdi-observer" pod that observes the particular namespace where
SAP Data Intelligence (SDI) runs and modifies its deployments and configuration to enable
its pods to run on Red Hat OpenShift Container Platform (OCP).

## Functionality

The Observer performs the following actions.

### Enables NFS exports in a container on RHCOS

On Red Hat Enterprise Linux CoreOS, SDI's vsystem-vrep statefulset needs to be patched to
mount `emptyDir` volume at `/exports` directory in order to enable NFS exports in the
container running on top of overlayfs which is the default filesystem in RHCOS.

The observer pod modifies vsystem-vrep statefulset as soon as it appears to enable the NFS
exports.

### Configures host path mount for diagnostic pods

SDI's diagnostics-fluentd daemonset is patched to allow its pods to access log
files on the host system. It also modifies it to parse plain text log files instead of
preconfigured json.

### Exposes SDI System Management service

By default, observer also exposes SDI System Management service as a route using OpenShift Ingress controller. The service is in OCP represented as `service/vsystem` resource.

**Influential parameters**:

Parameter                | Default Value | Description
-----                    | -----         | -----------
`MANAGE_VSYSTEM_ROUTE`   | `true`        | Whether to create vsystem route for vsystem service in `SDI_NAMESPACE`. The route will be of reencrypt type. The destination CA certificate for communication with the vsystem service will be kept up to date by the observer. If set to `remove`, the route will be deleted, which is useful to temporarily disable access to the vsystem service during SDI updates.
`VSYSTEM_ROUTE_HOSTNAME` |               | Expose the vsystem service at the provided hostname using a route. The value is applied only if `MANAGE_VSYSTEM_ROUTE` is enabled. The hostname defaults to `vsystem-<SDI_NAMESPACE>.<clustername>.<basedomainname>`

### *(optional)* Ensures registry CA bundle gets imported

SDI requires its images to be hosted in a local container image registry secured by TLS. Often, its certificates are self-signed. In order for SDI to to push and pull images to and from such a registry, its certificate authority must be imported to SDI.

At the moment, SDI Observer allows to import the CA only to the initial DI Tenant during the installation. This is also easily done manually by following [Setting Up Certificates](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.1.latest/en-US/39e8e391d5984e919725e601f089db74.html).

**Influential parameters**:

Parameter              | Default Value                          | Description
-----                  | -----                                  | -----
`INJECT_CABUNDLE`      | `false`                                | Inject CA certificate bundle into SAP Data Intelligence pods. The bundle can be specified with `CABUNDLE_SECRET_NAME`. It is needed if registry is secured by a self-signed certificate.
`CABUNDLE_SECRET_NAME` | `openshift-ingress-operator/router-ca` | The name of the secret containing certificate authority bundle that shall be injected into Data Intelligence pods. By default, the secret bundle is obtained from openshift-ingress-operator namespace where the router-ca secret contains the certificate authority used to signed all the edge and reencrypt routes that are among other things used for `SDI_REGISTRY` and NooBaa S3 API services. The secret name may be optionally prefixed with `$namespace/`.

For example, in the default value `openshift-ingress-operator/router-ca`, the `openshift-ingress-operator` stands for secret's namespace and `router-ca` stands for secret's name. If no `$namespace` prefix is given, the secret is expected to reside in `NAMESPACE` where the SDI observer runs. All the entries present in the `.data` field having `.crt` or `.pem` suffix will be concatenated to form the resulting `cert` file. This bundle will also be used to create `cmcertificates` secret in `SDI_NAMESPACE` according to [Setting Up Certificates](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.0.latest/en-US/39e8e391d5984e919725e601f089db74.html).

### *(optional)* Enforces SDI resources to run on dedicated compute nodes

In order to maintain stability and performance of other workloads running on the same OCP cluster as well as to improve security, one can dedicate a set of nodes to the SDI platform and ensure that its pods are not run anywhere else.

The dedicated nodes must have a unique combination of labels not applicable to the other nodes. These labels must be then specified in the `SDI_NODE_SELECTOR`. Usually, it is `node-role.kubernetes.io/sdi=`. Observer then patches the `SDI_NAMESPACE` resource to make OCP schedule pods running in this namespace only on the nodes matched by the node selector.

**Influential parameters**:

Parameter              | Default Value                          | Description
-----                  | -----                                  | -----
`SDI_NODE_SELECTOR`    |                                        | Make pods in `SDI_NAMESPACE` schedule only on nodes matching the given node selector. The selector will be applied to the whole namespace and its daemonsets. Selector can contain multiple `key=value` labels separated with commas. Example value: `node-role.kubernetes.io/sdi=`

### *(optional)* Deploys container image registry for SDI

Due to a couple of restrictions, it is not possible to mirror SDI images to the integrated OCP image registry. Observer can be instructed to deploy another container image registry suitable to host the images.

By default, the registry will be secured with TLS and will require authentication. It will be also exposed via route utilizing the OpenShift Ingress controller. Unless overridden, credentials for one user will be generated.

Note that by default, the route used to access the registry is secured by the Ingress controller's self-signed certificate. This certificate is not trusted by OpenShift platform for image pulls. To make it trusted, please follow [8.2. Configure OpenShift to trust container image registry](https://access.redhat.com/articles/5100521#ocp-configure-ca-trust).

**Influential parameters**:

Parameter                           | Default Value   | Description
-----                               | -----           | -----
`DEPLOY_SDI_REGISTRY`               | `false`         | Whether to deploy container image registry for the purpose of SAP Data Intelligence. Requires project admin role attached to the `sdi-observer` service account. If enabled, `REDHAT_REGISTRY_SECRET_NAME` must be provided.
`SDI_REGISTRY_STORAGE_CLASS_NAME`   |                 | Unless given, the default storage class will be used.
`REPLACE_PERSISTENT_VOLUME_CLAIMS`  | `false`         | Whether to replace existing persistent volume claims like the one belonging to SDI Registry.
`SDI_REGISTRY_AUTHENTICATION`       | `basic`         | Choose the authentication method of the SDI Registry. Value `none` disables authentication altogether. If set to `basic`, the provided htpasswd file is used to gate the incoming authentication requests.
`SDI_REGISTRY_USERNAME`             |                 | Will be used to generate htpasswd file to provide authentication data to the SDI Registry service as long as `SDI_REGISTRY_HTPASSWD_SECRET_NAME` does not exist or `REPLACE_SECRETS` is `true`.
`SDI_REGISTRY_PASSWORD`             |                 | Will be used to generate htpasswd file to provide authentication data to the SDI Registry service as long as `SDI_REGISTRY_HTPASSWD_SECRET_NAME` does not exist or `REPLACE_SECRETS` is `true`.
`SDI_REGISTRY_HTPASSWD_SECRET_NAME` |                 | A secret with htpasswd file with authentication data for the SDI image container. If given and the secret exists, it will be used instead of `SDI_REGISTRY_USERNAME` and `SDI_REGISTRY_PASSWORD`.
`SDI_REGISTRY_ROUTE_HOSTNAME`       |                 | Desired hostname of the exposed registry service. Defaults to `container-image-registry-<NAMESPACE>-apps.<cluster_name>.<base_domain>` Overrides and obsoletes the `REGISTRY` parameter.
`SDI_REGISTRY_VOLUME_CAPACITY`      | `120Gi`         | Volume space available for container images.
`SDI_REGISTRY_VOLUME_ACCESS_MODE`   | `ReadWriteOnce` | If the given `SDI_REGISTRY_STORAGE_CLASS_NAME` or the default storate class supports `ReadWriteMany` (`RWX`) access mode, please change this to `ReadWriteMany`.

For more information, please see [registry](./registry/) directory.

### Enable iptables manipulation for pods

**NOTE**: this functionality is disabled by default as there are far better alternatives.

On Red Hat Enterprise Linux CoreOS, "vsystem-iptables" containers need to be run as
privileged in order to load iptables-related kernel modules. SDI containers named
"vsystem-iptables" deployed as part of every "vsystem-app" deployment attempt to modify
iptables rules without having the necessary permissions.

The ideal solution is to pre-load these modules during node's startup. When not
feasable, this template can also fix the permissions on-the-fly as the
deployments are created. The drawback is a slower startup of SDI components.

To enable this functionality upon OCP Template's instantiation, one must set
`MAKE_VSYSTEM_IPTABLES_PODS_PRIVILEGED` to `true`. Or set this as the
environment variable on the observer's deployment config.

The recommended alternative is to [pre-load the needed kernel
modules](https://access.redhat.com/articles/5100521#preload-kernel-modules-post)
on the compute nodes.

If not feasible (for example on IBM Cloud platform), one can achieve the same
with the [Node Configurator daemonset](./node-configurator/).

*Influential parameters*:

Parameter | Description
-----     | -----------
`MAKE_VSYSTEM_IPTABLES_PODS_PRIVILEGED` | Patch deployments with `vsystem-iptables` container to make them privileged in order to load kernel modules they need. Unless `true`, it is assumed that the modules have been pre-loaded on the worker nodes. This will make also `vsystem-vrep-*` pod privileged.

## Usage

The template must be instantiated before the SDI installation. It is strongly recommended
to run the observer in a separate namespace from SDI.

Prerequisites:
  - OCP cluster must be healthy including all the cluster operators.
  - The OCP integrated image registry must be properly configured and working.
  - Pull secret for the registry.redhat.io must be configured.

Usage:
  Assuming the SDI will be run in the `SDI_NAMESPACE` which is different from the observer
  NAMESPACE, instantiate the template with parameters like this:

    oc new-project $SDI_NAMESPACE
    oc new-project sdi-observer
    oc process sdi-observer \\
        SDI_NAMESPACE=$SDI_NAMESPACE \\
        NAMESPACE=sdi-observer | oc create -f -

## HOWTO

1. Get a secret for accessing registry.redhat.io at: https://access.redhat.com/terms-based-registry/
See [Red Hat Container Registry Authentication](https://access.redhat.com/RegistryAuthentication) for more information.

2. Create a project to host SDI Observer (e.g. `sdi-observer`): `oc new-project sdi-observer`

3. Create the downloaded secret in there and add it as a pull secret for builds:

        # oc create -f rht-registry-miminar-secret.yaml
        secret/1979710-miminar-pull-secret created
        # oc secrets link default 1979710-miminar-pull-secret --for=pull

4. Create the deployment files:

        # oc process NAMESPACE=sdi-observer SDI_NAMESPACE=sdi \
            REDHAT_REGISTRY_SECRET_NAME=1979710-miminar-pull-secret \
            DEPLOY_SDI_REGISTRY=true DEPLOY_LETSENCRYPT=true \
            -f observer/ocp-template.json | oc create -f -
            
## Update instructions

## Deprecated parameters

The following parameters will be removed in future versions of SDI Observer.

Parameter | Since | Substitutes | Description
--------- | ----------- | -------- | --------
`REGISTRY` | 0.1.13 | `SDI_REGISTRY_ROUTE_HOSTNAME` | The registry to mark as insecure. If not given, it will be determined from the installer-config secret in the `SDI_NAMESPACE.` If `DEPLOY_SDI_REGISTRY` is set to `true`, this variable will be used as the container image registry's hostname when creating the corresponding route.
`MARK_REGISTRY_INSECURE` | 0.1.13 | `INJECT_CABUNDLE`, `CABUNDLE_SECRET_NAME` | Set to true if the given or configured `REGISTRY` shall be marked as insecure in all instances of Pipeline Modeler.
`DEPLOY_LETSENCRYPT` | 0.1.13 | | Whether to deploy letsencrypt controller. Requires project admin role attached to the sdi-observer service account.
`LETSENCRYPT_REVISION` | 0.1.13 | | Revision of letsencrypt repository to check out.
`LETSENCRYPT_REPOSITORY` | 0.1.13 | | Unless given, a local copy will be used.
`EXPOSE_WITH_LETSENCRYPT` | 0.1.13 | | Whether to expose routes annotated for letsencrypt controller. Requires project admin role attached to the sdi-observer service account. Letsencrypt controller must be deployed either via this observer or cluster-wide for this to have an effect. Defaults to the value of `DEPLOY_LETSENCRYPT`
