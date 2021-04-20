local is = import 'imagestream.libsonnet';
local list = import 'list.libsonnet';

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
        labels: {
          daemonset: ndcfgr.resourceName,
          app: ndcfgr.resourceName,
          'sdi-observer/version': ndcfgr.version,
        },
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
              command: [
                'chroot',
                '/host',
                '/bin/bash',
                '-c',
                std.join('\n', [
                  std.join(' ', ['for module in'] + ds.modulesToLoad + ['; do']),
                  '  modprobe -v $module',
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
}
