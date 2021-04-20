{
  local is = self,
  resourceName:: error 'resourceName must be overridden by a child!',
  createdBy:: error 'createdBy must be overridden by a child!',
  version:: error 'version must be specified',

  apiVersion: 'v1',
  kind: 'ImageStream',
  metadata: {
    name: is.resourceName,
    namespace: '${NAMESPACE}',
    labels: {
      'created-by': is.createdBy,
      'sdi-observer/version': is.version,
    },
  },
  spec: null,
  status: {
    dockerImageRepository: '',
  },
}
