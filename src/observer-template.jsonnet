local params = import 'common-parameters.libsonnet';
local base = import 'dc-template.libsonnet';
local is = import 'imagestream.libsonnet';
local obsbc = import 'observer-buildconfig.libsonnet';
local obssa = import 'observer-serviceaccount.libsonnet';
local urls = import 'urls.jsonnet';

base.DCTemplate {
  local obstmpl = self,
  resourceName: 'sdi-observer',
  imageStreamTag: obstmpl.resourceName + ':${OCP_MINOR_RELEASE}',
  createdBy: 'sdi-observer-template',
  saObjects:: obssa { createdBy: obstmpl.createdBy },
  sa: obstmpl.saObjects.ObserverServiceAccount,
  command: '/usr/local/bin/observer.sh',

  parametersToExport+: [
    params.ForceRedeployParam,
    params.ReplaceSecretsParam,
  ] + bc.newParameters + [
    {
      description: |||
        The name of the SAP Data Intelligance namespace to manage. Defaults to the current one. It
        must be set only in case the observer is running in a different namespace (see NAMESPACE).
      |||,
      name: 'SDI_NAMESPACE',
    },
    {
      description: |||
        The name of the namespace where SLC Bridge runs.
      |||,
      name: 'SLCB_NAMESPACE',
      value: 'sap-slcbridge',
    },
    {
      description: |||
        Set to true if the given or configured VFLOW_REGISTRY shall be marked as insecure in all
        instances of Pipeline Modeler.
      |||,
      name: 'MARK_REGISTRY_INSECURE',
      required: true,
      value: 'false',
    },
    {
      description: |||
        Patch deployments with vsystem-iptables container to make them privileged in order to load
        kernel modules they need. Unless true, it is assumed that the modules have been pre-loaded
        on the worker nodes. This will make also vsystem-vrep-* pod privileged.
      |||,
      name: 'MAKE_VSYSTEM_IPTABLES_PODS_PRIVILEGED',
      required: true,
      value: 'false',
    },
    {
      description: |||
        Format of the logging files on the nodes. Allowed values are "json" and "text".
        Initially, SDI fluentd pods are configured to parse "json" while OpenShift 4 uses
        "text" format by default. If not given, the default is "text".
      |||,
      name: 'NODE_LOG_FORMAT',
      required: false,
    },
    {
      description: |||
        The registry to mark as insecure. If not given, it will be determined from the
        installer-config secret in the SDI_NAMESPACE. If DEPLOY_SDI_REGISTRY is set to "true",
        this variable will be used as the container image registry's hostname when creating the
        corresponding route.
      |||,
      name: 'REGISTRY',
    },
    {
      description: |||
        Whether to deploy container image registry for the purpose of SAP Data Intelligence.
        Requires project admin role attached to the sdi-observer service account. If enabled,
        REDHAT_REGISTRY_SECRET_NAME must be provided.
      |||,
      name: 'DEPLOY_SDI_REGISTRY',
      required: false,
      value: 'false',
    },
    {
      description: |||
        Whether to deploy letsencrypt controller. Requires project admin role attached to the
        sdi-observer service account.
      |||,
      name: 'DEPLOY_LETSENCRYPT',
      required: false,
      value: 'false',
    },
    {
      description: |||
        Expose SLC Bridge's service at the provided hostname using a route. If not given, it will
        be exposed at slcb.apps.<clustername>.<basedomainname>.
      |||,
      name: 'SLCB_ROUTE_HOSTNAME',
      required: false,
    },
    {
      description: |||
        Inject CA certificate bundle into SAP Data Intelligence pods. The bundle can
        be specified with CABUNDLE_SECRET_NAME. It is needed if either registry or s3 endpoint
        is secured by a self-signed certificate.
      |||,
      required: false,
      name: 'INJECT_CABUNDLE',
      value: 'false',
    },
    {
      description: |||
        The name of the secret containing certificate authority bundle that shall be injected
        into Data Intelligence pods. By default, the secret bundle is obtained from
        openshift-ingress-operator namespace where the router-ca secret contains the certificate
        authority used to signed all the edge and reencrypt routes that are inter alia used for
        SDI_REGISTRY and NooBaa S3 API services. The secret name may be optionally prefixed with
        $namespace/. For example, in the default value "openshift-ingress-operator/router-ca",
        the "openshift-ingress-operator" stands for secret's namespace and "router-ca" stands for
        secret's name. If no $namespace prefix is given, the secret is expected to reside in
        NAMESPACE where the SDI observer runs. All the entries present in the "data" field having
        ".crt" or ".pem" suffix will be concated to form the resulting "cert" file. This bundle
        will also be used to create cmcertificates secret in SDI_NAMESPACE according to %s
      ||| % (urls.sapSdiSettingUpCertificates),
      required: false,
      name: 'CABUNDLE_SECRET_NAME',
      value: 'openshift-ingress-operator/router-ca',
    },
  ] + [
    params.NotRequired(p)
    for p in params.LetsencryptParams
    if p.name == 'LETSENCRYPT_ENVIRONMENT'
  ] + [params.ReplacePersistentVolumeClaimsParam] + params.RegistryDeployParams + [
    params.NotRequired(if p.name == 'SDI_REGISTRY_ROUTE_HOSTNAME' then
      p { description+: 'Overrides REGISTRY parameter.' }
    else p)
    for p in params.RegistryParams
    if p.name != 'SDI_REGISTRY_HTTP_SECRET'
  ] + [
    std.prune(params.ExposeWithLetsencryptParam {
      value: null,
      description+: 'Defaults to the value of DEPLOY_LETSENCRYPT.',
    }),
  ],

  local bc = obsbc.ObserverBuildConfigTemplate {
    createdBy: obstmpl.createdBy,
  },

  metadata+: {
    annotations+: {
      'openshift.io/display-name': |||
        OpenShift enabler and observer for SAP Data intelligence
      |||,
      description: |||
        The template spawns the "sdi-observer" pod that observes the particular
        namespace where SAP Data Intelligence runs and modifies its deployments
        and configuration to enable its pods to run.

        On Red Hat Enterprise Linux CoreOS, SAP Data Intelligence's vsystem-vrep
        statefulset needs to be patched to mount `emptyDir` volume at `/exports`
        directory in order to enable NFS exports in the container running on top
        of overlayfs which is the default filesystem in RHCOS.

        The "sdi-observer" pod modifies vsystem-vrep statefulset as soon as it
        appears to enable the NFS exports.

        The observer also allows to patch pipeline-modeler (aka "vflow") pods to
        mark registry as insecure.

        Additionally, it patches diagnostics-fluentd daemonset to allow its pods
        to access log files on the host system. It also modifies it to parse
        plain text log files instead of preconfigured json.

        On Red Hat Enterprise Linux CoreOS, "vsystem-iptables" containers need to
        be run as privileged in order to load iptables-related kernel modules.
        SAP Data Hub containers named "vsystem-iptables" deployed as part of
        every "vsystem-app" deployment attempt to modify iptables rules without
        having the necessary permissions. The ideal solution is to pre-load these
        modules during node's startup. When not feasable, this template can also
        fix the permissions on-the-fly as the deployments are created.

        The template must be instantiated before the installation of SAP Data
        Hub. Also the namespace, where SAP Data Hub will be installed, must exist
        before the instantiation.

        TODO: document admin project role requirement.

        Usage:
          If running in the same namespace as Data Intelligence, instantiate the
          template as is in the desired namespace:

            oc project $SDI_NAMESPACE
            oc process -n $SDI_NAMESPACE sdi-observer NAMESPACE=$SDI_NAMESPACE | \
              oc create -f -

          If running in a different/new namespace/project, instantiate the
          template with parameters SDI_NAMESPACE and NAMESPACE, e.g.:

            oc new-project $SDI_NAMESPACE
            oc new-project sapdatahub-admin
            oc process sdi-observer \
                SDI_NAMESPACE=$SDI_NAMESPACE \
                NAMESPACE=sapdatahub-admin | oc create -f -
      |||,
    },
  },
  message: |||
    The vsystem-app observer and patcher will be started. You can watch the progress with the
    following command: oc logs -f dc/sdi-observer
  |||,

  objects+: obstmpl.saObjects.ObjectsForSDI + bc.objects + [
    is.ImageStream {
      resourceName: obstmpl.resourceName,
      createdBy: obstmpl.createdBy,
    },
  ],

  parameters+: [p for p in params.LetsencryptParams if p.name != 'LETSENCRYPT_ENVIRONMENT'],

}
