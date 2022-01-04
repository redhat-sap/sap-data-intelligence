/*
Copyright 2022.

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

	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"

	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller"
	"sigs.k8s.io/controller-runtime/pkg/log"

	sdiv1alpha1 "github.com/redhat-sap/sap-data-intelligence/operator/api/v1alpha1"
	manageddh "github.com/redhat-sap/sap-data-intelligence/operator/controllers/managed-dh"
)

// SdiObserverReconciler reconciles a SdiObserver object
type SdiObserverReconciler struct {
	client.Client
	Scheme *runtime.Scheme
	Mgr    ctrl.Manager
	//Namespace    string
	//SdiNamespace string
	// maps SdiObserver's namespaced name to the namespaces where its DataHub managed instances exist
	SdhForObs map[types.NamespacedName][]string
	// maps SAP DI namespace to the SdiObserver instance
	ObsForSdh map[string]types.NamespacedName
	// each DI namespace is managed by a single SdiObserver CR
	// one SdiObserver instance can manage multiple DI namespaces
	// controllers are created and destroyed dynamicly as DI instances appear or disappear
	DhControllers map[types.NamespacedName]manageddh.DhController
}

func NewSdiObserverReconciler(
	client client.Client,
	scheme *runtime.Scheme,
	mgr ctrl.Manager,
) *SdiObserverReconciler {
	return &SdiObserverReconciler{
		Client:        client,
		Scheme:        scheme,
		Mgr:           mgr,
		SdhForObs:     make(map[types.NamespacedName][]string),
		ObsForSdh:     make(map[string]types.NamespacedName),
		DhControllers: make(map[types.NamespacedName]manageddh.DhController),
	}
}

//+kubebuilder:rbac:groups=di.sap-cop.redhat.com,resources=sdiobservers,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups=di.sap-cop.redhat.com,resources=sdiobservers/status,verbs=get;update;patch
//+kubebuilder:rbac:groups=di.sap-cop.redhat.com,resources=sdiobservers/finalizers,verbs=update

// Reconcile is part of the main kubernetes reconciliation loop which aims to
// move the current state of the cluster closer to the desired state.
// TODO(user): Modify the Reconcile function to compare the state specified by
// the SdiObserver object against the actual cluster state, and then
// perform operations to make the cluster state reflect the state specified by
// the user.
//
// For more details, check Reconcile and its Result here:
// - https://pkg.go.dev/sigs.k8s.io/controller-runtime@v0.9.2/pkg/reconcile
func (r *SdiObserverReconciler) Reconcile(ctx context.Context, req ctrl.Request) (rs ctrl.Result, err error) {
	logger := log.FromContext(ctx)

	logger.Info("(*SdiObserverReconciler) Reconcile: got request")

	knownManagedNamespaces := r.SdhForObs[req.NamespacedName]

	obs := &sdiv1alpha1.SdiObserver{}
	if err := r.Get(ctx, req.NamespacedName, obs); err != nil {
		if errors.IsNotFound(err) {
			if r.unmanageDhs(ctx, knownManagedNamespaces...) {
				// another existing obs instance could take ownership of the (now) orphaned DH instance
				return ctrl.Result{}, nil
			}
		}
		return rs, err
	}

	if dhCtrl, ok := r.DhControllers[req.NamespacedName]; ok {
		dhCtrl.ReconcileObs(obs)
	}

	dhc, err := manageddh.NewDhClient()
	if err != nil {
		return rs, err
	}
	// can potentially return multiple instances across multiple namespaces
	dhs, err := dhc.List(ctx, obs.Spec.SdiNamespace)
	if err != nil {
		return rs, err
	}

	for _, dh := range dhs {
		if obsNmName, ok := r.ObsForSdh[dh.GetNamespace()]; !ok {
			if err := r.manageDhs(ctx, req.NamespacedName, dh); err != nil {
				return rs, err
			}
		} else {
			logger.Info(fmt.Sprintf("(*SdiObserverReconciler) Reconcile: DI namespace %s is already managed by SdiObserver %s/%s", dh.GetNamespace(), obsNmName.Namespace, obsNmName.Name))
		}
	}

	logger.Info("(*SdiObserverReconciler) Reconcile: finished")
	return rs, nil
}

func (r *SdiObserverReconciler) unmanageDhs(ctx context.Context, dhNamespaces ...string) (changed bool) {
	// TODO: first check for other Obs instances in case they can take over
	for _, nm := range dhNamespaces {
		obsNmName, ok := r.ObsForSdh[nm]
		if !ok {
			continue
		}
		dhCtrl, ok := r.DhControllers[obsNmName]
		if !ok {
			continue
		}
		dhCtrl.Stop()
		delete(r.DhControllers, obsNmName)
		obs := r.ObsForSdh[nm]
		delete(r.ObsForSdh, nm)

		newDhNamespaces := make([]string, len(r.SdhForObs[obs])-1)
		for _, nm_ := range r.SdhForObs[obs] {
			if nm_ != nm {
				newDhNamespaces = append(newDhNamespaces, nm_)
			}
		}
		r.SdhForObs[obs] = newDhNamespaces
		changed = true

		if len(r.DhControllers) > 0 {
			r.findNewControllerForDh(ctx, nm)
		}
	}
	return
}

func (r *SdiObserverReconciler) destroyController(obsNmName types.NamespacedName) {
	dhctrl, ok := r.DhControllers[obsNmName]
	if !ok {
		return
	}
	dhctrl.Stop()
	delete(r.DhControllers, obsNmName)
	for _, nm := range r.SdhForObs[obsNmName] {
		delete(r.ObsForSdh, nm)
	}
	delete(r.SdhForObs, obsNmName)
}

func (r *SdiObserverReconciler) findNewControllerForDh(
	ctx context.Context,
	dhNamespace string,
) (*sdiv1alpha1.SdiObserver, error) {
	var clusterWideCandidate *sdiv1alpha1.SdiObserver
	var obss sdiv1alpha1.SdiObserverList
	err := r.List(ctx, &obss)
	if err != nil {
		return nil, err
	}
	for i := range obss.Items {
		obs := &obss.Items[i]
		if _, ok := r.SdhForObs[client.ObjectKeyFromObject(obs)]; !ok {
			// not yet managed SdiObserver instance, rely on the next reconcile execution
			continue
		}
		if dhNamespace == obs.Spec.SdiNamespace {
			// prefer an instance managing a specific DI namespace
			return obs, nil
		}
		if clusterWideCandidate == nil && len(obs.Spec.SdiNamespace) == 0 {
			clusterWideCandidate = obs
		}
	}
	return clusterWideCandidate, nil
}

/*
func (r *SdiObserverReconciler) tryManageDh(
	ctx context.Context,
	dhNamespace string,
) (obsNmName *types.NamespacedName, err error) {
	obs, err := r.findNewControllerForDh(ctx, dhNamespace)
	if err != nil || obs == nil {
		return
	}
	tmp := client.ObjectKeyFromObject(obs)
	obsNmName = &tmp

	dhc, err := NewDhClient()
	if err != nil {
		return nil, err
	}
	// can potentially return multiple instances across multiple namespaces since dhNamespace can be empty
	dhs, err := dhc.List(ctx, obs.Spec.SdiNamespace)
	if err != nil {
		return nil, err
	}

	ctrl := r.DhControllers[obs.Namespace]

	for _, dh := range dhs {
		if _, ok := r.ObsForSdh[
		err := ctrl.ManageDhNamespace(dh.GetNamespace())
		if err != nil {
			return err
		}
	}

	// we need to recreate caches to monitor the additional namespace
	// TODO: see if we can do without destorying the controller completely
	// TODO: now it is clear the controller can be modified to support watching a new namespace at runtime
	r.destroyController(*obsNmName)
	for _, dh := range dhs {
		r.manageDhs(ctx, *obsNmName, dh)
	}
	return obsNmName, nil
}
*/

