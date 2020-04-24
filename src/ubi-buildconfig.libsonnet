local bc = import 'buildconfig.libsonnet';
local params = import 'common-parameters.libsonnet';
local base = import 'ocp-template.libsonnet';
local ubiis = import 'ubi-imagestream.jsonnet';

{
  BuildConfigTemplate: base.OCPTemplate {
    local bctmpl = self,
    resourceName:: error 'resourceName must be overriden by a child!',
    dockerfile:: error 'dockerfile must be overriden by a child!',
    imageStreamTag:: error 'imageStreamTag must be overriden by a child!',

    is:: ubiis.UBIImageStream,

    bc:: bc.BuildConfig {
      resourceName: bctmpl.resourceName,
      dstImageStreamTag: bctmpl.imageStreamTag,
      srcImageStreamTag: bctmpl.is.metadata.name + ':latest',
      dockerfile: bctmpl.dockerfile,

      spec+: {
        strategy+: {
          dockerStrategy+: {
            pullSecret: {
              name: '${REDHAT_REGISTRY_SECRET_NAME}',
            },
          },
        },
      },
    },

    newParameters:: params.RedHatRegistrySecretParams,

    objects+: [bctmpl.bc, bctmpl.is],
    parameters+: bctmpl.newParameters,
  },
}
