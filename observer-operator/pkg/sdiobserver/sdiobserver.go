package sdiobserver

import (
	"context"
	"fmt"
	sdiv1alpha1 "github.com/redhat-sap/sap-data-intelligence/observer-operator/api/v1alpha1"
	"github.com/redhat-sap/sap-data-intelligence/observer-operator/pkg/adjuster"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"time"
)

type SDIObserver struct {
	obs *sdiv1alpha1.SDIObserver
}

func (so *SDIObserver) AdjustNodes(a *adjuster.Adjuster, c context.Context) error {

	if !so.obs.Spec.ManageSDINodeConfig {
		a.Logger().V(0).Info("Node config is unmanaged. Skip...")
		return nil
	}

	a.Logger().V(0).Info("Trying to adjust the SDI nodes")
	err := a.AdjustSDINodes(so.obs, c)
	if err != nil {
		meta.SetStatusCondition(&so.obs.Status.Conditions, metav1.Condition{
			Type:               "OperatorDegraded",
			Status:             metav1.ConditionTrue,
			Reason:             sdiv1alpha1.ReasonOperandResourceFailed,
			LastTransitionTime: metav1.NewTime(time.Now()),
			Message:            fmt.Sprintf("unable to adjust SDI nodes: %s", err.Error()),
		})
		return err
	}

	meta.SetStatusCondition(&so.obs.Status.Conditions, metav1.Condition{
		Type:               "OperatorDegraded",
		Status:             metav1.ConditionFalse,
		Reason:             sdiv1alpha1.ReasonSucceeded,
		LastTransitionTime: metav1.NewTime(time.Now()),
		Message:            "operator successfully reconciling SDI nodes",
	})
	return nil
}

func (so *SDIObserver) AdjustStorage(a *adjuster.Adjuster, c context.Context) error {
	//TODO implement me
	return nil
}

func (so *SDIObserver) AdjustSDIConfig(a *adjuster.Adjuster, c context.Context) error {
	a.Logger().V(0).Info("Trying to adjust the SDIConfig")

	err := a.AdjustNamespacesNodeSelectorAnnotation(so.obs, c)
	if err != nil {
		meta.SetStatusCondition(&so.obs.Status.Conditions, metav1.Condition{
			Type:               "OperatorDegraded",
			Status:             metav1.ConditionTrue,
			Reason:             sdiv1alpha1.ReasonOperandResourceFailed,
			LastTransitionTime: metav1.NewTime(time.Now()),
			Message:            fmt.Sprintf("unable to adjust namespace node selector: %s", err.Error()),
		})
		return err
	}
	err = a.AdjustSDIRbac(so.obs.Spec.SDINamespace, so.obs, c)
	if err != nil {
		meta.SetStatusCondition(&so.obs.Status.Conditions, metav1.Condition{
			Type:               "OperatorDegraded",
			Status:             metav1.ConditionTrue,
			Reason:             sdiv1alpha1.ReasonOperandResourceFailed,
			LastTransitionTime: metav1.NewTime(time.Now()),
			Message:            fmt.Sprintf("unable to adjust rbac for SDI: %s", err.Error()),
		})
		return err
	}

	err = a.AdjustSDIDiagnosticsFluentdDaemonsetContainerPrivilege(so.obs.Spec.SDINamespace, so.obs, c)
	if err != nil {
		meta.SetStatusCondition(&so.obs.Status.Conditions, metav1.Condition{
			Type:               "OperatorDegraded",
			Status:             metav1.ConditionTrue,
			Reason:             sdiv1alpha1.ReasonOperandResourceFailed,
			LastTransitionTime: metav1.NewTime(time.Now()),
			Message:            fmt.Sprintf("unable to adjust SDI diagnostics fluentd daemonset: %s", err.Error()),
		})
		return err
	}

	err = a.AdjustSDIVSystemVrepStatefulSets(so.obs.Spec.SDINamespace, so.obs, c)
	if err != nil {
		meta.SetStatusCondition(&so.obs.Status.Conditions, metav1.Condition{
			Type:               "OperatorDegraded",
			Status:             metav1.ConditionTrue,
			Reason:             sdiv1alpha1.ReasonOperandResourceFailed,
			LastTransitionTime: metav1.NewTime(time.Now()),
			Message:            fmt.Sprintf("unable to adjust SDI vSystem vRep StatefulSet: %s", err.Error()),
		})
		return err
	}

	meta.SetStatusCondition(&so.obs.Status.Conditions, metav1.Condition{
		Type:               "OperatorDegraded",
		Status:             metav1.ConditionFalse,
		Reason:             sdiv1alpha1.ReasonSucceeded,
		LastTransitionTime: metav1.NewTime(time.Now()),
		Message:            "operator successfully reconciling SDI config",
	})
	return nil
}

func New(obs *sdiv1alpha1.SDIObserver) *SDIObserver {
	return &SDIObserver{
		obs: obs,
	}
}

func (so *SDIObserver) AdjustSLCBNetwork(a *adjuster.Adjuster, ctx context.Context) error {

	a.Logger().V(0).Info("Trying to adjust the SLCB network")

	err := a.AdjustSLCBRoute(so.obs.Spec.SLCBNamespace, so.obs, ctx)
	if err != nil {
		meta.SetStatusCondition(&so.obs.Status.Conditions, metav1.Condition{
			Type:               "OperatorDegraded",
			Status:             metav1.ConditionTrue,
			Reason:             sdiv1alpha1.ReasonOperandResourceFailed,
			LastTransitionTime: metav1.NewTime(time.Now()),
			Message:            fmt.Sprintf("unable to adjust SLCB Route: %s", err.Error()),
		})
		return err
	}

	meta.SetStatusCondition(&so.obs.Status.Conditions, metav1.Condition{
		Type:               "OperatorDegraded",
		Status:             metav1.ConditionFalse,
		Reason:             sdiv1alpha1.ReasonSucceeded,
		LastTransitionTime: metav1.NewTime(time.Now()),
		Message:            "operator successfully reconciling SDI route",
	})
	return nil
}

func (so *SDIObserver) AdjustSDINetwork(a *adjuster.Adjuster, ctx context.Context) error {

	a.Logger().V(0).Info("Trying to adjust the SDI network")

	err := a.AdjustSDIVsystemRoute(so.obs.Spec.SDINamespace, so.obs, ctx)
	if err != nil {
		meta.SetStatusCondition(&so.obs.Status.Conditions, metav1.Condition{
			Type:               "OperatorDegraded",
			Status:             metav1.ConditionTrue,
			Reason:             sdiv1alpha1.ReasonOperandResourceFailed,
			LastTransitionTime: metav1.NewTime(time.Now()),
			Message:            fmt.Sprintf("unable to adjust SDI vSystem Route: %s", err.Error()),
		})
		return err
	}

	meta.SetStatusCondition(&so.obs.Status.Conditions, metav1.Condition{
		Type:               "OperatorDegraded",
		Status:             metav1.ConditionFalse,
		Reason:             sdiv1alpha1.ReasonSucceeded,
		LastTransitionTime: metav1.NewTime(time.Now()),
		Message:            "operator successfully reconciling SDI route",
	})
	return nil
}
