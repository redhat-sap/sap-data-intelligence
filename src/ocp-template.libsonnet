// Base OpenShift Template class
{
  OCPTemplate: {
    local template = self,
    resourceName:: error 'resourceName must be overriden by a child',

    apiVersion: 'template.openshift.io/v1',
    kind: 'Template',
    message: 'TODO',
    metadata: {
      annotations: {
        description: 'TODO',
        'openshift.io/display-name': 'TODO',
        'openshift.io/documentation-url':
          'https://access.redhat.com/articles/4324391',
        'openshift.io/provider-display-name': 'Red Hat, Inc.',
      },
      name: template.resourceName,
    },
    objects: [],
    parameters: [
      {
        description: |||
          If set to true, no action will be performed. The pod will just print
          what would have been executed.
        |||,
        name: 'DRY_RUN',
        required: false,
        value: 'false',
      },
      {
        description: |||
          The desired namespace to deploy resources to. Defaults to the current
          one.
        |||,
        name: 'NAMESPACE',
        required: true,
      },
    ],
  },
}
