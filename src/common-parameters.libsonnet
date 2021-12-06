local urls = import 'urls.jsonnet';

{
  Param: {
    local p = self,
    text:: error 'text must be overriden by a child!',
    description: if p.required && p.deprecated then
      error ('required and deprecated are mutually exclusive for a template parameter '
             + p.name + '!')
    else std.foldl(
      (function(t, fromTo) std.strReplace(t, fromTo[0], fromTo[1])), [
        // preserve new lines preceded with double space, remove all the others
        ['  \n', '@@@@'],
        ['\n', ' '],
        ['@@@@', '\n'],
        ['  ', ' '],
      ], (if p.deprecated then
            '(deprecated since ' + p.deprecated_since + ') '
          else '') + std.rstripChars(p.text, ' \n')
    ),
    name: error 'name must be overriden by a child!',
    required: false,
    //value: null,
    deprecated:: false,
  },

  ReplaceSecretsParam: $.Param {
    text:: |||
      Whether to replace secrets like SDI Registry's htpasswd file if they exist already.
    |||,
    name: 'REPLACE_SECRETS',
    required: false,
    value: 'false',
  },

  ReplacePersistentVolumeClaimsParam: $.Param {
    text:: |||
      Whether to replace existing persistent volume claims like the one belonging to SDI
      Registry.
    |||,
    name: 'REPLACE_PERSISTENT_VOLUME_CLAIMS',
    required: false,
    value: 'false',
  },

  ForceRedeployParam: $.Param {
    text:: |||
      Whether to forcefully replace existing objects and configuration files. To replace
      exising secrets as well, RECREATE_SECRETS needs to be set.
    |||,
    name: 'FORCE_REDEPLOY',
    required: false,
    value: 'false',
  },

  OCPMinorReleaseParam: $.Param {
    text:: |||
      Minor release of OpenShift Container Platform (e.g. 4.2). This value must match the OCP
      server version. The biggest tolerated difference between the versions is 1 in the second
      digit.
    |||,
    name: 'OCP_MINOR_RELEASE',
    required: true,
    value: '4.6',
  },

  DryRun: $.Param {
    text:: |||
      If set to true, no action will be performed. The pod will just print what would have been
      executed.
    |||,
    name: 'DRY_RUN',
    required: false,
    value: 'false',
  },

  ObserverBuildParams: [
    $.Param {
      text:: |||
        URL of SDI Observer's git repository to clone into sdi-observer image.
      |||,
      name: 'SDI_OBSERVER_REPOSITORY',
      required: true,
      value: 'https://github.com/redhat-sap/sap-data-intelligence',
    },
    $.Param {
      text:: |||
        Revision (e.g. tag, commit or branch) of SDI Observer's git repository to check out.
      |||,
      name: 'SDI_OBSERVER_GIT_REVISION',
      required: true,
      value: 'master',
    },
  ],

  ObserverParams: [
    $.Param {
      text:: |||
        The name of the SAP Data Intelligence namespace to manage. Should be set to a namespace
        other than NAMESPACE.
      |||,
      name: 'SDI_NAMESPACE',
      required: true,
    },
    $.Param {
      text:: |||
        The name of the namespace where SLC Bridge runs.
      |||,
      name: 'SLCB_NAMESPACE',
      value: 'sap-slcbridge',
      required: true,
    },
    $.Param {
      text:: |||
        Set to true if the given or configured VFLOW_REGISTRY shall be marked as insecure in all
        instances of Pipeline Modeler.
      |||,
      name: 'MARK_REGISTRY_INSECURE',
      value: 'false',
      deprecated:: true,
      deprecated_since:: '0.1.13',
    },
    $.Param {
      text:: |||
        Format of the logging files on the nodes. Allowed values are "json" and "text".
        Initially, SDI fluentd pods are configured to parse "json" while OpenShift 4 uses
        "text" format by default. If not given, the default is "text".
      |||,
      name: 'NODE_LOG_FORMAT',
    },
    $.Param {
      text:: |||
        Patch deployments with vsystem-iptables container to make them privileged in order to load
        kernel modules they need. Unless true, it is assumed that the modules have been pre-loaded
        on the worker nodes. This will make also vsystem-vrep-* pod privileged.
      |||,
      name: 'MAKE_VSYSTEM_IPTABLES_PODS_PRIVILEGED',
      value: 'false',
      deprecated:: true,
      deprecated_since:: '0.1.13',
    },
    $.Param {
      text:: |||
        Expose SLC Bridge's service at the provided hostname using a route. If not given, it will
        be exposed at <SLCB_NAMESPACE>.apps.<clustername>.<basedomainname>.
      |||,
      name: 'SLCB_ROUTE_HOSTNAME',
    },
    $.Param {
      text:: |||
        Whether to create a route for SLC Bridge service in SLCB_NAMESPACE. The route will be of
        passthrough type. If set to "remove", the route will be deleted.
      |||,
      name: 'MANAGE_SLCB_ROUTE',
      value: 'true',
    },
    $.Param {
      text:: |||
        Inject CA certificate bundle into SAP Data Intelligence pods. The bundle can
        be specified with CABUNDLE_SECRET_NAME. It is needed if either registry or s3 endpoint
        is secured by a self-signed certificate.
      |||,
      name: 'INJECT_CABUNDLE',
      value: 'false',
    },
    $.Param {
      text:: |||
        The name of the secret containing certificate authority bundle that shall be injected
        into Data Intelligence pods. By default, the secret bundle is obtained from
        openshift-ingress-operator namespace where the router-ca secret contains the certificate
        authority used to signed all the edge and reencrypt routes that are inter alia used for
        SDI_REGISTRY and NooBaa S3 API services. The secret name may be optionally prefixed with
        $namespace/. For example, in the default value "openshift-ingress-operator/router-ca",
        the "openshift-ingress-operator" stands for secret's namespace and "router-ca" stands for
        secret's name. If no $namespace prefix is given, the secret is expected to reside in
        NAMESPACE where the SDI observer runs. All the entries present in the "data" field having
        ".crt" or ".pem" suffix will be concatenated to form the resulting "cert" file. This bundle
        will also be used to create cmcertificates secret in SDI_NAMESPACE according to %s
      ||| % (urls.sapSdiSettingUpCertificates),
      name: 'CABUNDLE_SECRET_NAME',
      value: 'openshift-ingress-operator/router-ca',
    },
    $.Param {
      text:: |||
        Whether to create vsystem route for vsystem service in SDI_NAMESPACE. The route will be
        of reencrypt type. The destination CA certificate for communication with the vsystem
        service will be kept up to date by the observer. If set to "remove", the route will be
        deleted, which is useful to temporarily disable access to vsystem service during SDI
        updates.
      |||,
      name: 'MANAGE_VSYSTEM_ROUTE',
      value: 'true',
    },
    $.Param {
      text:: |||
        Expose the vsystem service at the provided hostname using a route. The value is applied
        only if MANAGE_VSYSTEM_ROUTE is enabled. The hostname defaults to  
          vsystem-<SDI_NAMESPACE>.apps.<clustername>.<basedomainname>
      |||,
      name: 'VSYSTEM_ROUTE_HOSTNAME',
    },
  ],

  LetsencryptDeployParam: $.Param {
    text:: |||
      Whether to deploy letsencrypt controller. Requires project admin role attached to the
      sdi-observer service account.
    |||,
    name: 'DEPLOY_LETSENCRYPT',
    value: 'false',
    deprecated:: true,
    deprecated_since:: '0.1.13',
  },

  LetsencryptParams: [
    $.Param {
      text:: |||
        Unless given, a local copy will be used.
      |||,
      name: 'LETSENCRYPT_REPOSITORY',
      value: 'https://github.com/tnozicka/openshift-acme',
      deprecated:: true,
      deprecated_since:: '0.1.13',
    },
    $.Param {
      text:: |||
        Revision of letsencrypt repository to check out.
      |||,
      name: 'LETSENCRYPT_REVISION',
      value: 'master',
      deprecated:: true,
      deprecated_since:: '0.1.13',
    },
    $.Param {
      text:: |||
        Either "live" or "staging". Use the latter when debugging SDI Observer's deployment.
      |||,
      name: 'LETSENCRYPT_ENVIRONMENT',
      value: 'live',
      deprecated:: true,
      deprecated_since:: '0.1.13',
    },
  ],

  ExposeWithLetsencryptParam: $.Param {
    text:: |||
      Whether to expose routes annotated for letsencrypt controller. Requires project admin
      role attached to the sdi-observer service account. Letsencrypt controller must be
      deployed either via this observer or cluster-wide for this to have an effect.
    |||,
    name: 'EXPOSE_WITH_LETSENCRYPT',
    value: 'false',
    deprecated:: true,
    deprecated_since:: '0.1.13',
  },

  RegistryDeployParam: $.Param {
    text:: |||
      Whether to deploy container image registry for the purpose of SAP Data Intelligence.
      Requires project admin role attached to the sdi-observer service account. Unsupported in
      disconnected environments (ubi-prebuilt flavour).
    |||,
    name: 'DEPLOY_SDI_REGISTRY',
    value: 'false',
    deprecated:: true,
    deprecated_since:: '0.1.17',
  },


  // these are used only by the registry's deployment job, not in registry's OCP template
  RegistryDeployParams: [
    $.Param {
      text:: |||
        The registry to mark as insecure. If not given, it will be determined from the
        installer-config secret in the SDI_NAMESPACE. If DEPLOY_SDI_REGISTRY is set to "true",
        this variable will be used as the container image registry's hostname when creating the
        corresponding route.
      |||,
      name: 'REGISTRY',
      deprecated:: true,
      deprecated_since:: '0.1.13',
    },
    $.Param {
      text:: |||
        Will be used to generate htpasswd file to provide authentication data to the SDI Registry
        service as long as SDI_REGISTRY_HTPASSWD_SECRET_NAME does not exist or REPLACE_SECRETS is
        "true".
      |||,
      from: 'user-[a-z0-9]{6}',
      generate: 'expression',
      name: 'SDI_REGISTRY_USERNAME',
    },
    $.Param {
      text:: |||
        Will be used to generate htpasswd file to provide authentication data to the SDI Registry
        service as long as SDI_REGISTRY_HTPASSWD_SECRET_NAME does not exist or REPLACE_SECRETS is
        "true".
      |||,
      from: '[a-zA-Z0-9]{32}',
      generate: 'expression',
      name: 'SDI_REGISTRY_PASSWORD',
    },
    $.Param {
      text:: |||
        Choose the authentication method of the SDI Registry. Value "none" disables authentication
        altogether. Defaults to "basic" where the provided htpasswd file is used to gate
        the incoming authentication requests.
      |||,
      name: 'SDI_REGISTRY_AUTHENTICATION',
      value: 'basic',
    },
    $.Param {
      text:: |||
        Unless given, the default storage class will be used.
      |||,
      name: 'SDI_REGISTRY_STORAGE_CLASS_NAME',
    },
  ],

  // used both in registry's deployment job and registry's OCP template
  RegistryParams: [
    $.Param {
      text:: |||
        A secret with htpasswd file with authentication data for the sdi image container If
        given and the secret exists, it will be used instead of SDI_REGISTRY_USERNAME and
        SDI_REGISTRY_PASSWORD.
      |||,
      name: 'SDI_REGISTRY_HTPASSWD_SECRET_NAME',
      required: true,
      value: 'container-image-registry-htpasswd',
    },
    $.Param {
      text:: |||
        Desired hostname of the exposed registry service. Defaults to
        container-image-registry-<NAMESPACE>-apps.<cluster_name>.<base_domain>
      |||,
      name: 'SDI_REGISTRY_ROUTE_HOSTNAME',
    },
    $.Param {
      text:: |||
        A random piece of data used to sign state that may be stored with the client to protect
        against tampering. If omitted, the registry will automatically generate a secret when it
        starts. If using multiple replicas of registry, the secret MUST be the same for all of
        them.
      |||,
      from: '[a-zA-Z0-9]{32}',
      generate: 'expression',
      name: 'SDI_REGISTRY_HTTP_SECRET',
    },
    $.Param {
      text:: |||
        Volume space available for container images (e.g. 120Gi).
      |||,
      name: 'SDI_REGISTRY_VOLUME_CAPACITY',
      required: true,
      value: '120Gi',
    },
    $.Param {
      text:: |||
        If the given SDI_REGISTRY_STORAGE_CLASS_NAME or the default storate class supports
        "ReadWriteMany" ("RWX") access mode, please change this to "ReadWriteMany".
      |||,
      name: 'SDI_REGISTRY_VOLUME_ACCESS_MODE',
      required: true,
      value: 'ReadWriteOnce',
    },
  ],

  RedHatRegistrySecretParams: [
    $.Param {
      text:: |||
        Name of the secret with credentials for registry.redhat.io registry. Please visit
        %(token)s to obtain the OpenShift secret. For more details, please refer to %(howto)s
      ||| % {
        token: urls.rhtRegistryToken,
        howto: urls.rhtRegistryAuthentication,
      },
      name: 'REDHAT_REGISTRY_SECRET_NAME',
      required: true,
    },
  ],

  SDINodeRoleLabel: 'node-role.kubernetes.io/sdi=',
  SDINodeRoleSelector: {
    'node-role.kubernetes.io/sdi': '',
  },
  NodeSelector: $.Param {
    text:: |||
      Make pods in SDI_NAMESPACE schedule only on nodes matching the given node selector. The
      selector will be applied to the whole namespace and its daemonsets. Selector can contain
      multiple key=value labels separated with commas.  
      Example value: %(selector)s
    ||| % { selector: $.SDINodeRoleLabel },
    name: 'SDI_NODE_SELECTOR',
    recommended:: $.SDINodeRoleLabel,
  },

  NotRequired: function(p)
    local _mkopt = function(i) i { required: false };
    if std.isArray(p) then
      [_mkopt(_p) for _p in p]
    else if std.isObject(p) then
      _mkopt(p)
    else
      error 'Expected parameter object, not "' + std.type(p) + '"!',

  FilterOut: function(unwanted, from)
    local byName = function(member) member.name;
    [
      p
      for p in from
      if !std.setMember(p, std.set(unwanted, byName), byName)
    ],


}
