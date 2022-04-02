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

package sdiobserver

import (
	"context"
	"sort"

	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller"
	"sigs.k8s.io/controller-runtime/pkg/log"

	sdiv1alpha1 "github.com/redhat-sap/sap-data-intelligence/operator/api/v1alpha1"
	"github.com/redhat-sap/sap-data-intelligence/operator/controllers/sdiobserver/namespaced"
	λ "github.com/redhat-sap/sap-data-intelligence/operator/util/log"
	"github.com/redhat-sap/sap-data-intelligence/operator/util/sdiobservers"
)

// Reconciler reconciles all SDIObserver objects in all namespaces.
type Reconciler struct {
	client.Client
	Scheme *runtime.Scheme
	Mgr    ctrl.Manager
	// Maps SDIObserver's namespaced name to the namespaces where its DataHub managed instances exist.
	// There can be multiple SDIObserver names mapping to the same DH namespace because multiple SDIObserver
	// resources can specify the same SDIObserver namespace. However, only one can be actively managing the
	// DH namespace. Such an instance will have the corresponding entry in ObsForSdh. The other instances will
	// have Backup condition "true".
	ManagedDHPerObserver map[types.NamespacedName]string
	// Maps SAP DI namespace to the SDIObserver instance. Only the actively managing SDIObserver instances are
	// reflected here.
	ActiveObserverForDH map[string]types.NamespacedName
	// There is one namespaced Controller running for each ObsObserver instance found. Controllers are created
	// and destroyed dynamicly as SDIObserver instances appear or disappear. No controllers are created for
	// Backup observer instances.
	NamespacedControllers map[types.NamespacedName]*namespaced.Controller
}

func NewReconciler(
	client client.Client,
	scheme *runtime.Scheme,
	mgr ctrl.Manager,
) *Reconciler {
	return &Reconciler{
		Client:                client,
		Scheme:                scheme,
		Mgr:                   mgr,
		ManagedDHPerObserver:  make(map[types.NamespacedName]string),
		ActiveObserverForDH:   make(map[string]types.NamespacedName),
		NamespacedControllers: make(map[types.NamespacedName]*namespaced.Controller),
	}
}

//+kubebuilder:rbac:groups=di.sap-cop.redhat.com,resources=sdiobservers,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups=di.sap-cop.redhat.com,resources=sdiobservers/status,verbs=get;update;patch
//+kubebuilder:rbac:groups=di.sap-cop.redhat.com,resources=sdiobservers/finalizers,verbs=update

// Reconcile is part of the main kubernetes reconciliation loop which aims to
// move the current state of the cluster closer to the desired state.
// TODO(user): Modify the Reconcile function to compare the state specified by
// the SDIObserver object against the actual cluster state, and then
// perform operations to make the cluster state reflect the state specified by
// the user.
//
// For more details, check Reconcile and its Result here:
// - https://pkg.go.dev/sigs.k8s.io/controller-runtime@v0.9.2/pkg/reconcile
func (r *Reconciler) Reconcile(ctx context.Context, req ctrl.Request) (rs ctrl.Result, err error) {
	tracer := λ.Enter(log.FromContext(ctx))
	defer λ.Leave(tracer)

	knownManagedNamespace := r.ManagedDHPerObserver[req.NamespacedName]
	_, isActive := r.NamespacedControllers[req.NamespacedName]

	obs := &sdiv1alpha1.SDIObserver{}
	if err = r.Get(ctx, req.NamespacedName, obs); err != nil {
		// TODO: do the same for terminating instances
		if errors.IsNotFound(err) && isActive {
			// TODO: handle finalizers
			_, err = r.orphanDH(ctx, knownManagedNamespace)
			if err != nil {
				return
			}
			var candidate *sdiv1alpha1.SDIObserver
			candidate, err = r.findNewObsForDH(ctx, knownManagedNamespace, true)
			if err != nil {
				return
			}
			if candidate == nil {
				tracer.Info("no known suitable substitute SDIObserver found")
				return
			}
			return ctrl.Result{}, r.manageDataHubs(ctx, candidate, knownManagedNamespace)
		}
		return
	}

	sdiNamespace := obs.Spec.SDINamespace
	if len(sdiNamespace) == 0 {
		sdiNamespace = obs.Namespace
	}

	if nm, ok := r.ManagedDHPerObserver[client.ObjectKeyFromObject(obs)]; !ok {
		tracer.Info("recording new Observer instance")
		r.ManagedDHPerObserver[client.ObjectKeyFromObject(obs)] = sdiNamespace
	} else if nm != sdiNamespace {
		tracer.Info("managed DH namespace change", "original", nm, "new", sdiNamespace)
		_, err = r.orphanDH(ctx, nm)
		r.ManagedDHPerObserver[client.ObjectKeyFromObject(obs)] = sdiNamespace
	}

	managingObs, ok := r.ActiveObserverForDH[sdiNamespace]
	if ok && managingObs.Namespace == obs.Namespace && managingObs.Name == obs.Name {
		if dhCtrl, ok := r.NamespacedControllers[req.NamespacedName]; ok {
			err = sdiobservers.SetBackupAndUpdate(ctx, r.Client, obs, false, managingObs)
			dhCtrl.ReconcileObs(obs)
			return
		}
		err = r.manageDataHubs(ctx, obs, sdiNamespace)
		return
	}
	if ok {
		return rs, sdiobservers.SetBackupAndUpdate(ctx, r.Client, obs, true, managingObs)
	}

	return rs, r.manageDataHubs(ctx, obs, sdiNamespace)
}

