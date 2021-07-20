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
  ] + bc.newParameters + params.ObserverParams + [
    params.RegistryDeployParam,
    params.LetsencryptDeployParam,
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

  imagePullSpecParam+: {
    description: |||
      Pull specification of a prebuilt image of SDI Observer. If the registry requires
      authentication, a pull secret must be created and linked with the %(saName)s service
      account.
    ||| % {
      saName: obstmpl.saName,
    },
    value: 'quay.io/redhat-sap-cop/sdi-observer:%(version)s-ocp%(ocpMinorRelease)s' % {
      version: obstmpl.version,
      ocpMinorRelease: params.OCPMinorReleaseParam.value,
    },
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
