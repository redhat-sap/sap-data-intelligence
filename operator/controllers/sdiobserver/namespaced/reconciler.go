package namespaced

import (
	"context"
	"fmt"
	"strings"
	"time"

	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/tools/reference"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"

	"github.com/redhat-sap/sap-data-intelligence/operator/api/v1alpha1"
	sdiv1alpha1 "github.com/redhat-sap/sap-data-intelligence/operator/api/v1alpha1"
	"github.com/redhat-sap/sap-data-intelligence/operator/util/sdiobservers"
)

type reconciler struct {
	client         client.Client
	dhClient       DHClient
	scheme         *runtime.Scheme
	namespacedName types.NamespacedName
	// Namespace where the managed DataHub resource lives.
	dhNamespace string
}

var _ reconcile.Reconciler = &reconciler{}

//+kubebuilder:rbac:groups=route.openshift.io;"",resources=routes,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups=route.openshift.io;"",resources=routes/custom-host,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups=route.openshift.io;"",resources=routes/status,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups=core,resources=services,verbs=get;list;watch
//+kubebuilder:rbac:groups=core,resources=secrets,verbs=get;list;watch
//+kubebuilder:rbac:groups=installers.datahub.sap.com,resources=datahubs,verbs=get;list;watch

// Reconcile is part of the main kubernetes reconciliation loop which aims to
// move the current state of the cluster closer to the desired state.
//
// For more details, check Reconcile and its Result here:
// - https://pkg.go.dev/sigs.k8s.io/controller-runtime@v0.9.2/pkg/reconcile
func (r *reconciler) Reconcile(ctx context.Context, req reconcile.Request) (rs reconcile.Result, err error) {
	logger := log.FromContext(ctx)
	logger.Info("(*reconciler).Reconcile: started", "request", req)
	defer logger.Info("(*reconciler).Reconcile: finished")
	select {
	case <-ctx.Done():
		logger.Info("(*reconciler).Reconcile: context cancelled")
		return
	default:
	}

	obs := &sdiv1alpha1.SDIObserver{}
	logger.Info("(*reconciler).Reconcile: getting obs")
	if err = r.client.Get(ctx, r.namespacedName, obs); err != nil {
		logger.Error(err, "(*reconciler).Reconcile: failed to get SDIObserver instance")
		return
	}

	ready, degraded, progressing, err := r.doReconcileObs(ctx, obs)
	if err != nil {
		logger.Error(err, "(*reconciler).Reconcile: failed to reconcile SDI Observer")
	}
	err = r.updateStatus(ctx, obs, ready, degraded, progressing)
	if err != nil {
		logger.Error(err, "(*reconciler).Reconcile: failed to update SDI Observer status")
	}
	// TODO: handle FailedGet on DH - require after some time
	if sdiobservers.IsStatusInCondition(obs, "FailedGet") {
		rs.RequeueAfter = time.Second * 30
		rs.Requeue = true
	}
	return rs, err
}

