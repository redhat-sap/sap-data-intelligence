package adjuster

import "time"

const (
	// Component names
	DiagnosticFluentdName = "diagnostics-fluentd"
	VSystemVrepStsName    = "vsystem-vrep"

	// Volume and mount names
	VolumeName              = "exports-mask"
	FluentdDockerVolumeName = "varlibdockercontainers"

	// Annotation keys
	AnnotationKey = "openshift.io/node-selector"

	// Namespace names
	DataHubSystemNamespace = "datahub-system"

	// API Group and version constants
	DataHubAPIGroup   = "installers.datahub.sap.com"
	DataHubAPIVersion = "v1alpha1"
	DataHubKind       = "DataHub"
	VoraClusterKind   = "VoraCluster"

	// Default values
	DefaultRequeueInterval    = 1 * time.Minute
	DefaultGracePeriodSeconds = int64(1)

	// Security context constants
	DefaultPrivileged = true

	// Label keys
	ControllerRevisionHashLabel = "controller-revision-hash"
)

// Service account names by SDI version
var (
	SDIServiceAccounts = map[string][]string{
		"3.2": {
			"diagnostics-fluentd",
			"elasticsearch",
			"mlf-deployment-api",
			"pipeline-modeler",
			"storagegateway",
			"vsystem",
		},
		"3.3": {
			"diagnostics-fluentd",
			"elasticsearch",
			"mlf-deployment-api",
			"pipeline-modeler",
			"storagegateway",
			"vsystem",
			"backup-agent",
		},
	}
)
