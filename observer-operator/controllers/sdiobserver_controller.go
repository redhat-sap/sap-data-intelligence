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
	if err != nil {
		if errors.IsNotFound(err) {
			logger.Info("Operator resource not found.")
			return ctrl.Result{}, nil
		}
		return r.handleError(ctx, operatorCR, err, "Error getting operator resource")
	}

	updateStatus := r.ensureStatusConditions(operatorCR)
	if updateStatus {
		if err = r.Status().Update(ctx, operatorCR); err != nil {
			return r.handleError(ctx, operatorCR, err, "Failed to update status")
		}
		if err := r.Get(ctx, req.NamespacedName, operatorCR); err != nil {
			return r.handleError(ctx, operatorCR, err, "Failed to re-fetch SDIObserver")
		}
	}

	sdiObserver := sdiobserver.New(operatorCR)
	sdiAdjuster := adjuster.New(
		operatorCR.Name,
		operatorCR.Namespace,
		r.Client,
		r.Scheme,
		logger,
	)

	if err := sdiAdjuster.Adjust(sdiObserver, ctx); err != nil {
		if client.IgnoreNotFound(err) != nil {
			return r.handleError(ctx, operatorCR, err, "Couldn't reconcile SDI observer")
		}
	}

	if err := r.Get(ctx, req.NamespacedName, operatorCR); err != nil {
		return r.handleError(ctx, operatorCR, err, "Failed to re-fetch SDIObserver")
	}

	meta.SetStatusCondition(&operatorCR.Status.Conditions, metav1.Condition{
		Type:               "OperatorDegraded",
		Status:             metav1.ConditionFalse,
		Reason:             sdiv1alpha1.ReasonSucceeded,
		LastTransitionTime: metav1.NewTime(time.Now()),
		Message:            fmt.Sprintf("The reconcilation is done successfuly"),
	})

	if err = r.Status().Update(ctx, operatorCR); err != nil {
		return r.handleError(ctx, operatorCR, err, "Failed to update SDIObserver status")
	}

	logger.Info("Reconciled successfully. Requeueing", "nextRequeue", time.Now().Add(r.Interval).Format(time.Stamp))
	return ctrl.Result{RequeueAfter: r.Interval}, nil
}

// SetupWithManager sets up the controller with the Manager.
func (r *SDIObserverReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&sdiv1alpha1.SDIObserver{}).
		Complete(r)
}

func (r *SDIObserverReconciler) ensureStatusConditions(cr *sdiv1alpha1.SDIObserver) bool {
	updateStatus := false

	if cr.Status.Conditions == nil || len(cr.Status.Conditions) == 0 {
		meta.SetStatusCondition(&cr.Status.Conditions, metav1.Condition{Type: "Available", Status: metav1.ConditionUnknown, Reason: "Reconciling", Message: "Starting reconciliation"})
		updateStatus = true
	}

	return updateStatus
}

func (r *SDIObserverReconciler) handleError(ctx context.Context, cr *sdiv1alpha1.SDIObserver, err error, msg string) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("sdiobserver", cr.Name)
	meta.SetStatusCondition(&cr.Status.Conditions, metav1.Condition{
		Type:               "OperatorDegraded",
		Status:             metav1.ConditionTrue,
		Reason:             sdiv1alpha1.ReasonCRNotAvailable,
		LastTransitionTime: metav1.NewTime(time.Now()),
		Message:            msg,
	})
	if updateErr := r.Status().Update(ctx, cr); updateErr != nil {
		return ctrl.Result{RequeueAfter: 20 * time.Second}, utilerrors.NewAggregate([]error{err, updateErr})
	}
	logger.Error(err, msg)
	return ctrl.Result{RequeueAfter: 20 * time.Second}, err
}

// ConditionHolder is a helper struct to hold conditions
type ConditionHolder struct {
	Conditions []metav1.Condition
}
