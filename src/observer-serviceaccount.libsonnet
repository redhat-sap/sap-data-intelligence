{
  resourceName:: 'sdi-observer',
  createdBy:: error 'createdBy must be overridden by a child!',

  Objects: [$.ObserverServiceAccount] + $.ObserverRBAC,
  ObjectsForSDI: $.Objects + $.ObserverRBACForSDI,

  rbac:: {
    role: {
      local role = self,

      watch:: {
        apiGroups: [],
        resources: [],
        verbs: [
          'get',
          'list',
          'watch',
        ],
      },

      patch:: role.watch {
        verbs+: ['patch', 'update', 'delete'],
      },

      manage:: role.patch {
        verbs+: ['create', 'delete'],
      },

      ManageRoutes: role.manage {
        apiGroups: ['route.openshift.io/v1'],
        resources: ['routes'],
      },
      CreateNamespaces: role.watch {
        apiGroups: [''],
        resources: [
          'namespaces',
          'namespaces/status',
        ],
        verbs+: ['create'],
      },
      GetProjects: {
        apiGroups: [
          '',
          'project.openshift.io',
        ],
        resources: ['projects'],
        verbs: ['get'],
      },
      ManageRBAC: role.manage {
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
      },
      WatchSecrets: role.watch {
        apiGroups: [''],
        resources: ['secrets'],
      },
      ManageSecrets: $.rbac.role.WatchSecrets {
        verbs: $.rbac.role.manage.verbs,
      },
      PatchDeployments: role.patch {
        apiGroups: [
          'apps',
          'extensions',
        ],
        resources: [
          'deployments',
          'deployments/scale',
        ],
      },
      PatchJobs: role.patch {
        apiGroups: ['batch/v1'],
        resources: ['jobs'],
      },
      PatchConfigmaps: role.patch {
        apiGroups: [''],
        resources: ['configmaps'],
      },
    },
  },

  ObserverServiceAccount: {
    local sa = self,
    createdBy:: error 'createdBy must be overridden by a child!',

    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: {
      labels: {
        deploymentconfig: $.resourceName,
        'created-by': $.createdBy,
      },
      name: $.resourceName,
      namespace: '${NAMESPACE}',
    },
  },

  ObserverRBACForSDI: [
    {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'Role',
      metadata: {
        labels: {
          deploymentconfig: $.resourceName,
          'created-by': $.createdBy,
        },
        name: $.resourceName,
        namespace: '${SDI_NAMESPACE}',
      },
      rules: [
        $.rbac.role.ManageSecrets,
        $.rbac.role.PatchConfigmaps,
        $.rbac.role.ManageRBAC,
        $.rbac.role.CreateNamespaces,
        $.rbac.role.GetProjects,
        $.rbac.role.PatchDeployments {
          resources+: [
            'statefulsets',
            'statefulsets/scale',
          ],
        },
        $.rbac.role.PatchJobs,
        $.rbac.role.patch {
          apiGroups: [
            'apps',
            'extensions',
          ],
          resources: [
            'daemonsets',
          ],
        },
        $.rbac.role.watch {
          apiGroups: [
            'apps',
            'deploymentconfigs.apps.openshift.io',
          ],
          resources: [
            'deploymentconfigs',
          ],
          verbs+: ['delete'],
        },
      ],
    },

    {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'RoleBinding',
      metadata: {
        labels: {
          deploymentconfig: $.resourceName,
          'created-by': $.createdBy,
        },
        name: $.resourceName,
        namespace: '${SDI_NAMESPACE}',
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'Role',
        name: $.resourceName,
        namespace: '${SDI_NAMESPACE}',
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: $.resourceName,
          namespace: '${NAMESPACE}',
        },
      ],
    },

    {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'Role',
      metadata: {
        labels: {
          deploymentconfig: $.resourceName,
          'created-by': $.createdBy,
        },
        name: $.resourceName + '-for-slcbridge',
        namespace: '${SLCB_NAMESPACE}',
      },
      rules: [
        $.rbac.role.GetProjects,
        $.rbac.role.PatchConfigmaps,
        $.rbac.role.ManageRBAC,
        $.rbac.role.ManageRoutes,
        $.rbac.role.CreateNamespaces,
        $.rbac.role.manage {
          apiGroups: [''],
          resources: ['service'],
        },
      ],
    },

    {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'RoleBinding',
      metadata: {
        labels: {
          deploymentconfig: $.resourceName,
          'created-by': $.createdBy,
        },
        name: $.resourceName + '-for-slcbridge',
        namespace: '${SLCB_NAMESPACE}',
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'Role',
        name: $.resourceName + '-for-slcbridge',
        namespace: '${SLCB_NAMESPACE}',
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: $.resourceName,
          namespace: '${NAMESPACE}',
        },
      ],
    },

    {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'ClusterRoleBinding',
      metadata: {
        labels: {
          deploymentconfig: $.resourceName,
        },
        name: $.resourceName + '-node-reader',
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'ClusterRole',
        name: 'system:node-reader',
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: $.resourceName,
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
          deploymentconfig: $.resourceName,
        },
        name: $.resourceName + '-admin',
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'ClusterRole',
        name: 'admin',
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: $.resourceName,
          namespace: '${NAMESPACE}',
        },
      ],
    },

    {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'ClusterRole',
      metadata: {
        name: $.resourceName + '-cluster-access',
      },
      rules: [
        $.rbac.role.watch {
          apiGroups: ['config.openshift.io'],
          resources: ['ingresses'],
        },
      ],
    },

    {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'ClusterRoleBinding',
      metadata: {
        labels: {
          deploymentconfig: $.resourceName,
        },
        name: $.resourceName + '-cluster-access',
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'ClusterRole',
        name: $.resourceName + '-cluster-access',
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: $.resourceName,
          namespace: '${NAMESPACE}',
        },
      ],
    },
  ],
}