func (r *Reconciler) orphanDH(ctx context.Context, dhNamespace string) (changed bool, err error) {
	defer λ.Leave(λ.Enter(log.FromContext(ctx), "dhNamespace", dhNamespace))
	obsNMName, ok := r.ActiveObserverForDH[dhNamespace]
	if !ok {
		return false, nil
	}
	_, ok = r.NamespacedControllers[obsNMName]
	if !ok {
		delete(r.ActiveObserverForDH, dhNamespace)
		return true, nil
	}
	r.destroyController(ctx, obsNMName)
	changed = true
	return
}

func (r *Reconciler) unblockObs(ctx context.Context, obs *sdiv1alpha1.SDIObserver) (update bool) {
	defer λ.Leave(λ.Enter(log.FromContext(ctx), "namespace", obs.Namespace, "name", obs.Name))
	return sdiobservers.SetBackup(ctx, r.Client, obs, false, client.ObjectKeyFromObject(obs))
}

func (r *Reconciler) destroyController(ctx context.Context, obsNMName types.NamespacedName) {
	defer λ.Leave(λ.Enter(log.FromContext(ctx), "observer namespace/name", obsNMName.String()))
	dhctrl, ok := r.NamespacedControllers[obsNMName]
	if !ok {
		return
	}
	dhctrl.Stop()
	delete(r.NamespacedControllers, obsNMName)
	if nm, ok := r.ManagedDHPerObserver[obsNMName]; ok {
		delete(r.ActiveObserverForDH, nm)
	}
	delete(r.ManagedDHPerObserver, obsNMName)
}

// byMostSpecific implements sort.Interface for []SDIObserver based on the SDINamespace field and Backup
// condition.
type byMostSpecific struct {
	dhNamespace string
	items       []sdiv1alpha1.SDIObserver
}

func isObsBlocked(obs *sdiv1alpha1.SDIObserver) bool {
	c := meta.FindStatusCondition(obs.Status.Conditions, "Blocked")
	if c == nil {
		return false
	}
	return c.Status == "True"
}

// TODO: write a unit test
func (a byMostSpecific) Len() int      { return len(a.items) }
func (a byMostSpecific) Swap(i, j int) { a.items[i], a.items[j] = a.items[j], a.items[i] }
func (a byMostSpecific) Less(i, j int) bool {
	if a.items[i].DeletionTimestamp != nil && a.items[j].DeletionTimestamp == nil {
		return false
	}
	if a.items[i].DeletionTimestamp == nil && a.items[j].DeletionTimestamp != nil {
		return true
	}
	if a.items[i].DeletionTimestamp != nil && a.items[j].DeletionTimestamp != nil {
		// don't care, no valid candidates for the DH management
		return (&a.items[i].CreationTimestamp).Before(&a.items[j].CreationTimestamp)
	}
	if a.items[i].Spec.SDINamespace != a.dhNamespace && a.items[j].Spec.SDINamespace == a.dhNamespace {
		return false
	}
	if a.items[i].Spec.SDINamespace == a.dhNamespace && a.items[j].Spec.SDINamespace != a.dhNamespace {
		return true
	}
	if a.items[i].Spec.SDINamespace != a.dhNamespace && a.items[j].Spec.SDINamespace != a.dhNamespace {
		if len(a.items[i].Spec.SDINamespace) > 0 && len(a.items[j].Spec.SDINamespace) == 0 {
			return false
		}
		if len(a.items[i].Spec.SDINamespace) == 0 && len(a.items[j].Spec.SDINamespace) > 0 {
			return true
		}
		if len(a.items[i].Spec.SDINamespace) > 0 && len(a.items[j].Spec.SDINamespace) > 0 {
			// don't care, no valid candidates for the DH management
			return (&a.items[i].CreationTimestamp).Before(&a.items[j].CreationTimestamp)
		}
	}
	if a.items[i].Namespace != a.dhNamespace && a.items[j].Namespace == a.dhNamespace {
		return false
	}
	if a.items[i].Namespace == a.dhNamespace && a.items[j].Namespace != a.dhNamespace {
		return true
	}
	if a.items[i].Namespace != a.dhNamespace && a.items[j].Namespace != a.dhNamespace {
		// don't care, no valid candidates for the DH management
		return (&a.items[i].CreationTimestamp).Before(&a.items[j].CreationTimestamp)
	}
	if isObsBlocked(&a.items[i]) && !isObsBlocked(&a.items[j]) {
		return false
	}
	if !isObsBlocked(&a.items[i]) && isObsBlocked(&a.items[j]) {
		return true
	}
	// prefer newer over older
	return !(&a.items[i].CreationTimestamp).Before(&a.items[j].CreationTimestamp)
}

