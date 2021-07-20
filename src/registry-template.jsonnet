local params = import 'common-parameters.libsonnet';
local base = import 'dc-template.libsonnet';
local bctmpl = import 'ubi-buildconfig.libsonnet';
local urls = import 'urls.jsonnet';

base {
  local regtmpl = self,
  local container = super.objects[0].spec.template.spec.containers[0],
  resourceName: 'container-image-registry',
  createdBy: 'registry-template',
  version:: error 'version must be specified',
  imageStreamTag: regtmpl.resourceName + ':latest',

  metadata+: {
    annotations+: {
      description: |||
        Generic purpose Container Image Registry secured from unauthorized access. It is more
        tolerant to image names than the integrated OpenShift image registry. Therefore it also
        allows for hosting of SAP Data Intelligence images.
      |||,
      'openshift.io/display-name': "Docker's Container Image Registry",
      'openshift.io/provider-display-name': 'Red Hat, Inc.',
      // TODO: update KB article when published
      'openshift.io/documentation-url': urls.rhtKbSdhOnOCP4,
    },
  },

  local bc = bctmpl {
    resourceName:: regtmpl.resourceName,
    imageStreamTag:: regtmpl.imageStreamTag,
    createdBy:: regtmpl.createdBy,
    version:: regtmpl.version,

    dockerfile:: |||
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
      RUN dnf update -y --skip-broken --nobest ||:
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

  imagePullSpecParam+: {
    description: |||
      Pull specification of a prebuilt image of container image registry (aka SDI Registry). If
      this param's registry requires authentication, a pull secret must be created and linked with
      the %(saName)s service account.
    ||| % {
      saName: regtmpl.saName,
    },
    value: 'quay.io/redhat-sap-cop/container-image-registry:%(version)s' % {
      version: regtmpl.version,
      ocpMinorRelease: params.OCPMinorReleaseParam.value,
    },
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

  local addPortAndProbes(object) = if object.kind == 'DeploymentConfig' then
    local probe = {
      failureThreshold: 3,
      httpGet: {
        path: '/',
        port: 5000,
        scheme: 'HTTP',
      },
      periodSeconds: 10,
      successThreshold: 1,
      timeoutSeconds: 5,
    };
    object {
      spec+: {
        template+: {
          spec+: {
            containers: [(c {
                            ports: [{
                              containerPort: 5000,
                              protocol: 'TCP',
                            }],
                            livenessProbe: probe,
                            readinessProbe: probe,
                          }) for c in object.spec.template.spec.containers],
          },
        },
      },
    }
  else object,

  objects: [addVolumes(addPortAndProbes(o)) for o in super.objects] + bc.objects
           + [
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
                 labels: {
                   app: regtmpl.resourceName,
                   deploymentconfig: regtmpl.resourceName,
                   'created-by': regtmpl.createdBy,
                 },
               },
               spec: {
                 ports: [
                   {
                     name: 'registry',
                     port: 5000,
                   },
                 ],
                 selector: {
                   // TODO: switch to app=... in some newer tag (1.13+)
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
                 labels: {
                   app: regtmpl.resourceName,
                   deploymentconfig: regtmpl.resourceName,
                   'created-by': regtmpl.createdBy,
                 },
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
                 app: regtmpl.resourceName,
                 deploymentconfig: regtmpl.resourceName,
                 'created-by': regtmpl.createdBy,
               },
               spec: {
                 accessModes: ['${SDI_REGISTRY_VOLUME_ACCESS_MODE}'],
                 // the default value "" cannot be used - no PV gets bound
                 //storageClassName: '${{SDI_REGISTRY_STORAGE_CLASS_NAME}}',
                 resources: {
                   requests: {
                     storage: '${SDI_REGISTRY_VOLUME_CAPACITY}',
                   },
                 },
                 // NOTE: Dynamically provisioned volumes are always deleted.
                 persistentVolumeReclaimPolicy: 'Retain',
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

  parametersToExport: [
    p
    for p in super.parametersToExport
    if p.name != 'DRY_RUN' && p.name != 'NAMESPACE'
  ],
  parameters+: [p for p in super.parametersToExport if p.name == 'NAMESPACE']
               + bc.newParameters + params.RegistryParams,
}
