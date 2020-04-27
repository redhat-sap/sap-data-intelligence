local params = import 'common-parameters.libsonnet';
local base = import 'job-template.libsonnet';

base.JobTemplate {
  local regjobtmpl = self,
  resourceName: 'deploy-registry',
  jobImage: null,
  command: regjobtmpl.resourceName + '.sh',

  description: 'TODO',
  metadata+: {
    annotations+: {
      'openshift.io/display-name': |||
        Job to deploy a container image registry.
      |||,
    },
  },

  parametersToExport+: [params.ReplacePersistentVolumeClaimsParam]
                       + params.RegistryDeployParams + params.RegistryParams + [
    params.ExposeWithLetsencryptParam,
  ] + params.RedHatRegistrySecretParams,
}
