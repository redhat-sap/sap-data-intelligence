{
  ReplaceSecretsParam: {
    description: |||
      Whether to replace secrets like SDI Registry's htpasswd file if they exist already.
    |||,
    name: 'REPLACE_SECRETS',
    required: false,
    value: 'false',
  },

  ForceRedeployParam:
    {
      description: |||
        Whether to forcefully replace existing objects and configuration files. To replace
        exising secrets as well, RECREATE_SECRETS needs to be set.
      |||,
      name: 'FORCE_REDEPLOY',
      required: false,
      value: 'false',
    },

  OCPMinorReleaseParam: {
    description: |||
      Minor release of OpenShift Container Platform (e.g. 4.2). This value must match the OCP
      server version. The biggest tolerated difference between the versions is 1 in the second
      digit.
    |||,
    name: 'OCP_MINOR_RELEASE',
    required: true,
    value: '4.2',
  },

  LetsencryptParams: [
    {
      description: |||
        Unless given, a local copy will be used.
      |||,
      name: 'LETSENCRYPT_REPOSITORY',
      required: false,
      value: 'https://github.com/tnozicka/openshift-acme',
    },
    {
      description: |||
        Revision of letsencrypt repository to check out.
      |||,
      name: 'LETSENCRYPT_REVISION',
      required: false,
      value: '2cfefc7388102408a334ada90933531c7e5e11c2',
    },
    {
      description: |||
        Either "live" or "staging". Use the latter when debugging SDI Observer's deployment.
      |||,
      name: 'LETSENCRYPT_ENVIRONMENT',
      required: true,
      value: 'live',
    },
  ],

  ExposeWithLetsencryptParam: {
    description: |||
      Whether to expose routes annotated for letsencrypt controller. Requires project admin
      role attached to the sdi-observer service account. Letsencrypt controller must be
      deployed either via this observer or cluster-wide for this to have an effect.
    |||,
    name: 'EXPOSE_WITH_LETSENCRYPT',
    value: 'false',
  },

  // these are used only by the registry's deployment job, not in registry's OCP template
  RegistryDeployParams: [
    {
      description: |||
        Unless given, the default storage class will be used.
      |||,
      name: 'SDI_REGISTRY_STORAGE_CLASS_NAME',
      required: false,
    },
    {
      description: |||
        Will be used to generate htpasswd file to provide authentication data to the sdi registry
        service as long as SDI_REGISTRY_HTPASSWD_SECRET_NAME does not exist or REPLACE_SECRETS is
        "true".
      |||,
      from: 'user-[a-z0-9]{6}',
      generage: 'expression',
      name: 'SDI_REGISTRY_USERNAME',
      required: false,
    },
    {
      description: |||
        Will be used to generate htpasswd file to provide authentication data to the sdi registry
        service as long as SDI_REGISTRY_HTPASSWD_SECRET_NAME does not exist or REPLACE_SECRETS is
        "true".
      |||,
      from: '[a-zA-Z0-9]{32}',
      generage: 'expression',
      name: 'SDI_REGISTRY_PASSWORD',
      required: false,
    },
  ],

  // used both in registry's deployment job and registry's OCP template
  RegistryParams: [
    {
      description: |||
        A secret with htpasswd file with authentication data for the sdi image container If
        given and the secret exists, it will be used instead of SDI_REGISTRY_USERNAME and
        SDI_REGISTRY_PASSWORD.
      |||,
      name: 'SDI_REGISTRY_HTPASSWD_SECRET_NAME',
      required: false,
      value: 'container-image-registry-htpasswd',
    },
    {
      description: |||
        Desired hostname of the exposed registry service. Defaults to
        container-image-registry-<NAMESPACE>-apps.<cluster_name>.<base_domain>
      |||,
      name: 'SDI_REGISTRY_ROUTE_HOSTNAME',
      required: false,
    },
    {
      description: |||
        A random piece of data used to sign state that may be stored with the client to protect
        against tampering. If omitted, the registry will automatically generate a secret when it
        starts. If using multiple replicas of registry, the secret MUST be the same for all of
        them.
      |||,
      from: '[a-zA-Z0-9]{32}',
      generage: 'expression',
      name: 'SDI_REGISTRY_HTTP_SECRET',
      required: false,
    },
    {
      description: |||
        Volume space available for container images (e.g. 75Gi).
      |||,
      name: 'SDI_REGISTRY_VOLUME_CAPACITY',
      required: true,
      value: '75Gi',
    },
  ],

  NotRequired: function(p)
    local _mkopt = function(i) i { required: false };
    if std.isArray(p) then
      [_mkopt(_p) for _p in p]
    else if std.isObject(p) then
      _mkopt(p)
    else
      error 'Expected parameter object, not "' + std.type(p) + '"!',

}
