local params = import 'common-parameters.libsonnet';
local base = import 'job-template.libsonnet';

base.JobTemplate {
  local regjobtmpl = self,
  resourceName: 'deploy-registry',
  jobImage: 'sdi-observer:${' + params.OCPMinorReleaseParam.name + '}',
  command: regjobtmpl.resourceName + '.sh',

  description: 'TODO',
  metadata+: {
    annotations+: {
      'openshift.io/display-name': |||
        Job to deploy a container image registry.
      |||,
    },
  },

  parametersToExport+: params.RegistryDeployParams + params.RegistryParams + [
    params.ExposeWithLetsencryptParam,
  ],

  parameters+: [
    params.OCPMinorReleaseParam,
  ],
}
