{
  ImageStream: {
    local is = self,
    resourceName:: error 'resourceName must be overridden by a child!',
    createdBy:: error 'createdBy must be overridden by a child!',

    apiVersion: 'v1',
    kind: 'ImageStream',
    metadata: {
      name: is.resourceName,
      namespace: '${NAMESPACE}',
      labels: {
        'created-by': is.createdBy,
      },
    },
    spec: null,
    status: {
      dockerImageRepository: '',
    },
  },
}
