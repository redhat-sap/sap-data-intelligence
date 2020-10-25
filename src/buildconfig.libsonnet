local is = import 'imagestream.libsonnet';

{
  local bc = self,
  resourceName:: error 'resourceName must be overriden by a child',
  createdBy:: error 'createdBy must be overridden by a child!',
  srcImageStreamTag:: error 'srcImageStreamTag must be overriden by a child!',
  dstImageStreamTag:: $.resourceName + ':latest',
  dockerfile:: error 'dockerfile must be overriden by a child!',
  version:: error 'version must be specified',

  Objects: [$.BuildConfig, $.ImageStream],

  BuildConfig: {
    apiVersion: 'build.openshift.io/v1',
    kind: 'BuildConfig',
    metadata: {
      labels: {
        deploymentconfig: $.resourceName,
        'created-by': $.createdBy,
        'sdi-observer/version': bc.version,
      },
      name: $.resourceName,
      namespace: '${NAMESPACE}',
    },
    spec: {
      output: {
        to: {
          kind: 'ImageStreamTag',
          name: $.dstImageStreamTag,
        },
      },
      runPolicy: 'Serial',
      source: {
        dockerfile: $.dockerfile,
      },
      strategy: {
        dockerStrategy: {
          from: {
            kind: 'ImageStreamTag',
            name: $.srcImageStreamTag,
          },
          imageOptimizationPolicy: 'SkipLayers',
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

  ImageStream: is.ImageStream {
    resourceName: $.resourceName,
    createdBy: $.createdBy,
  },
}
