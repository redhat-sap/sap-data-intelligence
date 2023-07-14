package sdiobserver

import (
	"context"
	sdiv1alpha1 "github.com/redhat-sap/sap-data-intelligence/observer-operator/api/v1alpha1"
	"github.com/redhat-sap/sap-data-intelligence/observer-operator/pkg/adjuster"
)

type SDIObserver struct {
	obs *sdiv1alpha1.SDIObserver
}

func (so *SDIObserver) AdjustNodes(a *adjuster.Adjuster, ctx context.Context) error {

	if !so.obs.Spec.ManageSDINodeConfig {
		a.Logger().V(0).Info("Node config is unmanaged. Skip...")
		return nil
	}

	a.Logger().V(0).Info("Trying to adjust the SDI nodes")
	if err := a.AdjustSDINodes(so.obs, ctx); err != nil {
		return err
	}

	return nil
}

func (so *SDIObserver) AdjustStorage(a *adjuster.Adjuster, c context.Context) error {
	//TODO implement me
	return nil
}

func (so *SDIObserver) AdjustSDIConfig(a *adjuster.Adjuster, ctx context.Context) error {
	a.Logger().V(0).Info("Trying to adjust the SDIConfig")

	if err := a.AdjustNamespacesNodeSelectorAnnotation(so.obs, ctx); err != nil {
		return err
	}
	if err := a.AdjustSDIRbac(so.obs.Spec.SDINamespace, so.obs, ctx); err != nil {
		return err
	}

	if err := a.AdjustSDIDiagnosticsFluentdDaemonsetContainerPrivilege(so.obs.Spec.SDINamespace, so.obs, ctx); err != nil {
		return err
	}

	if err := a.AdjustSDIVSystemVrepStatefulSets(so.obs.Spec.SDINamespace, so.obs, ctx); err != nil {
		return err
	}

	return nil
}

func New(obs *sdiv1alpha1.SDIObserver) *SDIObserver {
	return &SDIObserver{
		obs: obs,
	}
}

func (so *SDIObserver) AdjustSLCBNetwork(a *adjuster.Adjuster, ctx context.Context) error {

	a.Logger().V(0).Info("Trying to adjust the SLCB network")

	if err := a.AdjustSLCBRoute(so.obs.Spec.SLCBNamespace, so.obs, ctx); err != nil {
		return err
	}

	return nil
}

func (so *SDIObserver) AdjustSDINetwork(a *adjuster.Adjuster, ctx context.Context) error {

	a.Logger().V(0).Info("Trying to adjust the SDI network")

	if err := a.AdjustSDIVsystemRoute(so.obs.Spec.SDINamespace, so.obs, ctx); err != nil {
		return err
	}

	return nil
}
