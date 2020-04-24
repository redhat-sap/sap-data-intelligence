local params = import 'common-parameters.libsonnet';
local base = import 'dc-template.libsonnet';
local bctmpl = import 'ubi-buildconfig.libsonnet';

base.DCTemplate {
  local regtmpl = self,
  local container = super.objects[0].spec.template.spec.containers[0],
  resourceName: 'container-image-registry',
  imageStreamTag: regtmpl.resourceName + ':latest',
  parametersToExport+: [],

  local bc = bctmpl.BuildConfigTemplate {
    resourceName: regtmpl.resourceName,
    imageStreamTag: regtmpl.imageStreamTag,
    dockerfile: |||
      FROM openshift/ubi8:latest
      # docker-distribution is not yet available on UBI - install from fedora repo
      # RHEL8 / UBI8 is based on fedora 28
      ENV FEDORA_BASE_RELEASE=28
      RUN curl -L -o /etc/pki/rpms-fedora.gpg \
        https://getfedora.org/static/fedora.gpg
      RUN /bin/bash -c 'for repo in base updates; do printf "%s\n" \
          "[fedora-$repo]" \
          "name=Fedora $FEDORA_BASE_RELEASE - $(uname -m) - ${repo^}" \
          "metalink=https://mirrors.fedoraproject.org/metalink?repo=fedora-$FEDORA_BASE_RELEASE&arch=$(uname -m)" \
          "enabled=0" \
          "countme=1" \
          "type=rpm" \
          "gpgcheck=0" \
          "priority=99" \
          "gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-$FEDORA_BASE_RELEASE-$(uname -m)" \
          "skip_if_unavailable=False" >/etc/yum.repos.d/fedora-$repo.repo; \
        done'
      RUN dnf update -y
      # install the GPG keys first, so we can enable GPG keys checking for
      # the package in question
      RUN dnf install -y \
        --enablerepo=fedora-base \
        --enablerepo=fedora-updates \
        fedora-gpg-keys
      RUN sed -i 's/^\(gpgcheck=\)0/\11/' /etc/yum.repos.d/fedora-*.repo
      RUN dnf install -y \
        --enablerepo=fedora-base \
        --enablerepo=fedora-updates \
        docker-distribution
      RUN dnf clean all -y
      EXPOSE 5000
      ENTRYPOINT [ \
        "/usr/bin/registry", \
        "serve", "/etc/docker-distribution/registry/config.yml"]
    |||,
  },

  local addVolumes(object) = if object.kind == 'DeploymentConfig' then
    object {
      spec+: {
        template+: {
          spec+: {
            containers: [(c {
                            volumeMounts+: [
                              {
                                name: 'storage',
                                mountPath: '/var/lib/registry',
                              },
                              {
                                name: 'htpasswd',
                                mountPath: '/etc/docker-distribution/htpasswd',
                                readonly: true,
                                subPath: 'htpasswd',
                              },
                            ],
                          }) for c in object.spec.template.spec.containers],
            volumes+: [
              {
                name: 'storage',
                persistentVolumeClaim: {
                  claimName: regtmpl.resourceName,
                },
              },
              {
                name: 'htpasswd',
                secret: {
                  secretName: '${SDI_REGISTRY_HTPASSWD_SECRET_NAME}',
                },
                readonly: true,
              },
            ],
          },
        },
      },
    }
  else object,

  objects: [addVolumes(o) for o in super.objects] + [
    bc.bc,

    {
      apiVersion: 'v1',
      kind: 'ImageStream',
      metadata: {
        name: regtmpl.resourceName,
        namespace: '${NAMESPACE}',
      },
      spec: null,
      status: {
        dockerImageRepository: '',
      },
    },

    {
      apiVersion: 'v1',
      kind: 'Service',
      metadata: {
        annotations: {
          'template.openshift.io/expose-uri': |||
            https://{.spec.clusterIP}:{.spec.ports[?(.name=="registry")].port}
          |||,
        },
        name: regtmpl.resourceName,
        namespace: '${NAMESPACE}',
      },
      spec: {
        ports: [
          {
            name: 'registry',
            port: 5000,
          },
        ],
        selector: {
          deploymentconfig: regtmpl.resourceName,
        },
        sessionAffinity: 'ClientIP',
        type: 'ClusterIP',
      },
    },

    {
      apiVersion: 'route.openshift.io/v1',
      kind: 'Route',
      metadata: {
        annotations: {
          'template.openshift.io/expose-uri': 'https://{.spec.host}{.spec.path}',
        },
        name: regtmpl.resourceName,
        namespace: '${NAMESPACE}',
      },
      spec: {
        host: '${SDI_REGISTRY_ROUTE_HOSTNAME}',
        port: {
          targetPort: 'registry',
        },
        subdomain: '',
        tls: {
          insecureEdgeTerminationPolicy: 'Redirect',
          termination: 'edge',
        },
        to: {
          kind: 'Service',
          name: regtmpl.resourceName,
        },
      },
    },

    {
      apiVersion: 'v1',
      kind: 'PersistentVolumeClaim',
      metadata: {
        name: regtmpl.resourceName,
        namespace: '${NAMESPACE}',
      },
      spec: {
        accessModes: [
          'ReadWriteOnce',
        ],
        resources: {
          requests: {
            storage: '${SDI_REGISTRY_VOLUME_CAPACITY}',
          },
        },
      },
    },
  ],


  additionalEnvironment+: [
    {
      name: 'REGISTRY_AUTH_HTPASSWD_REALM',
      value: 'basic-realm',
    },
    {
      name: 'REGISTRY_AUTH_HTPASSWD_PATH',
      value: '/etc/docker-distribution/htpasswd',
    },
    {
      name: 'REGISTRY_HTTP_SECRET',
      value: '${SDI_REGISTRY_HTTP_SECRET}',
    },
  ],

  parameters+: bc.newParameters + params.RegistryParams,
}
