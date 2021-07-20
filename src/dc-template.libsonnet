local params = import 'common-parameters.libsonnet';
local obssa = import 'observer-serviceaccount.libsonnet';
local base = import 'ocp-template.libsonnet';

base {
  local dctmpl = self,
  imageStreamTag:: error 'imageStreamTag must be overriden!',
  parametersToExport:: super.parameters,
  additionalEnvironment:: [],
  command:: null,
  args:: null,
  createdBy:: error 'createdBy must be overriden by a child!',
  requests:: {
    cpu: '100m',
    memory: '256Mi',
  },
  limits:: {
    cpu: '500m',
    memory: '768Mi',
  },

  sa:: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: {
      labels: {
        app: dctmpl.resourceName,
        deploymentconfig: dctmpl.resourceName,
        'created-by': dctmpl.createdBy,
      },
      name: dctmpl.resourceName,
      namespace: '${NAMESPACE}',
    },
  },

  imagePullSpecParam:: params.Param {
    description: error 'description must be overriden by a child!',
    name: 'IMAGE_PULL_SPEC',
    required: true,
    value: error 'imagePullSpecParam.value must be overriden by a child!',
  },

  saName:: local sas = [o.metadata.name for o in dctmpl.objects if o.kind == 'ServiceAccount'];
          if sas == [] then 'default' else sas[0],

  objects+: [
    dctmpl.sa,

    {
      apiVersion: 'v1',
      kind: 'DeploymentConfig',
      metadata: {
        labels: {
          app: dctmpl.resourceName,
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
          // TODO: replace with app: in a future release
          deploymentconfig: dctmpl.resourceName,
        },
        strategy: {
          type: 'Rolling',
        },
        template: {
          metadata: {
            labels: {
              app: dctmpl.resourceName,
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
                resources: {
                  requests: dctmpl.requests,
                  limits: dctmpl.limits,
                },
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
}
