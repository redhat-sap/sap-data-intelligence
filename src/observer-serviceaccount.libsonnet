{
  _resourceName: 'sdi-observer',
  createdBy:: error 'createdBy must be overridden by a child!',

  Objects: [$.ObserverServiceAccount] + $.ObserverRBAC,
  ObjectsForSDI: $.Objects + $.ObserverRBACForSDI,

  ObserverServiceAccount: {
    local sa = self,
    createdBy:: error 'createdBy must be overridden by a child!',

    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: {
      labels: {
        deploymentconfig: $._resourceName,
        'created-by': $.createdBy,
      },
      name: $._resourceName,
      namespace: '${NAMESPACE}',
    },
  },

  ObserverRBACForSDI: [
    {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'Role',
      metadata: {
        labels: {
          deploymentconfig: $._resourceName,
          'created-by': $.createdBy,
        },
        name: $._resourceName,
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
          deploymentconfig: $._resourceName,
          'created-by': $.createdBy,
        },
        name: $._resourceName,
        namespace: '${SDI_NAMESPACE}',
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'Role',
        name: $._resourceName,
        namespace: '${SDI_NAMESPACE}',
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: $._resourceName,
          namespace: '${NAMESPACE}',
        },
      ],
    },

    {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'Role',
      metadata: {
        labels: {
          deploymentconfig: $._resourceName,
          'created-by': $.createdBy,
        },
        name: $._resourceName + '-for-slcbridge',
        namespace: '${SLCB_NAMESPACE}',
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
            'create',
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
          deploymentconfig: $._resourceName,
          'created-by': $.createdBy,
        },
        name: $._resourceName + '-for-slcbridge',
        namespace: '${SLCB_NAMESPACE}',
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'Role',
        name: $._resourceName + '-for-slcbridge',
        namespace: '${SLCB_NAMESPACE}',
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: $._resourceName,
          namespace: '${NAMESPACE}',
        },
      ],
    },

    {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'ClusterRoleBinding',
      metadata: {
        labels: {
          deploymentconfig: $._resourceName,
        },
        name: $._resourceName + '-node-reader',
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'ClusterRole',
        name: 'system:node-reader',
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: $._resourceName,
          namespace: '${NAMESPACE}',
        },
      ],
    },

  ],

  ObserverRBAC: [
    /**
     * TODO: determine the necessary permissions (ideally automatically) and create a custom role
     * instead
     */
    {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'ClusterRoleBinding',
      metadata: {
        labels: {
          deploymentconfig: $._resourceName,
        },
        name: $._resourceName + '-admin',
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'ClusterRole',
        name: 'admin',
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: $._resourceName,
          namespace: '${NAMESPACE}',
        },
      ],
    },
  ],
}
