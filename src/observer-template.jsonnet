local base = import 'dc-template.libsonnet';
local bctmpl = import 'ubi-buildconfig.libsonnet';

base.DCTemplate {
  local obstmpl = self,
  resourceName: 'sdi-observer',
  imageStreamTag: obstmpl.resourceName + ':${OCP_MINOR_RELEASE}',

  local bc = bctmpl.BuildConfigTemplate {
    resourceName: obstmpl.resourceName,
    imageStreamTag: obstmpl.imageStreamTag,
    dockerfile: |||
      FROM openshift/cli:latest
      RUN dnf update -y
      # TODO: jq is not yet available in EPEL-8
      RUN dnf install -y \
        https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm && \
        dnf install -y jq
      RUN dnf install -y \
        https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm && \
        dnf install -y parallel procps-ng bc git && dnf clean all -y
      # TODO: determine OCP version from environment
      COPY https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest-${OCP_MINOR_RELEASE}/openshift-client-linux.tar.gz /tmp/
      COPY https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest-${OCP_MINOR_RELEASE}/sha256sum.txt /tmp/
      # verify the downloaded tar
      RUN /bin/bash -c 'grep "$(awk '"'"'{print $1}'"'"' \
        <(sha256sum /tmp/openshift-client-linux.tar.gz))[[:space:]]\+openshift-client-linux-." \
        /tmp/sha256sum.txt'
      RUN /bin/bash -c 'tar -C /usr/local/bin/ -xzvf /tmp/openshift-client-linux.tar.gz -T <(printf oc)'
      # TODO: verify signatures as well
      RUN mkdir -p /usr/local/bin \
        /usr/local/share/{sdi-observer,openshift-acme}
      RUN git clone --depth 5 --single-branch \
        --branch ${LETSENCRYPT_REVISION} \
        ${LETSENCRYPT_REPOSITORY} /usr/local/share/openshift-acme
      RUN git clone --depth 5 --single-branch \
        --branch ${SDI_OBSERVER_GIT_REVISION} \
        ${SDI_OBSERVER_REPOSITORY} /usr/local/share/sap-data-intelligence
      RUN for bin in observer.sh deploy-registry.sh deploy-letsencrypt.sh; do \
            cp -lv /usr/local/share/sap-data-intelligence/$bin \
              /usr/local/bin/$bin; \
            chmod a+rx /usr/local/bin/$bin; \
          done
      RUN ln -s /usr/local/share/sap-data-intelligence/observer \
        /usr/local/share/sdi-observer
      WORKDIR /usr/local/share/sdi-observer
    |||,
  },

  metadata+: {
    annotations+: {
      'openshift.io/display-name': |||
        OpenShift enabler and observer for SAP Data intelligence
      |||,
      description: |||
        The template spawns the "sdi-observer" pod that observes the particular
        namespace where SAP Data Intelligence runs and modifies its deployments
        and configuration to enable its pods to run.

        On Red Hat Enterprise Linux CoreOS, SAP Data Intelligence's vsystem-vrep
        statefulset needs to be patched to mount `emptyDir` volume at `/exports`
        directory in order to enable NFS exports in the container running on top
        of overlayfs which is the default filesystem in RHCOS.

        The "sdi-observer" pod modifies vsystem-vrep statefulset as soon as it
        appears to enable the NFS exports.

        The observer also allows to patch pipeline-modeler (aka "vflow") pods to
        mark registry as insecure.

        Additionally, it patches diagnostics-fluentd daemonset to allow its pods
        to access log files on the host system. It also modifies it to parse
        plain text log files instead of preconfigured json.

        On Red Hat Enterprise Linux CoreOS, "vsystem-iptables" containers need to
        be run as privileged in order to load iptables-related kernel modules.
        SAP Data Hub containers named "vsystem-iptables" deployed as part of
        every "vsystem-app" deployment attempt to modify iptables rules without
        having the necessary permissions. The ideal solution is to pre-load these
        modules during node's startup. When not feasable, this template can also
        fix the permissions on-the-fly as the deployments are created.

        The template must be instantiated before the installation of SAP Data
        Hub. Also the namespace, where SAP Data Hub will be installed, must exist
        before the instantiation.

        TODO: document admin project role requirement.

        Usage:
          If running in the same namespace as Data Intelligence, instantiate the
          template as is in the desired namespace:

            oc project $SDI_NAMESPACE
            oc process -n $SDI_NAMESPACE sdi-observer NAMESPACE=$SDI_NAMESPACE | \
              oc create -f -

          If running in a different/new namespace/project, instantiate the
          template with parameters SDI_NAMESPACE and NAMESPACE, e.g.:

            oc new-project $SDI_NAMESPACE
            oc new-project sapdatahub-admin
            oc process sdi-observer \
                SDI_NAMESPACE=$SDI_NAMESPACE \
                NAMESPACE=sapdatahub-admin | oc create -f -
      |||,
    },
  },
  message: |||
    The vsystem-app observer and patcher will be started. You can watch the progress with the
    following command: oc logs -f dc/sdi-observer
  |||,

  objects+: [
    bc.bc,

    {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'Role',
      metadata: {
        labels: {
          deploymentconfig: obstmpl.resourceName,
        },
        name: obstmpl.resourceName,
        namespace: '${SDI_NAMESPACE}',
      },
      rules: [
        {
          apiGroups: [
            'apps',
            'extensions',
          ],
          resources: [
            'deployments',
            'deployments/scale',
            'statefulsets',
            'statefulsets/scale',
          ],
          verbs: [
            'get',
            'list',
            'patch',
            'watch',
          ],
        },
        {
          apiGroups: [
            'apps',
            'extensions',
          ],
          resources: [
            'daemonsets',
          ],
          verbs: [
            'get',
            'list',
            'patch',
            'update',
            'watch',
          ],
        },
        {
          apiGroups: [
            '',
          ],
          resources: [
            'secrets',
          ],
          verbs: [
            'get',
          ],
        },
        {
          apiGroups: [
            '',
          ],
          resources: [
            'configmaps',
          ],
          verbs: [
            'get',
            'list',
            'watch',
            'patch',
          ],
        },
        {
          apiGroups: [
            '',
          ],
          resources: [
            'namespaces',
            'namespaces/status',
          ],
          verbs: [
            'get',
            'list',
            'watch',
          ],
        },
        {
          apiGroups: [
            '',
            'project.openshift.io',
          ],
          resources: [
            'projects',
          ],
          verbs: [
            'get',
          ],
        },
        {
          apiGroups: [
            'apps',
            'deploymentconfigs.apps.openshift.io',
          ],
          resources: [
            'deploymentconfigs',
          ],
          verbs: [
            'get',
            'list',
            'delete',
          ],
        },
        {
          apiGroups: [
            '',
            'authorization.openshift.io',
            'rbac.authorization.k8s.io',
          ],
          resources: [
            'roles',
            'rolebindings',
            'serviceaccounts',
          ],
          verbs: [
            'get',
            'list',
            'delete',
          ],
        },
      ],
    },

    {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'RoleBinding',
      metadata: {
        labels: {
          deploymentconfig: obstmpl.resourceName,
        },
        name: obstmpl.resourceName + '-${ROLE_BINDING_SUFFIX}',
        namespace: '${SDI_NAMESPACE}',
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'Role',
        name: obstmpl.resourceName,
        namespace: '${SDI_NAMESPACE}',
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: obstmpl.resourceName,
          namespace: '${NAMESPACE}',
        },
      ],
    },

    {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'ClusterRoleBinding',
      metadata: {
        labels: {
          deploymentconfig: obstmpl.resourceName,
        },
        name: obstmpl.resourceName + '-node-reader-${ROLE_BINDING_SUFFIX}',
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'ClusterRole',
        name: 'system:node-reader',
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: obstmpl.resourceName,
          namespace: '${NAMESPACE}',
        },
      ],
    },

    {
      apiVersion: 'v1',
      kind: 'ImageStream',
      metadata: {
        name: obstmpl.resourceName,
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
        name: obstmpl.resourceName,
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
          deploymentconfig: obstmpl.resourceName,
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
        name: obstmpl.resourceName,
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
          name: obstmpl.resourceName,
        },
      },
    },
  ],

  parameters+: bc.newParameters + [
    {
      description: |||
        Minor release of OpenShift Container Platform (e.g. 4.2). This value must match the OCP
        server version. The biggest tolerated difference between the versions is 1 in the second
        digit.
      |||,
      name: 'OCP_MINOR_RELEASE',
      required: true,
      value: '4.2',
    },
    {
      description: |||
        The name of the SAP Data Hub namespace to manage. Defaults to the current one. It must be
        set only in case the observer is running in a differnt namespace (see NAMESPACE).
      |||,
      name: 'SDI_NAMESPACE',
    },
    {
      description: |||
        TODO
      |||,
      name: 'SDI_OBSERVER_REPOSITORY',
      required: true,
      value: 'https://github.com/redhat-sap/sap-data-intelligence',
    },
    {
      description: |||
        Revision (e.g. tag, commit or branch) of git repository where SDI Observer's source
        reside.
      |||,
      name: 'SDI_OBSERVER_GIT_REVISION',
      required: true,
      value: 'master',
    },
    {
      description: |||
        A random suffix for the new RoleBinding's name. No need to edit.
      |||,
      from: '[a-z0-9]{5}',
      generate: 'expression',
      name: 'ROLE_BINDING_SUFFIX',
    },
    {
      description: |||
        Set to true if the given or configured VFLOW_REGISTRY shall be marked as insecure in all
        instances of Pipeline Modeler.
      |||,
      name: 'MARK_REGISTRY_INSECURE',
      required: true,
      value: 'false',
    },
    {
      description: |||
        Patch deployments with vsystem-iptables container to make them privileged in order to load
        kernel modules they need. Unless true, it is assumed that the modules have been pre-loaded
        on the worker nodes. This will make also vsystem-vrep-* pod privileged.
      |||,
      name: 'MAKE_VSYSTEM_IPTABLES_PODS_PRIVILEGED',
      required: true,
      value: 'false',
    },
    {
      description: |||
        Format of the logging files on the nodes. Allowed values are "json" and "text".
        Initially, SDI fluentd pods are configured to parse "json" while OpenShift 4 uses
        "text" format by default. If not given, the default is "text".
      |||,
      name: 'NODE_LOG_FORMAT',
      required: false,
    },
    {
      description: |||
        The registry to mark as insecure. If not given, it will be determined from the
        installer-config secret in the SDI_NAMESPACE. If DEPLOY_SDI_REGISTRY is set to "true",
        this variable will be used as the container image registry's hostname when creating the
        corresponding route.
      |||,
      name: 'REGISTRY',
    },
    {
      description: |||
        Whether to deploy container image registry for the purpose of SAP Data Intelligence.
        Requires project admin role attached to the sdi-observer service account. If enabled,
        REDHAT_REGISTRY_SECRET_NAME must be provided.
      |||,
      name: 'DEPLOY_SDI_REGISTRY',
      required: false,
      value: 'false',
    },
    {
      description: |||
        Whether to deploy letsencrypt controller. Requires project admin role attached to the
        sdi-observer service account.
      |||,
      name: 'DEPLOY_LETSENCRYPT',
      required: false,
      value: 'false',
    },
    {
      description: |||
        Whether to expose routes annotated for letsencrypt controller. Requires project admin role
        attached to the sdi-observer service account. Letsencrypt controller must be deployed
        either via this observer or cluster-wide for this to have an effect. Defaults to
        DEPLOY_LETSENCRYPT.
      |||,
      name: 'EXPOSE_WITH_LETSENCRYPT',
    },
    {
      description: |||
        Unless given, a local copy will be used.
      |||,
      name: 'LETSENCRYPT_REPOSITORY',
      required: false,
      value: 'https://github.com/tnozicka/openshift-acme',
    },
    {
      description: |||
        Revision of letsencrypt repository to check out.
      |||,
      name: 'LETSENCRYPT_REVISION',
      required: false,
      value: '2cfefc7388102408a334ada90933531c7e5e11c2',
    },
    {
      description: |||
        Either "live" or "staging". Use the latter when debugging SDI Observer's deployment.
      |||,
      name: 'LETSENCRYPT_ENVIRONMENT',
      required: true,
      value: 'live',
    },
    {
      description: |||
        Whether to forcefully replace existing registry and/or letsencrypt deployments and
        configuration files.
      |||,
      name: 'FORCE_REDEPLOY',
      required: false,
      value: 'false',
    },
    {
      description: |||
        Whether to replace secrets like SDI Registry's htpasswd file if they exist already.
      |||,
      name: 'RECREATE_SECRETS',
      required: false,
      value: 'false',
    },
    {
      description: |||
        Volume space available for container images (e.g. 75Gi).
      |||,
      name: 'SDI_REGISTRY_VOLUME_CAPACITY',
      required: true,
      value: '75Gi',
    },
    {
      description: |||
        Unless given, the default storage class will be used.
      |||,
      name: 'SDI_REGISTRY_STORAGE_CLASS_NAME',
      required: false,
    },
    {
      description: |||
        A secret with htpasswd file with authentication data for the sdi image container If given
        and the secret exists, it will be used instead of SDI_REGISTRY_USERNAME and
        SDI_REGISTRY_PASSWORD.
      |||,
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
    {
      description: |||
        Namespace where the secret with credentials for registry.redhat.io registry resides.
      |||,
      name: 'REDHAT_REGISTRY_SECRET_NAMESPACE',
      require: false,
    },
  ],
}
