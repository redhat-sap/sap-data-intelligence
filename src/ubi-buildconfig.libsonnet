local bc = import 'buildconfig.libsonnet';
local base = import 'ocp-template.libsonnet';

{
  BuildConfigTemplate: base.OCPTemplate {
    local bctmpl = self,
    resourceName:: error 'resourceName must be overriden by a child!',
    dockerfile:: error 'dockerfile must be overriden by a child!',
    imageStreamTag:: error 'imageStreamTag must be overriden by a child!',

    bc:: bc.BuildConfig {
      resourceName: bctmpl.resourceName,
      dstImageStreamTag: bctmpl.imageStreamTag,
      srcImageStreamTag: 'ubi8:latest',
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

    newParameters:: [
      {
        description: |||
          Name of the secret with credentials for registry.redhat.io registry. Please visit
          https://access.redhat.com/terms-based-registry/ to obtain the OpenShift secret. For
          more details, please refer to https://access.redhat.com/RegistryAuthentication.'
        |||,
        name: 'REDHAT_REGISTRY_SECRET_NAME',
        required: true,
      },
    ],

    objects+: [bc],
    parameters+: bctmpl.newParameters,
  },
}
