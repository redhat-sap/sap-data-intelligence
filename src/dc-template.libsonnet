local params = import 'common-parameters.libsonnet';
local obssa = import 'observer-serviceaccount.libsonnet';
local base = import 'ocp-template.libsonnet';

{
  DCTemplate: base.OCPTemplate {
    local dctmpl = self,
    imageStreamTag:: error 'imageStreamTag must be overriden!',
    parametersToExport:: super.parameters,
    additionalEnvironment:: [],
    command:: null,
    args:: null,
    createdBy:: error 'createdBy must be overriden by a child!',

    sa:: {
      apiVersion: 'v1',
      kind: 'ServiceAccount',
      metadata: {
        labels: {
          deploymentconfig: dctmpl.resourceName,
          'created-by': dctmpl.createdBy,
        },
        name: dctmpl.resourceName,
        namespace: '${NAMESPACE}',
      },
    },

    objects+: [
      dctmpl.sa,

      {
        apiVersion: 'v1',
        kind: 'DeploymentConfig',
        metadata: {
          labels: {
            deploymentconfig: dctmpl.resourceName,
            'created-by': dctmpl.createdBy,
            'sdi-observer/version': dctmpl.version,
          },
          name: dctmpl.resourceName,
          namespace: '${NAMESPACE}',
        },
        spec: {
          replicas: 1,
          selector: {
            deploymentconfig: dctmpl.resourceName,
          },
          strategy: {
            type: 'Rolling',
          },
          template: {
            metadata: {
              labels: {
                deploymentconfig: dctmpl.resourceName,
              },
            },
            spec: {
              containers: [
                {
                  env: [
                         {
                           name: 'SDI_OBSERVER_VERSION',
                           value: dctmpl.version,
                         },
                       ] + [
                         {
                           name: p.name,
                           value: '${' + p.name + '}',
                         }
                         for p in dctmpl.parametersToExport
                       ]
                       + dctmpl.additionalEnvironment,
                  image: ' ',
                  name: dctmpl.resourceName,
                  command: if std.isArray(dctmpl.command) then
                    dctmpl.command
                  else if dctmpl.command != null then
                    [dctmpl.command],
                  args: dctmpl.args,
                },
              ],
              restartPolicy: 'Always',
              serviceAccount: dctmpl.resourceName,
              serviceAccountName: dctmpl.resourceName,
            },
          },
          triggers: [
            {
              type: 'ConfigChange',
            },
            {
              imageChangeParams: {
                automatic: true,
                containerNames: [
                  dctmpl.resourceName,
                ],
                from: {
                  kind: 'ImageStreamTag',
                  name: dctmpl.imageStreamTag,
                },
              },
              type: 'ImageChange',
            },
          ],
        },
      },
    ],
    parameters: dctmpl.parametersToExport,
  },

}
