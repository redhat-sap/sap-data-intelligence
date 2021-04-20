local bc = import 'buildconfig.libsonnet';
local params = import 'common-parameters.libsonnet';
local base = import 'ocp-template.libsonnet';
local ubiis = import 'ubi-imagestream.jsonnet';

base {
  local bctmpl = self,
  resourceName:: error 'resourceName must be overriden by a child!',
  dockerfile:: error 'dockerfile must be overriden by a child!',
  imageStreamTag:: error 'imageStreamTag must be overriden by a child!',
  createdBy:: error 'createdBy must be overridden by a child!',
  version:: error 'version must be specified',

  ubiIS:: ubiis {
    createdBy:: bctmpl.createdBy,
    version:: bctmpl.version,
  },

  bcObjects:: bc {
    resourceName:: bctmpl.resourceName,
    dstImageStreamTag:: bctmpl.imageStreamTag,
    srcImageStreamTag:: bctmpl.ubiIS.metadata.name + ':latest',
    dockerfile:: bctmpl.dockerfile,
    createdBy:: bctmpl.createdBy,
    version:: bctmpl.version,

    BuildConfig+: {
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
  }.Objects,

  newParameters:: params.RedHatRegistrySecretParams,

  objects+: bctmpl.bcObjects + [bctmpl.ubiIS],
  parameters+: bctmpl.newParameters,
}
