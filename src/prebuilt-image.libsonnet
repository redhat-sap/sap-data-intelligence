local params = import 'common-parameters.libsonnet';

local usePrebuiltImage(tmpl, version) = tmpl {
  local arrayHasName(arr, name) = std.foldl(
    local checkVarName(p, e) = if p then p else e.name == name;
    checkVarName, arr, false
  ),

  local onlineOnlyCommonParams = std.flattenArrays([
    params.ObserverBuildParams,
    params.RedHatRegistrySecretParams,

    [params.ExposeWithLetsencryptParam],
    [params.LetsencryptDeployParam],
    params.LetsencryptParams,

    [params.RegistryDeployParam],
    params.RegistryDeployParams,
  ]),

  // TODO: filter out by a hidden field in parameter objects e.g. Online / Offline
  local onlineOnlyObserverParams = std.flattenArrays([
    params.RegistryParams,
    [params.ReplacePersistentVolumeClaimsParam],
  ]),

  local onlineOnlyParams = std.flattenArrays(
    [
      onlineOnlyCommonParams,
      if tmpl.metadata.name == 'sdi-observer' then
        onlineOnlyObserverParams
      else
        [],
    ]
  ),

  tags: {
    online: false,
    offline: true,
  },

  objects: [
    (
      if (o.kind == 'ImageStream') then
        o {
          local ismeta = super.metadata,
          metadata+: {
            labels+: {
              'sdi-observer/version': version,
            },
          },
          spec: {
            tags: [
              {
                from: {
                  kind: 'DockerImage',
                  name: '${IMAGE_PULL_SPEC}',
                },
                importPolicy: {
                  scheduled: true,
                },
                name: std.split(tmpl.imageStreamTag, ':')[1],
                referencePolicy: {
                  type: 'Source',
                },
              },
            ],
          },
        }
      else if o.kind == 'Job' || o.kind == 'DeploymentConfig' || o.kind == 'Deployment' then
        o {
          metadata+: {
            labels+: {
              'sdi-observer/version': version,
            },
          },
          spec+: {
            template+: {
              spec+: {
                containers: [
                  c {
                    env: params.FilterOut(onlineOnlyParams, c.env) + [
                      {
                        name: 'SOURCE_IMAGE_PULL_SPEC',
                        value: '${IMAGE_PULL_SPEC}',
                      },
                    ],
                  }
                  for c in super.containers
                ],
              },
            },
          },
        }
      else o
    )

    for o in tmpl.objects
    if ((o.kind != 'ImageStream') || (o.metadata.name != 'ubi9')) && (o.kind != 'BuildConfig')
  ],

  local tmplParams = super.parameters,
  parameters: params.FilterOut(onlineOnlyParams, tmplParams) + [
    tmpl.imagePullSpecParam,
  ],
};

usePrebuiltImage