func (r *Reconciler) findNewObsForDH(
	ctx context.Context,
	dhNamespace string,
	// Reduce the searched instances only to those already tracked by this reconciler.
	onlyTracked bool,
) (*sdiv1alpha1.SDIObserver, error) {
	tracer := λ.Enter(log.FromContext(ctx))
	defer λ.Leave(tracer)

	var obss sdiv1alpha1.SDIObserverList
	err := r.List(ctx, &obss)
	if err != nil || len(obss.Items) == 0 {
		return nil, err
	}
	sort.Sort(byMostSpecific{
		dhNamespace: dhNamespace,
		items:       obss.Items,
	})
	for _, obs := range obss.Items {
		if obs.DeletionTimestamp == nil && (obs.Spec.SDINamespace == dhNamespace ||
			(len(obs.Spec.SDINamespace) == 0 && obs.Namespace == dhNamespace)) {
			if _, ok := r.ManagedDHPerObserver[client.ObjectKeyFromObject(&obs)]; !onlyTracked || ok {
				return &obs, nil
			}
		} else if !onlyTracked {
			// all the valid candidates have been exhausted
			break
		}
	}
	return nil, nil
}

func (r *Reconciler) manageDataHubs(
	ctx context.Context,
	obs *sdiv1alpha1.SDIObserver,
	sdiNamespace string,
) error {
	tracer := λ.Enter(log.FromContext(ctx), "SDI namespace", sdiNamespace)
	defer λ.Leave(tracer)

	obsNMName := client.ObjectKeyFromObject(obs)
	if _, ok := r.NamespacedControllers[obsNMName]; ok {
		// already managed
		return nil
	}
	tracer.Info("creating the controller for SAP Data Intelligence instance", "SDI namespace", sdiNamespace)

	ctrl, err := namespaced.NewController(
		r.Client,
		r.Scheme,
		obsNMName,
		sdiNamespace,
		r.Mgr,
		controller.Options{})
	if err != nil {
		return err
	}

	err = ctrl.Start(ctx)
	if err != nil {
		tracer.Error(err, "controller of SDI instance", "SDI namespace", sdiNamespace)
		return err
	}
	tracer.Info("started the controller")

	r.ActiveObserverForDH[sdiNamespace] = obsNMName
	r.ManagedDHPerObserver[obsNMName] = sdiNamespace
	r.NamespacedControllers[obsNMName] = ctrl
	tracer.Info("starting the management of SDI instance", "SDI namespace", sdiNamespace)
	if err != nil {
		tracer.Error(err, "controller of SDI instance", "SDI namespace", sdiNamespace)
		return err
	}

	if r.unblockObs(ctx, obs) {
		err = r.Update(ctx, obs)
		if err != nil {
			tracer.Error(err, "failed to update the SDIObserver", "SDIObserver instance", obsNMName.String())
		}
	}
	ctrl.ReconcileObs(&sdiv1alpha1.SDIObserver{
		ObjectMeta: metav1.ObjectMeta{
			Namespace: obsNMName.Namespace,
			Name:      obsNMName.Name,
		},
	})
	return err
}

func (r *Reconciler) SetupWithManager(mgr ctrl.Manager) error {
	var obs = &sdiv1alpha1.SDIObserver{}
	return ctrl.NewControllerManagedBy(mgr).For(obs).Complete(r)
}
