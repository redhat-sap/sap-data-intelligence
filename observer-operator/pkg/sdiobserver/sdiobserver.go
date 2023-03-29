package sdiobserver

import (
	"context"
	sdiv1alpha1 "github.com/redhat-sap/sap-data-intelligence/observer-operator/api/v1alpha1"
	"github.com/redhat-sap/sap-data-intelligence/observer-operator/pkg/adjuster"
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
		return err
	}
	return nil
}

func (so *SDIObserver) AdjustStorage(a *adjuster.Adjuster, c context.Context) error {
	//TODO implement me
	return nil
}

func (so *SDIObserver) AdjustSDIConfig(a *adjuster.Adjuster, c context.Context) error {
	a.Logger().V(0).Info("Trying to adjust the SDIConfig")
	err := a.AdjustSDIDiagnosticsFluentdDaemonsetContainerPrivilege(so.obs.Spec.SDINamespace, so.obs, c)
	if err != nil {
		a.Logger().V(1).Info(err.Error())
		return err
	}

	err = a.AdjustSDIVSystemVrepStatefulSets(so.obs.Spec.SDINamespace, so.obs, c)
	if err != nil {
		a.Logger().V(1).Info(err.Error())
		return err
	}

	err = a.AdjustNamespacesNodeSelectorAnnotation(so.obs, c)
	if err != nil {
		a.Logger().V(1).Info(err.Error())
		return err
	}
	return nil
}

func New(obs *sdiv1alpha1.SDIObserver) *SDIObserver {
	return &SDIObserver{
		obs: obs,
	}
}

func (so *SDIObserver) AdjustNetwork(a *adjuster.Adjuster, ctx context.Context) error {

	a.Logger().V(0).Info("Trying to adjust the network")
	err := a.AdjustSDIVsystemRoute(so.obs.Spec.SDINamespace, so.obs, ctx)
	if err != nil {
		a.Logger().V(1).Info(err.Error())
		return err
	}

	err = a.AdjustSLCBRoute(so.obs.Spec.SLCBNamespace, so.obs, ctx)
	if err != nil {
		a.Logger().V(1).Info(err.Error())
		return err
	}

	return nil
}
