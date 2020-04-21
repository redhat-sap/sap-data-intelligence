local params = import 'common-parameters.libsonnet';
local base = import 'job-template.libsonnet';

base.JobTemplate {
  local acmejobtmpl = self,
  resourceName: 'deploy-letsencrypt',
  jobImage: null,
  command: acmejobtmpl.resourceName + '.sh',

  description: 'TODO',
  metadata+: {
    annotations+: {
      'openshift.io/display-name': |||
        Job to deploy a letsencrypt controller.
      |||,
    },
  },

  parametersToExport+: [
    (if p.name == 'LETSENCRYPT_REPOSITORY' then p {
       value: null,
       description+: |||
         Defaults to a local check out. Example value: https://github.com/tnozicka/openshift-acme
       |||,
     } else p)
    for p in params.LetsencryptParams
  ] + [
    {
      name: 'PROJECTS_TO_MONITOR',
      description: |||
        Additional projects to monitor separated by commas. The controller will be granted
        permission to manage routes in the projects. The job needs to be able to create roles
        and rolebindings in all the projects listed.
      |||,
      required: false,
    },
  ],

  parameters+: [],
}
