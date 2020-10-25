local urls = import 'urls.jsonnet';

// Base OpenShift Template class
{
  OCPTemplate: {
    local template = self,
    resourceName:: error 'resourceName must be overriden by a child',
    version:: error 'version must be specified',

    apiVersion: 'template.openshift.io/v1',
    kind: 'Template',
    message: 'TODO',
    metadata: {
      annotations: {
        description: 'TODO',
        'openshift.io/display-name': 'TODO',
        'openshift.io/documentation-url': urls.rhtKbSdhOnOCP4,
        'openshift.io/provider-display-name': 'Red Hat, Inc.',
        'sdi-observer/version': template.version,
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
