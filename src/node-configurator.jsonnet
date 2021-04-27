local params = import 'common-parameters.libsonnet';
local is = import 'imagestream.libsonnet';
local list = import 'list.libsonnet';
local tmplbase = import 'ocp-template.libsonnet';

{
  local ndcfgr = self,
  resourceName:: 'sdi-node-configurator',
  createdBy:: 'manual',
  version:: error 'version must be specified',

  ImageStream: is {
    local is = self,
    resourceName:: 'ocp-tools',
    createdBy:: ndcfgr.createdBy,
    tagName:: 'latest',
    istag:: is.resourceName + ':' + is.tagName,
    metadata+: {
      // this is not a template
      namespace:: null,
      labels+: {
        'sdi-observer/version': ndcfgr.version,
      },
    },

    spec: {
      lookupPolicy: {
        'local': true,
      },
      tags: [
        {
          from: {
            kind: 'ImageStreamTag',
            name: 'tools:latest',
            namespace: 'openshift',
          },
          name: is.tagName,
        },
      ],
    },
  },

  ServiceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: {
      labels: {
        daemonset: 'sdi-node-configurator',
        app: ndcfgr.resourceName,
        'created-by': ndcfgr.createdBy,
      },
      name: ndcfgr.resourceName,
    },
  },

  DaemonSet: {
    local ds = self,
    modulesToLoad:: [
      'nfsd',
      'nfsv4',
      'ip_tables',
      'ipt_REDIRECT',
      'ipt_owner',
      'iptable_nat',
      'iptable_filter',
    ],

    apiVersion: 'apps/v1',
    kind: 'DaemonSet',
    metadata: {
      annotations: {
        'image.openshift.io/triggers': std.toString(
          [
            {
              from: { kind: 'ImageStreamTag', name: $.ImageStream.istag },
              fieldPath: 'spec.template.spec.containers[0].image',
              paused: 'false',
            },
            {
              from: { kind: 'ImageStreamTag', name: $.ImageStream.istag },
              fieldPath: 'spec.template.spec.initContainers[0].image',
              paused: 'false',
            },
          ]
        ),
      },
      labels: {
        daemonset: ndcfgr.resourceName,
        app: ndcfgr.resourceName,
        'sdi-observer/version': ndcfgr.version,
      },
      name: ndcfgr.resourceName,
    },
    spec: {
      revisionHistoryLimit: 7,
      selector: {
        matchLabels: {
          daemonset: ndcfgr.resourceName,
          app: ndcfgr.resourceName,
        },
      },
      template: {
        metadata: {
          labels: {
            daemonset: ndcfgr.resourceName,
            app: ndcfgr.resourceName,
          },
        },
        spec: {
          containers: [
            {
              command: [
                '/bin/sleep',
                'infinity',
              ],
              image: $.ImageStream.istag,
              imagePullPolicy: 'IfNotPresent',
              name: 'keep-alive',
              resources: {
                requests: {
                  cpu: '50m',
                  memory: '50Mi',
                },
                limits: {
                  cpu: '50m',
                  memory: '50Mi',
                },
              },
            },
          ],
          hostIPC: true,
          hostNetwork: true,
          hostPID: true,
          initContainers: [
            {
              env+: [
                {
                  name: 'SDI_OBSERVER_VERSION',
                  value: ndcfgr.version,
                },
                {
                  local param = params.DryRun,
                  name: param.name,
                  value: param.value,
                },
              ],
              command: [
                'chroot',
                '/host',
                '/bin/bash',
                '-c',
                |||
                  args=( --verbose )
                  if [[ "${DRY_RUN:-0}" == 1 ]]; then
                    args+=( --dry-run )
                  fi
                ||| +
                std.join('\n', [
                  std.join(' ', ['for module in'] + ds.modulesToLoad + ['; do']),
                  '  modprobe "${args[@]}" $module',
                  'done',
                ]),
              ],
              image: $.ImageStream.istag,
              imagePullPolicy: 'IfNotPresent',
              name: ndcfgr.resourceName,
              securityContext: {
                privileged: true,
                runAsUser: 0,
              },
              volumeMounts: [
                {
                  mountPath: '/host',
                  name: 'host-root',
                },
              ],
              resources: {
                requests: {
                  cpu: '100m',
                  memory: '100Mi',
                },
                limits: {
                  cpu: '200m',
                  memory: '100Mi',
                },
              },
            },
          ],
          serviceAccountName: ndcfgr.resourceName,
          volumes: [
            {
              hostPath: {
                path: '/',
                type: '',
              },
              name: 'host-root',
            },
          ],
        },
      },
      updateStrategy: {
        rollingUpdate: {
          maxUnavailable: 7,
        },
        type: 'RollingUpdate',
      },
    },
  },

  Objects: [
    $.ServiceAccount,
    $.ImageStream,
    $.DaemonSet,
  ],

  List: list {
    items: $.Objects,
  },

  Template: tmplbase {
    local tmpl = self,
    metadata+: {
      annotations+: {
        'openshift.io/display-name': |||
          OpenShift compute node configurator for SAP Data Intelligence
        |||,
        description: |||
          The template creates a daemonset that spawns pods on all matching nodes. The pods will
          configure the nodes for running SAP Data Intelligence.

          As of now, the configuration consists of loading kernel modules needed needed to use NFS
          and manipulated iptables.

          Before running this template, Security Context Constraints need to be given to the
          %(saName)s service account. This can be achieved from command line with
          system admin role with the following command:

            oc adm policy add-scc-to-user -n $NAMESPACE privileged -z %(saName)s
        ||| % { saName: ndcfgr.resourceName },
      },
    },

    resourceName:: ndcfgr.resourceName,
    version:: ndcfgr.version,
    objects+: [
      local setNamespace = function(o) o {
        metadata+: { namespace::: '${NAMESPACE}' },
      };
      (
        if o.kind == 'DaemonSet' then
          setNamespace(o) {
            spec+: {
              template+: {
                local old = super.spec,
                local parammap = std.foldl(
                  (function(o, p) (o { [p.name]: null })), tmpl.parameters, {}
                ),
                spec+: {
                  initContainers: [
                    (c {
                       local oldEnv = super.env,
                       env: [e for e in oldEnv if !std.objectHas(parammap, e.name)] +
                            [
                              {
                                name: p.name,
                                value: '${' + p.name + '}',
                              }
                              for p in tmpl.parameters
                            ],
                     })
                    for c in old.initContainers
                  ],
                  nodeSelector: '${{SDI_NODE_SELECTOR}}',
                },
              },
            },
          }
        else
          setNamespace(o)
      )
      for o in ndcfgr.Objects
    ],
    parameters+: [
      (params.NodeSelector {
         description: |||
           Select the nodes where the SDI node configurator pods can be scheduled. The selector must
           match all the nodes where SAP Data Intelligence is running.
           Typically, this should correspond to the SDI_NODE_SELECTOR parameter of the SDI Observer
           template and its resulting DeploymentConfig. The difference is that this field accepts
           JSON object instead of a plain string.
           If the daemonset shall run on all nodes, set this to "null".
         |||,
         value: std.toString(params.SDINodeRoleSelector),
         required: true,
       }),
    ],
  },
}
