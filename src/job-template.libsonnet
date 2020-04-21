local params = import 'common-parameters.libsonnet';
local base = import 'ocp-template.libsonnet';

{
  JobTemplate: base.OCPTemplate {
    local jobtmpl = self,
    resourceName:: error 'resourceName must be overriden!',
    command:: error 'command must be overriden!',
    args:: '${SCRIPT_ARGUMENTS}',
    jobImage:: 'JOB_IMAGE',
    parametersToExport:: super.parameters + [
      params.ForceRedeployParam,
      params.ReplaceSecretsParam,
    ],

    objects+: [
      {
        apiVersion: 'batch/v1',
        kind: 'CronJob',
        metadata: {
          name: jobtmpl.resourceName,
          namespace: '${NAMESPACE}',
        },
        spec: {
          completions: 1,
          jobTemplate: {
            metadata: {
              labels: {
                job: jobtmpl.resourceName,
              },
            },
            spec: {
              template: {
                spec: {
                  containers: [
                    {
                      args: jobtmpl.args,
                      command: if std.isString(jobtmpl.command) then
                        [jobtmpl.command]
                      else if std.isArray(jobtmpl.command) then
                        jobtmpl.command
                      else
                        error 'command must be either string or array!',

                      env: [{
                        name: p.name,
                        value: '${' + p.name + '}',
                      } for p in jobtmpl.parametersToExport],
                      image: '${JOB_IMAGE}',
                      name: 'deploy-sdi-registry',
                    },
                  ],
                  restartPolicy: 'OnFailure',
                  serviceAccountName: jobtmpl.resourceName,
                },
              },
            },
          },
          parallelism: 1,
        },
      },
    ],

    parameters: jobtmpl.parametersToExport + [
      {
        description: 'Pull specification of the built SDI Observer image.\n',
        name: 'JOB_IMAGE',
        required: true,
        value: if jobtmpl.jobImage != 'JOB_IMAGE' then jobtmpl.jobImage,
      },
      {
        description: |||
          Arguments for job's script. Passed as a json array of strings.
        |||,
        name: 'SCRIPT_ARGUMENTS',
        required: true,
        value: if jobtmpl.args != '${SCRIPT_ARGUMENTS}' then jobtmpl.args,
      },
    ],
  },
}