func (r *reconciler) doReconcileObs(
	ctx context.Context,
	obs *sdiv1alpha1.SDIObserver,
) (ready, degraded, progressing []metav1.Condition, err error) {
	logger := log.FromContext(ctx)
	logger.Info("(*reconciler).Reconcile: getting the managed DH")
	var dh *unstructured.Unstructured
	dh, err = r.dhClient.Get(ctx, r.dhNamespace)
	logger.Info("(*reconciler).Reconcile: do we have an error?", "err", err)
	removeManagedObjects := false
	if err != nil {
		if errors.IsNotFound(err) {
			// TODO: delete the owned objects
			ready = append(ready, metav1.Condition{
				Status:  metav1.ConditionFalse,
				Reason:  "NotFound",
				Message: fmt.Sprintf("waiting for the managed DH to appear: %v", err),
			})
			progressing = append(progressing, metav1.Condition{
				Status:  metav1.ConditionFalse,
				Reason:  "NotFound",
				Message: fmt.Sprintf("waiting for the managed DH to appear: %v", err),
			})
			logger.Info("(*reconciler).Reconcile: DH not found")
			err = nil
			obs.Status.ManagedDataHubRef = nil
			return
		}

		ready = append(ready, metav1.Condition{
			Status:  metav1.ConditionUnknown,
			Reason:  "FailedGet",
			Message: fmt.Sprintf("failed to fetch the managed DH: %v", err),
		})
		progressing = append(progressing, metav1.Condition{
			Status:  metav1.ConditionFalse,
			Reason:  "FailedGet",
			Message: fmt.Sprintf("failed to fetch the managed DH: %v", err),
		})
		degraded = append(degraded, metav1.Condition{
			Status:  metav1.ConditionTrue,
			Reason:  "FailedGet",
			Message: fmt.Sprintf("failed to fetch the managed DH: %v", err),
		})
		return
	}

	logger.Info("(*reconciler).Reconcile: handling managed DH")
	// Backup status is controlled by the parent controller
	if sdiobservers.IsBackup(obs) {
		msg := "there is another SDIObserver instance managing the SDINamespace"
		reason := "Backup"
		ready = append(ready, metav1.Condition{Status: metav1.ConditionUnknown, Reason: reason, Message: msg})
		progressing = append(progressing, metav1.Condition{Status: metav1.ConditionUnknown, Reason: reason, Message: msg})
		degraded = append(degraded, metav1.Condition{Status: metav1.ConditionFalse, Reason: reason, Message: msg})
		obs.Status.ManagedDataHubRef = nil
		return
	}

	ref, err := reference.GetReference(r.scheme, dh)
	if err != nil {
		degraded = append(degraded, metav1.Condition{
			Status:  metav1.ConditionTrue,
			Reason:  "FailedGetRef",
			Message: fmt.Sprintf("failed to get reference to DataHub: %v", err),
		})
	} else {
		obs.Status.ManagedDataHubRef = ref
	}

	owner := obs
	if removeManagedObjects {
		owner.Spec.VSystemRoute = sdiv1alpha1.SDIObserverSpecRoute{
			ManagementState: sdiv1alpha1.RouteManagementStateRemoved,
		}
	}
	err = manageVSystemRoute(ctx, r.scheme, r.client, owner, r.dhNamespace)
	if err != nil {
		logger.Error(err, "failed to reconcile vsystem route")
		ready = append(ready, metav1.Condition{
			Status:  metav1.ConditionFalse,
			Reason:  "VSystemRoute",
			Message: fmt.Sprintf("failed to reconcile vsystem route: %v", err),
		})
		return
	}

	ready = append(ready, metav1.Condition{
		Type:   "Ready",
		Status: metav1.ConditionTrue,
		Reason: v1alpha1.ConditionReasonAsExpected,
	})
	if sdiobservers.IsRouteInCondition(obs.Status.VSystemRoute, "Degraded") &&
		!sdiobservers.IsRouteConditionKnown(obs.Status.VSystemRoute, "Exposed") {
		progressing = append(progressing, metav1.Condition{
			Status: metav1.ConditionTrue,
			Reason: "VSystemRoute",
			Message: (func() string {
				if owner.Spec.VSystemRoute.ManagementState == sdiv1alpha1.RouteManagementStateManaged {
					return "waiting for vsystem route to be admitted"
				}
				return "removing the vsystem route"
			})(),
		})
	} else {
		progressing = append(progressing, metav1.Condition{
			Status: metav1.ConditionFalse,
			Reason: "VSystemRoute",
			Message: (func() string {
				if owner.Spec.VSystemRoute.ManagementState == sdiv1alpha1.RouteManagementStateManaged {
					return "vsystem route is up to date"
				}
				return "vsystem route is removed"
			})(),
		})
	}

	degradedStatus := metav1.ConditionFalse
	message := ""
	if sdiobservers.IsRouteInCondition(obs.Status.VSystemRoute, "Degraded") {
		degradedStatus = metav1.ConditionTrue
		message = meta.FindStatusCondition(obs.Status.VSystemRoute.Conditions, "Degraded").Message
	}
	degraded = append(degraded, metav1.Condition{
		Status:  degradedStatus,
		Reason:  "VSystemRoute",
		Message: message,
	})
	return
}

