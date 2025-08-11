/*
Copyright 2023.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package main

import (
	"flag"
	"fmt"
	"os"
	"time"

	operatorv1 "github.com/openshift/api/config/v1"
	openshiftv1 "github.com/openshift/api/image/v1"
	routev1 "github.com/openshift/api/route/v1"

	// Import all Kubernetes client auth plugins (e.g. Azure, GCP, OIDC, etc.)
	// to ensure that exec-entrypoint and run can make use of them.
	_ "k8s.io/client-go/plugin/pkg/client/auth"

	"k8s.io/apimachinery/pkg/runtime"
	utilruntime "k8s.io/apimachinery/pkg/util/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/healthz"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"
	metricsserver "sigs.k8s.io/controller-runtime/pkg/metrics/server"
	"sigs.k8s.io/controller-runtime/pkg/webhook"

	sdiv1alpha1 "github.com/redhat-sap/sap-data-intelligence/observer-operator/api/v1alpha1"
	"github.com/redhat-sap/sap-data-intelligence/observer-operator/controllers"

	configv1 "github.com/openshift/machine-config-operator/pkg/apis/machineconfiguration.openshift.io/v1"
	//+kubebuilder:scaffold:imports
)

var (
	scheme   = runtime.NewScheme()
	setupLog = ctrl.Log.WithName("setup")
)

const (
	namespaceEnvVar = "OPERATOR_NAMESPACE"
)

func init() {
	utilruntime.Must(clientgoscheme.AddToScheme(scheme))
	utilruntime.Must(routev1.AddToScheme(scheme))
	utilruntime.Must(sdiv1alpha1.AddToScheme(scheme))
	utilruntime.Must(operatorv1.AddToScheme(scheme))
	utilruntime.Must(configv1.AddToScheme(scheme))
	utilruntime.Must(openshiftv1.AddToScheme(scheme))
	//+kubebuilder:scaffold:scheme
}

func main() {

	cfg := parseFlags()
	setupLogger()

	if cfg.Namespace == "" {
		setupLog.Error(fmt.Errorf("missing namespace argument, please set at least the NAMESPACE variable"), "fatal")
		os.Exit(1)
	}

	mgr, err := createManager(cfg)
	if err != nil {
		setupLog.Error(err, "unable to start manager")
		os.Exit(1)
	}

	if err := setupController(mgr, cfg); err != nil {
		setupLog.Error(err, "unable to create controller", "controller", "SDIObserver")
		os.Exit(1)
	}

	if err := addHealthChecks(mgr); err != nil {
		setupLog.Error(err, "unable to set up health checks")
		os.Exit(1)
	}

	setupLog.Info("starting manager")
	if err := mgr.Start(ctrl.SetupSignalHandler()); err != nil {
		setupLog.Error(err, "problem running manager")
		os.Exit(1)
	}
}

type config struct {
	MetricsAddr          string
	ProbeAddr            string
	EnableLeaderElection bool
	Namespace            string
	RequeueInterval      time.Duration
}

func parseFlags() config {
	var cfg config

	flag.StringVar(&cfg.MetricsAddr, "metrics-bind-address", ":8080", "The address the metric endpoint binds to.")
	flag.StringVar(&cfg.ProbeAddr, "health-probe-bind-address", ":8081", "The address the probe endpoint binds to.")
	flag.BoolVar(&cfg.EnableLeaderElection, "leader-elect", false,
		"Enable leader election for controller manager. "+
			"Enabling this will ensure there is only one active controller manager.")
	flag.StringVar(&cfg.Namespace, "namespace", os.Getenv(namespaceEnvVar),
		"The k8s namespace where the operator runs. "+mkOverride(namespaceEnvVar))
	flag.DurationVar(&cfg.RequeueInterval, "requeue-interval", 1*time.Minute, "The duration until the next untriggered reconciliation run")

	opts := zap.Options{Development: true}
	opts.BindFlags(flag.CommandLine)
	flag.Parse()

	return cfg
}

func createManager(cfg config) (ctrl.Manager, error) {
	return ctrl.NewManager(ctrl.GetConfigOrDie(), ctrl.Options{
		Scheme: scheme,
		Metrics: metricsserver.Options{
			BindAddress: cfg.MetricsAddr,
		},
		WebhookServer: webhook.NewServer(webhook.Options{
			Port: 9443,
		}),
		HealthProbeBindAddress: cfg.ProbeAddr,
		LeaderElection:         cfg.EnableLeaderElection,
		LeaderElectionID:       "8a63268f.sap-redhat.io",
	})
}

func setupLogger() {
	opts := zap.Options{Development: true}
	ctrl.SetLogger(zap.New(zap.UseFlagOptions(&opts)))
}

func setupController(mgr ctrl.Manager, cfg config) error {
	return (&controllers.SDIObserverReconciler{
		Client:            mgr.GetClient(),
		Scheme:            mgr.GetScheme(),
		ObserverNamespace: cfg.Namespace,
		Interval:          cfg.RequeueInterval,
	}).SetupWithManager(mgr)
}

func addHealthChecks(mgr ctrl.Manager) error {
	if err := mgr.AddHealthzCheck("healthz", healthz.Ping); err != nil {
		return err
	}
	if err := mgr.AddReadyzCheck("readyz", healthz.Ping); err != nil {
		return err
	}
	return nil
}

func mkOverride(varName string) string {
	return fmt.Sprintf("Overrides %s environment variable.", varName)
}
