local params = import 'common-parameters.libsonnet';
local base = import 'job-template.libsonnet';
local obsbc = import 'observer-buildconfig.libsonnet';
local obssa = import 'observer-serviceaccount.libsonnet';

base {
  local regjobtmpl = self,
  resourceName: 'deploy-registry',
  jobImage: null,
  command: regjobtmpl.resourceName + '.sh',
  createdBy:: 'registry-deploy',
  version:: error 'version must be specified',

  local bc = obsbc {
    createdBy:: regjobtmpl.createdBy,
    version:: regjobtmpl.version,
  },

  description: 'TODO',
  metadata+: {
    annotations+: {
      'openshift.io/display-name': |||
        Job to deploy a container image registry.
      |||,
    },
  },

  objects+: obssa { createdBy: regjobtmpl.createdBy }.Objects + bc.objects,

  parametersToExport+: [params.ReplacePersistentVolumeClaimsParam]
                       + params.RegistryDeployParams + params.RegistryParams + [
    params.ExposeWithLetsencryptParam,
  ] + bc.newParameters,
}
