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

package controllers

import (
	"context"
	"fmt"
	"github.com/redhat-sap/sap-data-intelligence/observer-operator/pkg/adjuster"
	"github.com/redhat-sap/sap-data-intelligence/observer-operator/pkg/sdiobserver"
	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	utilerrors "k8s.io/apimachinery/pkg/util/errors"
	"time"

	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	sdiv1alpha1 "github.com/redhat-sap/sap-data-intelligence/observer-operator/api/v1alpha1"
)

// SDIObserverReconciler reconciles a SDIObserver object
type SDIObserverReconciler struct {
	client.Client
	Scheme            *runtime.Scheme
	ObserverNamespace string
	Interval          time.Duration
}

//+kubebuilder:rbac:groups=sdi.sap-redhat.io,resources=sdiobservers,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups=sdi.sap-redhat.io,resources=sdiobservers/status,verbs=get;update;patch
//+kubebuilder:rbac:groups=sdi.sap-redhat.io,resources=sdiobservers/finalizers,verbs=update
//+kubebuilder:rbac:groups=route.openshift.io,resources=routes,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups=route.openshift.io,resources=routes/custom-host,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups=route.openshift.io,resources=routes/status,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups=core,resources=services,verbs=get;list;watch
//+kubebuilder:rbac:groups=core,resources=secrets,verbs=get;list;watch
// +kubebuilder:rbac:groups=core,resources=pods,verbs=get;list;watch;delete
//+kubebuilder:rbac:groups=apps,resources=daemonsets,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups=,resources=serviceaccounts,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups=rbac.authorization.k8s.io,resources=roles;rolebindings,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups=image.openshift.io,resources=imagestreams,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups=machineconfiguration.openshift.io,resources=kubeletconfigs;machineconfigs;machineconfigpools;containerruntimeconfigs,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups=config.openshift.io,resources=clusteroperators,verbs=get;list
//+kubebuilder:rbac:groups=installers.datahub.sap.com,resources=datahubs;voraclusters,verbs=get;list;watch;update;patch

// Reconcile is part of the main kubernetes reconciliation loop which aims to
// move the current state of the cluster closer to the desired state.
// TODO(user): Modify the Reconcile function to compare the state specified by
// the SDIObserver object against the actual cluster state, and then
// perform operations to make the cluster state reflect the state specified by
// the user.
//
// For more details, check Reconcile and its Result here:
// - https://pkg.go.dev/sigs.k8s.io/controller-runtime@v0.13.0/pkg/reconcile
func (r *SDIObserverReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("sdiobserver", req.NamespacedName)

	operatorCR := &sdiv1alpha1.SDIObserver{}

	err := r.Get(ctx, req.NamespacedName, operatorCR)

	if err != nil && errors.IsNotFound(err) {
		logger.Info("Operator resource object not found.")
		return ctrl.Result{}, nil
	} else if err != nil {
		logger.Error(err, "Error getting operator resource object")
		meta.SetStatusCondition(&operatorCR.Status.Conditions, metav1.Condition{
			Type:               "OperatorDegraded",
			Status:             metav1.ConditionTrue,
			Reason:             sdiv1alpha1.ReasonCRNotAvailable,
			LastTransitionTime: metav1.NewTime(time.Now()),
			Message:            fmt.Sprintf("unable to get operator custom resource: %s", err.Error()),
		})
		return ctrl.Result{}, utilerrors.NewAggregate([]error{err, r.Status().Update(ctx, operatorCR)})
	}

	sdiObserver := sdiobserver.New(operatorCR)

	sdiAdjuster := adjuster.New(
		operatorCR.Name,
		operatorCR.Namespace,
		r.Client,
		r.Scheme,
		logger,
	)

	err = sdiAdjuster.Adjust(sdiObserver, ctx)
	if err != nil {
		if client.IgnoreNotFound(err) != nil {
			logger.Error(err, "Couldn't reconcile SDI observer")
			return ctrl.Result{}, err
		}
	}

	logger.Info(fmt.Sprintf("Reconciled Successfully. Requeueing at %s", time.Now().Add(r.Interval).Format(time.Stamp)))
	return ctrl.Result{RequeueAfter: r.Interval}, nil
}

// SetupWithManager sets up the controller with the Manager.
func (r *SDIObserverReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&sdiv1alpha1.SDIObserver{}).
		Complete(r)
}

func getBoolPtr(b bool) *bool {
	return &b
}
