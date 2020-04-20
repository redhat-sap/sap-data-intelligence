{
  JobTemplate: base.OCPTemplate {
    imageStreamTag:: error 'imageStreamTag must be overriden!',

    objects+: [
      {
        apiVersion: 'batch/v1',
        kind: 'CronJob',
        metadata: {
          name: 'deploy-sdi-registry',
          namespace: '${NAMESPACE}',
        },
        spec: {
          completions: 1,
          jobTemplate: {
            metadata: {
              labels: {
                job: self.resourceName,
              },
            },
            spec: {
              template: {
                spec: {
                  containers: [
                    {
                      args: '${SCRIPT_ARGUMENTS}',
                      command: [
                        'deploy-registry.sh',
                      ],
                      env: [
                        {
                          name: 'DRY_RUN',
                          value: '${DRY_RUN}',
                        },
                        {
                          name: 'NAMESPACE',
                          value: '${NAMESPACE}',
                        },
                        {
                          name: 'FORCE_REDEPLOY',
                          value: '${FORCE_REDEPLOY}',
                        },
                        {
                          name: 'RECREATE_SECRETS',
                          value: '${RECREATE_SECRETS}',
                        },
                        {
                          name: 'FORCE_REDEPLOY',
                          value: '${FORCE_REDEPLOY}',
                        },
                        {
                          name: 'RECREATE_SECRETS',
                          value: '${RECREATE_SECRETS}',
                        },
                        {
                          name: 'EXPOSE_WITH_LETSENCRYPT',
                          value: '${EXPOSE_WITH_LETSENCRYPT}',
                        },
                        {
                          name: 'SDI_REGISTRY_VOLUME_CAPACITY',
                          value: '${SDI_REGISTRY_VOLUME_CAPACITY}',
                        },
                        {
                          name: 'SDI_REGISTRY_STORAGE_CLASS_NAME',
                          value: '${SDI_REGISTRY_STORAGE_CLASS_NAME}',
                        },
                        {
                          name: 'SDI_REGISTRY_HTPASSWD_SECRET_NAME',
                          value: '${SDI_REGISTRY_HTPASSWD_SECRET_NAME}',
                        },
                        {
                          name: 'SDI_REGISTRY_USERNAME',
                          value: '${SDI_REGISTRY_USERNAME}',
                        },
                        {
                          name: 'SDI_REGISTRY_PASSWORD',
                          value: '${SDI_REGISTRY_PASSWORD}',
                        },
                      ],
                      image: '${SDI_OBSERVER_IMAGE}',
                      name: 'deploy-sdi-registry',
                    },
                  ],
                  restartPolicy: 'OnFailure',
                  serviceAccountName: 'sdi-observer',
                },
              },
            },
          },
          parallelism: 1,
        },
      },
    ],
    parameters: [
      {
        description: 'If set to true, no action will be performed. The pod will just print what would have been executed.\n',
        name: 'DRY_RUN',
        required: false,
        value: 'false',
      },
      {
        description: 'The desired namespace, where the registry shall be deployed. Defaults to the current one.\n',
        name: 'NAMESPACE',
        required: false,
      },
      {
        description: 'Pull specification of the built SDI Observer image.\n',
        name: 'SDI_OBSERVER_IMAGE',
        required: true,
      },
      {
        description: 'Whether to forcefully replace existing registry and/or letsencrypt deployments and configuration files.\n',
        name: 'FORCE_REDEPLOY',
        required: false,
        value: 'false',
      },
      {
        description: "Whether to replace secrets like SDI Registry's htpasswd file if they exist already.\n",
        name: 'RECREATE_SECRETS',
        required: false,
        value: 'false',
      },
      {
        description: 'Whether to expose routes annotated for letsencrypt controller. Requires project admin role attached to the sdi-observer service account. Letsencrypt controller must be deployed either via this observer or cluster-wide for this to have an effect. Defaults to DEPLOY_LETSENCRYPT.\n',
        name: 'EXPOSE_WITH_LETSENCRYPT',
        value: 'false',
      },
      {
        description: 'Volume space available for container images (e.g. 75Gi).',
        name: 'SDI_REGISTRY_VOLUME_CAPACITY',
        required: true,
        value: '75Gi',
      },
      {
        description: 'Unless given, the default storage class will be used.\n',
        name: 'SDI_REGISTRY_STORAGE_CLASS_NAME',
        required: false,
      },
      {
        description: 'A secret with htpasswd file with authentication data for the sdi image container If given and the secret exists, it will be used instead of SDI_REGISTRY_USERNAME and SDI_REGISTRY_PASSWORD.\n',
        name: 'SDI_REGISTRY_HTPASSWD_SECRET_NAME',
        required: false,
      },
      {
        from: 'user-[a-z0-9]{6}',
        generage: 'expression',
        name: 'SDI_REGISTRY_USERNAME',
        required: false,
      },
      {
        from: 'user-[a-zA-Z0-9]{32}',
        generage: 'expression',
        name: 'SDI_REGISTRY_PASSWORD',
        required: false,
      },
    ],
  },
}
