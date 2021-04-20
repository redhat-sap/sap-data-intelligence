local params = import 'common-parameters.libsonnet';
local base = import 'job-template.libsonnet';
local obsbc = import 'observer-buildconfig.libsonnet';
local obssa = import 'observer-serviceaccount.libsonnet';

base {
  local acmejobtmpl = self,
  resourceName: 'deploy-letsencrypt',
  jobImage: null,
  command: acmejobtmpl.resourceName + '.sh',
  createdBy:: 'letsencrypt-deploy',

  local bc = obsbc {
    createdBy:: acmejobtmpl.createdBy,
    version:: acmejobtmpl.version,
  },

  metadata+: {
    annotations+: {
      'openshift.io/display-name': |||
        Job to deploy a letsencrypt controller.
      |||,
      description: |||
        Deploys a letsencrypt controller that secures OpenShift Routes with trusted certificates
        that are periodically refreshed. By default, the controller monitors and secures only
        routes in the SDI_NAMESPACE. That can be changed with the PROJECTS_TO_MONITOR parameter.
      |||,
    },
  },

  objects+: obssa { createdBy: acmejobtmpl.createdBy }.Objects + bc.objects,

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

  parameters+: bc.newParameters,
}
