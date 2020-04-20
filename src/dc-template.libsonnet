local base = import 'ocp-template.libsonnet';

{
  DCTemplate: base.OCPTemplate {
    local dctmpl = self,
    imageStreamTag:: error 'imageStreamTag must be overriden!',

    objects+: [
      {
        apiVersion: 'v1',
        kind: 'DeploymentConfig',
        metadata: {
          labels: {
            deploymentconfig: dctmpl.resourceName,
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
                  env: [],
                  image: ' ',
                  name: dctmpl.resourceName,
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

      {
        apiVersion: 'v1',
        kind: 'ServiceAccount',
        metadata: {
          labels: {
            deploymentconfig: dctmpl.resourceName,
          },
          name: dctmpl.resourceName,
          namespace: '${NAMESPACE}',
        },
      },
    ],
  },
}