// Consolidate lists of conditions into a single one for each type
func (r *reconciler) updateStatus(
	ctx context.Context,
	obs *sdiv1alpha1.SDIObserver,
	ready []metav1.Condition,
	degraded []metav1.Condition,
	progressing []metav1.Condition,
) error {
	logger := log.FromContext(ctx)
	for _, clist := range []struct {
		Type       string
		Conditions []metav1.Condition
	}{
		{Type: "Ready", Conditions: ready},
		{Type: "Degraded", Conditions: degraded},
		{Type: "Progressing", Conditions: progressing},
	} {
		current := meta.FindStatusCondition(obs.Status.Conditions, clist.Type)
		if len(clist.Conditions) == 0 {
			if current == nil {
				meta.SetStatusCondition(&obs.Status.Conditions, metav1.Condition{
					Type:   clist.Type,
					Status: metav1.ConditionUnknown,
					Reason: "Unknown",
				})
			}
			continue
		}

		product := metav1.Condition{
			Type: clist.Type,
			Status: (func() metav1.ConditionStatus {
				// defaults
				switch clist.Type {
				case "Ready":
					return metav1.ConditionTrue
				default:
					return metav1.ConditionFalse
				}
			})(),
			Reason:             "Unknown",
			ObservedGeneration: obs.Generation,
		}

		extendMessage := func(msg string) {
			if len(product.Message) == 0 {
				product.Message = msg
			} else {
				product.Message = strings.Join([]string{product.Message, msg}, "\n")
			}
		}
		keepFirst := func(dst *string, msg string) {
			if len(*dst) == 0 || *dst == "Unknown" {
				*dst = msg
			}
		}
		for _, c := range clist.Conditions {
			switch clist.Type {
			case "Ready":
				switch {
				case c.Status == metav1.ConditionFalse || product.Status == metav1.ConditionFalse:
					product.Status = metav1.ConditionFalse
					if c.Status == metav1.ConditionFalse && product.Status == metav1.ConditionFalse {
						keepFirst(&product.Reason, c.Reason)
						extendMessage(c.Message)
					} else if c.Status == metav1.ConditionFalse {
						product.Reason = c.Reason
						product.Message = c.Message
					}
				case c.Status == metav1.ConditionUnknown && product.Status != metav1.ConditionFalse:
					product.Status = metav1.ConditionUnknown
					if c.Status == metav1.ConditionUnknown && product.Status == metav1.ConditionUnknown {
						keepFirst(&product.Reason, c.Reason)
						extendMessage(c.Message)
					} else if c.Status == metav1.ConditionUnknown {
						product.Reason = c.Reason
						product.Message = c.Message
					}
				case c.Status == metav1.ConditionTrue && product.Status == metav1.ConditionTrue:
					product.Status = metav1.ConditionTrue
					keepFirst(&product.Reason, c.Reason)
					keepFirst(&product.Message, c.Message)
				}

			case "Progressing", "Degraded":
				switch {
				case c.Status == metav1.ConditionTrue || product.Status == metav1.ConditionTrue:
					product.Status = metav1.ConditionTrue
					if c.Status == metav1.ConditionTrue && product.Status == metav1.ConditionTrue {
						keepFirst(&product.Reason, c.Reason)
						extendMessage(c.Message)
					} else if c.Status == metav1.ConditionTrue {
						product.Reason = c.Reason
						product.Message = c.Message
					}
				case (c.Status == metav1.ConditionUnknown && product.Status != metav1.ConditionTrue):
					product.Status = metav1.ConditionUnknown
					if c.Status == metav1.ConditionUnknown && product.Status == metav1.ConditionUnknown {
						keepFirst(&product.Reason, c.Reason)
						extendMessage(c.Message)
					} else if c.Status == metav1.ConditionUnknown {
						product.Reason = c.Reason
						product.Message = c.Message
					}
				case c.Status == metav1.ConditionFalse && product.Status == metav1.ConditionFalse:
					product.Status = metav1.ConditionFalse
					keepFirst(&product.Reason, c.Reason)
					keepFirst(&product.Message, c.Message)
				}
			}
		}
		logger.Info("(*reconciler).updateStatus: setting condition", "type", product.Type, "status", product.Status, "reason", product.Reason)
		meta.SetStatusCondition(&obs.Status.Conditions, product)
	}
	// if this ends up in a conflict, let's just do a new reconciliation round
	logger.Info("(*reconciler).updateStatus: updating obs", "obs", fmt.Sprintf("%#v", obs))
	return r.client.Status().Update(ctx, obs)
}
