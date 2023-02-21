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
	routev1 "github.com/openshift/api/route/v1"
	"github.com/redhat-sap/sap-data-intelligence/observer-operator/pkg/adjuster"
	"github.com/redhat-sap/sap-data-intelligence/observer-operator/pkg/sdiobserver"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/apiutil"
	"sigs.k8s.io/controller-runtime/pkg/log"

	sdiv1alpha1 "github.com/redhat-sap/sap-data-intelligence/observer-operator/api/v1alpha1"
)

// SDIObserverReconciler reconciles a SDIObserver object
type SDIObserverReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

//+kubebuilder:rbac:groups=sdi.sap-redhat.io,resources=sdiobservers,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups=sdi.sap-redhat.io,resources=sdiobservers/status,verbs=get;update;patch
//+kubebuilder:rbac:groups=sdi.sap-redhat.io,resources=sdiobservers/finalizers,verbs=update

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
	log := log.FromContext(ctx).WithValues("sdiobserver", req.NamespacedName)
	// TODO(user): your logic here

	obs := &sdiv1alpha1.SDIObserver{}
	if err := r.Get(ctx, req.NamespacedName, obs); err != nil {
		log.Error(err, "Unable to fetch SDIObserver", "name", req.NamespacedName)
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	obsGVK, err := apiutil.GVKForObject(obs, r.Scheme)
	if err != nil {
		return ctrl.Result{}, fmt.Errorf("unable to get GVK:  '%s'", req.NamespacedName)
	}

	sdiObserver := sdiobserver.New(obs)

	sdiAdjuster := adjuster.New(
		obs.GetName(),
		obs.GetNamespace(),
		r.Client,
		r.Scheme,
		metav1.OwnerReference{
			APIVersion:         obsGVK.GroupVersion().String(),
			Kind:               obsGVK.Kind,
			Name:               obs.GetName(),
			UID:                obs.GetUID(),
			BlockOwnerDeletion: getBoolPtr(false),
			Controller:         getBoolPtr(true),
		},
		log,
	)

	err = sdiAdjuster.Adjust(ctx, sdiObserver)
	if err != nil {
		if client.IgnoreNotFound(err) != nil {
			log.Error(err, "Couldn't reconcile SDI observer")
			return ctrl.Result{}, err
		}
	}

	return ctrl.Result{}, nil
}

// SetupWithManager sets up the controller with the Manager.
func (r *SDIObserverReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&sdiv1alpha1.SDIObserver{}).
		Owns(&routev1.Route{}).
		Complete(r)
}

func getBoolPtr(b bool) *bool {
	return &b
}
