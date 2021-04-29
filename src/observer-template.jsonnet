local params = import 'common-parameters.libsonnet';
local base = import 'dc-template.libsonnet';
local obsbc = import 'observer-buildconfig.libsonnet';
local obssa = import 'observer-serviceaccount.libsonnet';
local urls = import 'urls.jsonnet';

base {
  local obstmpl = self,
  resourceName: 'sdi-observer',
  imageStreamTag: obstmpl.resourceName + ':' + obstmpl.version + '-ocp${OCP_MINOR_RELEASE}',
  createdBy: 'sdi-observer-template',
  saObjects:: obssa { createdBy: obstmpl.createdBy },
  command: '/usr/local/bin/observer.sh',
  requests:: {
    cpu: '400m',
    memory: '500Mi',
  },
  limits+:: {
    cpu: '2000m',
    memory: '2Gi',
  },

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
    params.RegistryDeployParam,
    params.LetsencryptDeployParam,
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
    {
      description: |||
        Whether to create vsystem route for vsystem service in SDI_NAMESPACE. The route will be
        of reencrypt type. The destination CA certificate for communication with the vsystem
        service will be kept up to date by the observer. If set to "remove", the route will be
        deleted, which is useful to temporarily disable access to vsystem service during SDI
        updates.
      |||,
      required: false,
      name: 'MANAGE_VSYSTEM_ROUTE',
      value: 'false',
    },
    {
      description: |||
        Expose the vsystem service at the provided hostname using a route. The value is applied
        only if MANAGE_VSYSTEM_ROUTE is enabled. The hostname defaults to
        vsystem-<SDI_NAMESPACE>.<clustername>.<basedomainname>
      |||,
      required: false,
      name: 'VSYSTEM_ROUTE_HOSTNAME',
    },
  ] + [
    params.NotRequired(p)
    for p in params.LetsencryptParams
    if p.name == 'LETSENCRYPT_ENVIRONMENT'
  ] + [params.NodeSelector, params.ReplacePersistentVolumeClaimsParam] + params.RegistryDeployParams + [
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

  saName:: local sas = [o.metadata.name for o in obstmpl.objects if o.kind == 'ServiceAccount'];
          if sas == [] then 'default' else sas[0],


  local bc = obsbc {
    createdBy:: obstmpl.createdBy,
    version:: obstmpl.version,
  },

  local p = {
    text:: error 'text of the paragraph must be set',
    // whether the text is suitable for the disconnected/air-gapped/offline version of the
    // template
    offline:: true,
    // whether the text is suitable for the connecte/online version of the template
    online:: true,
  },

  descriptionParagraphs:: [
    p {
      text:: |||
        The template spawns the "sdi-observer" pod that observes the particular namespace where
        SAP Data Intelligence (SDI) runs and modifies its deployments and configuration to enable
        its pods to run on Red Hat OpenShift.
      |||,
    },
    p {
      text:: |||
        On Red Hat Enterprise Linux CoreOS, SDI's vsystem-vrep statefulset needs to be patched to
        mount `emptyDir` volume at `/exports` directory in order to enable NFS exports in the
        container running on top of overlayfs which is the default filesystem in RHCOS.
      |||,
    },
    p {
      text:: |||
        The observer pod modifies vsystem-vrep statefulset as soon as it appears to enable the NFS
        exports.
      |||,
    },
    p {
      text:: |||
        Additionally, it patches diagnostics-fluentd daemonset to allow its pods to access log
        files on the host system. It also modifies it to parse plain text log files instead of
        preconfigured json.
      |||,
    },
    p {
      text:: |||
        On Red Hat Enterprise Linux CoreOS, "vsystem-iptables" containers need to be run as
        privileged in order to load iptables-related kernel modules. SDI containers named
        "vsystem-iptables" deployed as part of every "vsystem-app" deployment attempt to modify
        iptables rules without having the necessary permissions. The ideal solution is to pre-load
        these modules during node's startup. When not feasable, this template can also fix the
        permissions on-the-fly as the deployments are created. The drawback is a slower startup of
        SDI components.
      |||,
    },
    p {
      text:: |||
        By default, observer also exposes SDI vsystem service as a route using OpenShift Ingress
        controller.
      |||,
    },
    p {
      text:: |||
        The template must be instantiated before the SDI installation. It is stronly recommended
        to run the observer in a separate namespace from SDI.
      |||,
    },
    p {
      text:: |||
        Prerequisites:
          - OCP cluster must be healty including all the cluster operators.
          - The OCP integrated image registry must be properly configured and working.
          - Pull secret for the registry.redhat.io must be configured.
      |||,
      offline: false,
    },
    p {
      text:: |||
        Prerequisites:
          - OCP cluster must be healty including all the cluster operators.
          - A container image registry hosting a prebuilt image of SDI Observer must be reachable
            from the OCP cluster. IMAGE_PULL_SPEC parameter must point to this registry.
          - If the registry requires authentication, a pull secret must be created in the
            NAMESPACE and linked with the "%(saName)s" service account.
      ||| % {
        saName: obstmpl.saName,
      },
      online: false,
    },
    p {
      text:: |||
        Usage:
          Assuming the SDI will be run in the SDI_NAMESPACE which is different from the observer
          NAMESPACE, instantiate the template with parameters like this:

            oc new-project $SDI_NAMESPACE
            oc new-project sdi-observer
            oc process sdi-observer \
                SDI_NAMESPACE=$SDI_NAMESPACE \
                NAMESPACE=sdi-observer | oc create -f -
      |||,
      offline: false,
    },
    p {
      text:: |||
        Usage:
          Assuming the SDI will be run in the SDI_NAMESPACE which is different from the observer
          NAMESPACE, instantiate the template with parameters like this:

            oc new-project $SDI_NAMESPACE
            oc new-project sdi-observer
            # the following 2 commands are needed only if the registry requires authentication
            oc create secret docker-registry my-secret --docker-server=REGISTRY \
                --docker-username=... --docker-password=...
            # oc secrets link %(saName)s my-secret --for=pull

            oc process sdi-observer \
                SDI_NAMESPACE=$SDI_NAMESPACE \
                NAMESPACE=sdi-observer | oc create -f -
      ||| % { saName: obstmpl.saName },
      online: false,
    },
  ],

  messageParagraphs:: [
    p {
      text:: |||
        The SDI Observer will be started. You can watch the progress with the following commands:

          oc logs -f bc/sdi-observer
          oc logs -f dc/sdi-observer

        The SDI observer image will be first built and pushed to the integrated OpenShift image
        registry. That will trigger a new rollout of its deployment config.
      |||,
      offline: false,
    },
    p {
      text:: |||
        The SDI Observer will be started. You can watch the progress with the following commands:

          oc logs -f dc/sdi-observer
      |||,
      online: false,
    },
  ],

  tags:: {
    online: true,
    offline: false,
  },

  renderParagraphs:: function(pars)
    std.join('\n', [
      p.text
      for p in pars
      if std.foldl(
        function(res, tag) res && (!obstmpl.tags[tag] || p[tag]),
        std.objectFields(obstmpl.tags),
        true
      )
    ]),

  metadata+: {
    annotations+: {
      'openshift.io/display-name': |||
        OpenShift enabler and observer for SAP Data intelligence
      |||,
      description: obstmpl.renderParagraphs(obstmpl.descriptionParagraphs),
    },
  },

  message: obstmpl.renderParagraphs(obstmpl.messageParagraphs),

  local setDeploymentStrategy(strategy, object) = if object.kind == 'DeploymentConfig' then
    object {
      spec+: {
        strategy+: {
          type: strategy,
        },
      },
    }
  else object,

  objects: [setDeploymentStrategy('Recreate', o) for o in super.objects] +
           [o for o in obstmpl.saObjects.ObjectsForSDI if o.kind != 'ServiceAccount']
           + bc.objects,

  parameters+: [p for p in params.LetsencryptParams if p.name != 'LETSENCRYPT_ENVIRONMENT'],

}
