local params = import 'common-parameters.libsonnet';
local urls = import 'urls.jsonnet';

// Base OpenShift Template class
{
  local template = self,
  resourceName:: error 'resourceName must be overriden by a child',
  version:: error 'version must be specified',

  apiVersion: 'template.openshift.io/v1',
  kind: 'Template',
  message: null,
  metadata: {
    annotations: {
      description: error 'description must be specified',
      'openshift.io/display-name': error 'display-name must be set',
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
        The desired namespace to deploy resources to. Defaults to the current one.
      |||,
      name: 'NAMESPACE',
      required: true,
    },
    params.DryRun,
  ],
}
