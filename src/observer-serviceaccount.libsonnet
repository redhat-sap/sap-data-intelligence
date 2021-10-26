{
  resourceName:: 'sdi-observer',
  createdBy:: error 'createdBy must be overridden by a child!',

  Objects: [$.ObserverServiceAccount] + $.ObserverRBAC,
  ObjectsForSDI: $.Objects + $.ObserverRBACForSDI,

  rbac:: {
    role: {
      local role = self,

      get:: {
        apiGroups: [],
        resources: [],
        verbs: [
          'get',
        ],
      },

      watch:: role.get {
        verbs+: ['list', 'watch'],
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
      GetProjects: role.get {
        apiGroups: [
          '',
          'project.openshift.io',
        ],
        resources: ['projects'],
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
      PatchDaemonSets: $.rbac.role.patch {
        apiGroups: ['apps', 'extensions'],
        resources: ['daemonsets'],
      },
      PatchJobs: role.patch {
        apiGroups: ['batch/v1'],
        resources: ['jobs'],
      },
      PatchConfigmaps: role.patch {
        apiGroups: [''],
        resources: ['configmaps'],
      },
      ManageServices: $.rbac.role.manage {
        apiGroups: [''],
        resources: ['service'],
      },
      ManageRoles: $.rbac.role.manage {
        apiGroups: ['rbac.authorization.k8s.io'],
        resources: ['role'],
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
        app: $.resourceName,
        deploymentconfig: $.resourceName,
        'created-by': $.createdBy,
      },
      name: $.resourceName,
      namespace: '${NAMESPACE}',
    },
  },

  // In order to manipulate the role of vora-vsystem service account, SDI Observer must have the
  // same permissions as the vora-vsystem.
  voraVSystem31RBACRules: [
    {
      apiGroups: [''],
      resources: ['events'],
      verbs: ['create', 'delete', 'update', 'patch', 'deletecollection'],
    },
    {
      apiGroups: [''],
      resources: ['pods/log'],
      verbs: ['create', 'delete', 'update', 'patch', 'deletecollection'],
    },
    {
      apiGroups: ['vsystem.datahub.sap.com'],
      resources: ['appinstances'],
      verbs: ['*'],
    },
    {
      apiGroups: ['vsystem.datahub.sap.com'],
      resources: ['workloads'],
      verbs: ['*'],
    },
    {
      apiGroups: ['vsystem.datahub.sap.com'],
      resources: ['workloads/finalizers'],
      verbs: ['update'],
    },
  ],

  ObserverRBACForSDI: [
    {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'Role',
      metadata: {
        labels: {
          deploymentconfig: $.resourceName,
          'created-by': $.createdBy,
        },
        name: $.resourceName + '-in-${NAMESPACE}',
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
        $.rbac.role.PatchDaemonSets,
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
        $.rbac.role.ManageRoutes,
        $.rbac.role.ManageServices,
        $.rbac.role.get {
          apiGroups: [
            'apiextensions.k8s.io',
          ],
          resourceNames: [
            'datahubs.installers.datahub.sap.com',
          ],
          resources: [
            'customresourcedefinitions',
          ],
        },
        $.rbac.role.patch {
          apiGroups: [
            'installers.datahub.sap.com',
          ],
          resources: [
            'datahubs',
          ],
        },
        $.rbac.role.watch {
          apiGroups: [
            'sap.com',
          ],
          resources: [
            'voraclusters',
          ],
        },
      ] + $.voraVSystem31RBACRules,
    },

    {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'RoleBinding',
      metadata: {
        labels: {
          deploymentconfig: $.resourceName,
          'created-by': $.createdBy,
        },
        name: $.resourceName + '-in-${NAMESPACE}',
        namespace: '${SDI_NAMESPACE}',
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'Role',
        name: $.resourceName + '-in-${NAMESPACE}',
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
        name: $.resourceName + '-for-slcbridge-in-${NAMESPACE}',
        namespace: '${SLCB_NAMESPACE}',
      },
      rules: [
        $.rbac.role.GetProjects,
        $.rbac.role.ManageRBAC,
        $.rbac.role.CreateNamespaces,
        $.rbac.role.PatchDaemonSets,
        $.rbac.role.ManageRoutes,
        $.rbac.role.ManageServices,
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
        name: $.resourceName + '-for-slcbridge-in-${NAMESPACE}',
        namespace: '${SLCB_NAMESPACE}',
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'Role',
        name: $.resourceName + '-for-slcbridge-in-${NAMESPACE}',
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
          'created-by': $.createdBy,
        },
        name: $.resourceName + '-node-reader-in-${NAMESPACE}',
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
          'created-by': $.createdBy,
        },
        name: $.resourceName + '-admin-in-${NAMESPACE}',
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
        labels: {
          deploymentconfig: $.resourceName,
          'created-by': $.createdBy,
        },
        name: $.resourceName + '-cluster-access-in-${NAMESPACE}',
      },
      rules: [
        $.rbac.role.watch {
          apiGroups: ['config.openshift.io'],
          resources: ['ingresses', 'clusteroperators'],
        },
        $.rbac.role.patch {
          apiGroups: [''],
          resources: ['namespaces'],
        },
      ],
    },

    {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'ClusterRoleBinding',
      metadata: {
        labels: {
          deploymentconfig: $.resourceName,
          'created-by': $.createdBy,
        },
        name: $.resourceName + '-cluster-access-in-${NAMESPACE}',
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'ClusterRole',
        name: $.resourceName + '-cluster-access-in-${NAMESPACE}',
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
