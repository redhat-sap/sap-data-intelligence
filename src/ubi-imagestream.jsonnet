{
  UBIImageStream: {
    apiVersion: 'v1',
    kind: 'ImageStream',
    metadata: {
      name: 'ubi8',
      namespace: '${NAMESPACE}',
    },
    spec: {
      tags: [
        {
          from: {
            kind: 'DockerImage',
            name: 'registry.redhat.io/ubi8/ubi:latest',
          },
          name: 'latest',
          referencePolicy: {
            type: 'Source',
          },
        },
      ],
    },
    status: {
      dockerImageRepository: '',
    },
  },
}
