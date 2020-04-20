local base = import 'dc-template.libsonnet';
local bctmpl = import 'ubi-buildconfig.libsonnet';

base.DCTemplate {
  local regtmpl = self,
  resourceName: 'container-image-registry',
  imageStreamTag: regtmpl.resourceName + ':latest',

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

  objects+: [
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
          'template.openshift.io/expose-uri': '"https://{.spec.clusterIP}:{.spec.ports[?(.name==\\"registry\\")].port)}"',
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
        host: '${HOSTNAME}',
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
            storage: '${VOLUME_CAPACITY}',
          },
        },
      },
    },
  ],

  parameters+: bc.newParameters + [
    {
      description: 'Volume space available for container images (e.g. 75Gi).',
      name: 'VOLUME_CAPACITY',
      required: true,
      value: '75Gi',
    },
    {
      name: 'HTPASSWD_SECRET_NAME',
      required: true,
      value: regtmpl.resourceName + '-htpasswd',
    },
    {
      from: '[a-zA-Z0-9]{32}',
      generage: 'expression',
      name: 'REGISTRY_HTTP_SECRET',
    },
    {
      description: |||
        Desired domain name of the exposed registry service.'
      |||,
      name: 'HOSTNAME',
      required: false,
    },
  ],
}
