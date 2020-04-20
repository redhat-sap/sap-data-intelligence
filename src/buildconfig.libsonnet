{
  BuildConfig: {
    local bctmpl = self,
    resourceName:: error 'resourcename must be overriden by a child',
    srcImageStreamTag:: error 'srcImageStreamTag must be overriden by a child!',
    dstImageStreamTag:: error 'dstImageStreamTag must be overriden by a child!',
    dockerfile:: error 'dockerfile must be overriden by a child!',

    apiVersion: 'build.openshift.io/v1',
    kind: 'BuildConfig',
    metadata: {
      labels: {
        deploymentconfig: bctmpl.resourceName,
      },
      name: bctmpl.resourceName,
      namespace: '${NAMESPACE}',
    },
    spec: {
      output: {
        to: {
          kind: 'ImageStreamTag',
          name: bctmpl.dstImageStreamTag,
        },
      },
      runPolicy: 'Serial',
      source: {
        dockerfile: bctmpl.dockerfile,
      },
      strategy: {
        dockerStrategy: {
          from: {
            kind: 'ImageStreamTag',
            name: bctmpl.srcImageStreamTag,
          },
        },
      },
      triggers: [
        {
          type: 'ImageChange',
        },
        {
          type: 'ConfigChange',
        },
      ],
    },
  },
}
