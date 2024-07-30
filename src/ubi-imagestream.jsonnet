local is = import 'imagestream.libsonnet';

is {
  local ubiis = self,
  resourceName: 'ubi9',
  createdBy:: error 'createdBy must be overridden by a child!',

  spec: {
    lookupPolicy: {
      'local': true,
    },
    tags: [
      {
        from: {
          kind: 'DockerImage',
          name: 'registry.redhat.io/ubi9/ubi:latest',
        },
        name: 'latest',
        referencePolicy: {
          type: 'Source',
        },
        importPolicy: {
          scheduled: true,
        },
      },
    ],
  },
}
