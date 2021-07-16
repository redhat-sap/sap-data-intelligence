local params = import 'common-parameters.libsonnet';

local usePrebuiltImage(tmpl, version) = tmpl {
  local arrayHasName(arr, name) = std.foldl(
    local checkVarName(p, e) = if p then p else e.name == name;
    checkVarName, arr, false
  ),

  // TODO: filter out by a hidden field in parameter objects e.g. Online / Offline
  local onlineParams = std.flattenArrays([
    params.ObserverBuildParams,

    params.RegistryParams,
    [params.RegistryDeployParam],
    params.RegistryDeployParams,
    [params.ReplacePersistentVolumeClaimsParam],

    params.RedHatRegistrySecretParams,

    [params.ExposeWithLetsencryptParam],
    [params.LetsencryptDeployParam],
    params.LetsencryptParams,
  ]),

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
                name: version + '-ocp${OCP_MINOR_RELEASE}',
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
                    env: params.FilterOut(onlineParams, c.env) + [
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
    if ((o.kind != 'ImageStream') || (o.metadata.name != 'ubi8')) && (o.kind != 'BuildConfig')
  ],

  local tmplParams = super.parameters,
  parameters: params.FilterOut(onlineParams, tmplParams) + [
    {
      description: |||
        Pull specification of a prebuilt image of SDI Observer. If the registry requires
        authentication, a pull secret must be created and linked with the %(saName)s service
        account.
      ||| % {
        saName: tmpl.saName,
      },
      name: 'IMAGE_PULL_SPEC',
      required: true,
      value: 'quay.io/redhat-sap-cop/sdi-observer:%(version)s-ocp%(ocpMinorRelease)s' % {
        version: version,
        ocpMinorRelease: params.OCPMinorReleaseParam.value,
      },
    },
  ],
};

usePrebuiltImage