func (r *SdiObserverReconciler) manageDhs(
	ctx context.Context,
	obsNmName types.NamespacedName,
	dh unstructured.Unstructured,
) error {
	logger := log.FromContext(ctx)
	if _, ok := r.ObsForSdh[dh.GetNamespace()]; ok {
		// already managed
		return nil
	}
	dhNmName := types.NamespacedName{Namespace: dh.GetNamespace(), Name: dh.GetName()}
	logger.Info(fmt.Sprintf("(*SdiObserverReconciler).manageDhs: creating the controller for DataHub intance %s/%s", dhNmName.Namespace, dhNmName.Name))

	ctrl, err := manageddh.NewManagedDhController(
		r.Client,
		r.Scheme,
		obsNmName,
		dh.GetNamespace(),
		r.Mgr,
		controller.Options{})
	if err != nil {
		return err
	}
	r.ObsForSdh[dh.GetNamespace()] = obsNmName
	r.SdhForObs[obsNmName] = append(r.SdhForObs[obsNmName], dh.GetNamespace())
	r.DhControllers[obsNmName] = ctrl
	logger.Info(fmt.Sprintf("(*SdiObserverReconciler).manageDhs: starting the management of DataHub instance %s/%s", dhNmName.Namespace, dhNmName.Name))
	err = ctrl.Start(ctx)
	if err != nil {
		logger.Error(err, fmt.Sprintf("(*SdiObserverReconciler).manageDhs: controller of DataHub instance %s/%s terminated", dhNmName.Namespace, dhNmName.Name))
		return err
	}
	logger.Info("(*SdiObserverReconciler).manageDhs: started")
	return nil
}

func (r *SdiObserverReconciler) SetupWithManager(mgr ctrl.Manager) error {
	var obs = &sdiv1alpha1.SdiObserver{}
	return ctrl.NewControllerManagedBy(mgr).For(obs).Complete(r)
}
