package adjuster

import (
	"context"
	"fmt"
	routev1 "github.com/openshift/api/route/v1"
	apiv2 "github.com/operator-framework/api/pkg/operators/v2"
	"github.com/operator-framework/operator-lib/conditions"
	sdiv1alpha1 "github.com/redhat-sap/sap-data-intelligence/observer-operator/api/v1alpha1"
	"github.com/redhat-sap/sap-data-intelligence/observer-operator/assets"
	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	utilerrors "k8s.io/apimachinery/pkg/util/errors"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"time"
)

func (a *Adjuster) AdjustSDIVsystemRoute(ns string, obs *sdiv1alpha1.SDIObserver, ctx context.Context) error {

	name := "vsystem"
	route := &routev1.Route{
		ObjectMeta: metav1.ObjectMeta{
			Name:      name,
			Namespace: ns,
		},
	}

	create := false

	err := a.Reconciler.Get(ctx, client.ObjectKey{Name: name, Namespace: ns}, route)

	if err != nil && errors.IsNotFound(err) {
		create = true
		route = assets.GetRouteFromFile("manifests/route-vsystem.yaml")
	} else if err != nil {
		a.logger.Error(err, "Error getting existing sdi vsystem route.")
		meta.SetStatusCondition(&obs.Status.Conditions, metav1.Condition{
			Type:               "OperatorDegraded",
			Status:             metav1.ConditionTrue,
			Reason:             sdiv1alpha1.ReasonRouteNotAvailable,
			LastTransitionTime: metav1.NewTime(time.Now()),
			Message:            fmt.Sprintf("unable to get operand route: %s", err.Error()),
		})
		return utilerrors.NewAggregate([]error{err, a.Reconciler.Status().Update(ctx, obs)})
	}

	ctrl.SetControllerReference(obs, route, a.Reconciler.Scheme)

	if create {
		err = a.Reconciler.Create(ctx, route)
	} else {
		err = a.Reconciler.Update(ctx, route)
	}

	if err != nil {
		meta.SetStatusCondition(&obs.Status.Conditions, metav1.Condition{
			Type:               "OperatorDegraded",
			Status:             metav1.ConditionTrue,
			Reason:             sdiv1alpha1.ReasonOperandRouteFailed,
			LastTransitionTime: metav1.NewTime(time.Now()),
			Message:            fmt.Sprintf("unable to update operand route: %s", err.Error()),
		})
		return utilerrors.NewAggregate([]error{err, a.Reconciler.Status().Update(ctx, obs)})
	}

	meta.SetStatusCondition(&obs.Status.Conditions, metav1.Condition{
		Type:               "OperatorDegraded",
		Status:             metav1.ConditionFalse,
		Reason:             sdiv1alpha1.ReasonSucceeded,
		LastTransitionTime: metav1.NewTime(time.Now()),
		Message:            "operator successfully reconciling",
	})
	a.Reconciler.Status().Update(ctx, obs)

	condition, err := conditions.InClusterFactory{Client: a.Reconciler.Client}.
		NewCondition(apiv2.ConditionType(apiv2.Upgradeable))

	if err != nil {
		return err
	}

	err = condition.Set(ctx, metav1.ConditionTrue,
		conditions.WithReason("OperatorUpgradeable"),
		conditions.WithMessage("The operator is currently upgradeable"))
	if err != nil {
		return err
	}

	return utilerrors.NewAggregate([]error{err, a.Reconciler.Status().Update(ctx, obs)})
}

func (a *Adjuster) AdjustSLCBRoute(ns string, obs *sdiv1alpha1.SDIObserver, ctx context.Context) error {

	name := "sap-slcbridge"
	route := &routev1.Route{
		ObjectMeta: metav1.ObjectMeta{
			Name:      name,
			Namespace: ns,
		},
	}

	create := false

	err := a.Reconciler.Get(ctx, client.ObjectKey{Name: name, Namespace: ns}, route)

	if err != nil && errors.IsNotFound(err) {
		create = true
		route = assets.GetRouteFromFile("manifests/route-sap-slcbridge.yaml")
	} else if err != nil {
		a.logger.Error(err, "Error getting existing sap-slcbridge route.")
		meta.SetStatusCondition(&obs.Status.Conditions, metav1.Condition{
			Type:               "OperatorDegraded",
			Status:             metav1.ConditionTrue,
			Reason:             sdiv1alpha1.ReasonRouteNotAvailable,
			LastTransitionTime: metav1.NewTime(time.Now()),
			Message:            fmt.Sprintf("unable to get operand deployment: %s", err.Error()),
		})
		return utilerrors.NewAggregate([]error{err, a.Reconciler.Status().Update(ctx, obs)})
	}

	ctrl.SetControllerReference(obs, route, a.Reconciler.Scheme)

	if create {
		err = a.Reconciler.Create(ctx, route)
	} else {
		err = a.Reconciler.Update(ctx, route)
	}

	meta.SetStatusCondition(&obs.Status.Conditions, metav1.Condition{
		Type:               "OperatorDegraded",
		Status:             metav1.ConditionFalse,
		Reason:             sdiv1alpha1.ReasonSucceeded,
		LastTransitionTime: metav1.NewTime(time.Now()),
		Message:            "operator successfully reconciling",
	})
	a.Reconciler.Status().Update(ctx, obs)

	condition, err := conditions.InClusterFactory{Client: a.Reconciler.Client}.
		NewCondition(apiv2.ConditionType(apiv2.Upgradeable))

	if err != nil {
		return err
	}

	err = condition.Set(ctx, metav1.ConditionTrue,
		conditions.WithReason("OperatorUpgradeable"),
		conditions.WithMessage("The operator is currently upgradeable"))
	if err != nil {
		return err
	}

	return utilerrors.NewAggregate([]error{err, a.Reconciler.Status().Update(ctx, obs)})
}
