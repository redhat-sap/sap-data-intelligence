local params = import 'common-parameters.libsonnet';
local base = import 'ocp-template.libsonnet';

{
  JobTemplate: base.OCPTemplate {
    local jobtmpl = self,
    resourceName:: error 'resourceName must be overriden!',
    command:: error 'command must be overriden!',
    defaultArguments:: ['--wait'],
    args:: null,
    jobImage:: 'JOB_IMAGE',
    parametersToExport:: super.parameters + [
      params.ForceRedeployParam,
      params.ReplaceSecretsParam,
    ],

    objects+: [
      {
        apiVersion: 'batch/v1',
        kind: 'Job',
        metadata: {
          name: jobtmpl.resourceName,
          namespace: '${NAMESPACE}',
        },
        spec: {
          activeDeadlineSeconds: 30 * 60,
          backoffLimit: 9999,
          completions: 1,
          metadata: {
            labels: {
              job: jobtmpl.resourceName,
            },
          },
          template: {
            spec: {
              containers: [
                {
                  args: '${{SCRIPT_ARGUMENTS}}',
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
              serviceAccountName: 'sdi-observer',
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
        required: false,
        value: std.toString(
          jobtmpl.defaultArguments
          + if jobtmpl.args != null then jobtmpl.args else []
        ),
      },
    ],
  },
}
