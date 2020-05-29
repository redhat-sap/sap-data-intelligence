local useCustomSourceImage(tmpl, withSecret=false) = tmpl {
  local arrayHasName(arr, name) = std.foldl(
    local checkVarName(p, e) = if p then p else e.name == name;
    checkVarName, arr, false
  ),

  objects: [
    (
      if (o.kind == 'ImageStream') && (o.metadata.name == 'ubi8') then
        o {
          metadata+: {
            name: '${SOURCE_IMAGESTREAM_NAME}',
          },
          spec+: {
            tags: [
              {
                from: {
                  kind: 'DockerImage',
                  name: '${SOURCE_IMAGE_PULL_SPEC}',
                },
                importPolicy: {
                  scheduled: true,
                },
                name: '${SOURCE_IMAGESTREAM_TAG}',
                referencePolicy: {
                  type: 'Source',
                },
              },
            ],
          },
        }
      else if o.kind == 'BuildConfig' then
        o {
          spec+: {
            strategy+: {
              dockerStrategy: {
                from: {
                  kind: 'ImageStreamTag',
                  name: '${SOURCE_IMAGESTREAM_NAME}:${SOURCE_IMAGESTREAM_TAG}',
                },
              } + (if withSecret then {
                     pullSecret: {
                       name: '${SOURCE_IMAGE_REGISTRY_SECRET_NAME}',
                     },
                   } else {}),
            },
          },
        }
      else
        if o.kind == 'Job' || o.kind == 'DeploymentConfig' then
          o {
            spec+: {
              template+: {
                spec+: {
                  local containers = super.containers,
                  containers: [
                    c {
                      env: [
                        (if e.name == 'REDHAT_REGISTRY_SECRET_NAME' then
                           {
                             name: 'SOURCE_IMAGE_REGISTRY_SECRET_NAME',
                             value: '${SOURCE_IMAGE_REGISTRY_SECRET_NAME}',
                           }
                         else e)
                        for e in c.env
                        if withSecret || e.name != 'REDHAT_REGISTRY_SECRET_NAME'
                      ] + (if arrayHasName(c.env, 'REDHAT_REGISTRY_SECRET_NAME') then
                             [
                               {
                                 name: 'SOURCE_IMAGESTREAM_NAME',
                                 value: '${SOURCE_IMAGESTREAM_NAME}',
                               },
                               {
                                 name: 'SOURCE_IMAGESTREAM_TAG',
                                 value: '${SOURCE_IMAGESTREAM_TAG}',
                               },
                               {
                                 name: 'SOURCE_IMAGE_PULL_SPEC',
                                 value: '${SOURCE_IMAGE_PULL_SPEC}',
                               },
                             ] + (if withSecret then
                                    [{
                                      name: 'SOURCE_IMAGE_REGISTRY_SECRET_NAME',
                                      value: '${SOURCE_IMAGE_REGISTRY_SECRET_NAME}',
                                    }]
                                  else [])
                           else []),
                    }
                    for c in containers
                  ],
                },
              },
            },
          }
        else o
    )
    for o in tmpl.objects
  ],

  local params = super.parameters,
  parameters: [
    (if p.name == 'REDHAT_REGISTRY_SECRET_NAME' then
       p {
         description: |||
           Name of the secret with credentials for the custom source image registry.
         |||,
         name: 'SOURCE_IMAGE_REGISTRY_SECRET_NAME',
       }
     else if p.name == 'DEPLOY_SDI_REGISTRY' then
       p {
         description: |||
           Whether to deploy container image registry for the purpose of SAP Data Intelligence.
           Requires project admin role attached to the sdi-observer service account.
         ||| + (if withSecret then
                  'If enabled, SOURCE_IMAGE_REGISTRY_SECRET_NAME must be provided.'
                else ''),
       }
     else
       p)
    for p in params
    if withSecret || p.name != 'REDHAT_REGISTRY_SECRET_NAME'
  ] + [
    {
      description: |||
        Pull specification for the base image for sdi-observer and/or container-image-registry.
        The base image shall be RPM based and contain "dnf" binary for package management.
      |||,
      name: 'SOURCE_IMAGE_PULL_SPEC',
      required: true,
      value: 'registry.centos.org/centos:8',
    },
    {
      description: |||
        Name of the imagestream to use for the custom source image.
      |||,
      name: 'SOURCE_IMAGESTREAM_NAME',
      required: true,
      value: 'centos8',
    },
    {
      description: |||
        Tag in the custom source imagestream referring to the SOURCE_IMAGE_PULL_SPEC.
      |||,
      name: 'SOURCE_IMAGESTREAM_TAG',
      required: true,
      value: 'latest',
    },
  ],
};

useCustomSourceImage
