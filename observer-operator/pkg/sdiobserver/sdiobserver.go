package sdiobserver

import (
	"context"
	"fmt"
	sdiv1alpha1 "github.com/redhat-sap/sap-data-intelligence/observer-operator/api/v1alpha1"
	"github.com/redhat-sap/sap-data-intelligence/observer-operator/pkg/adjuster"
)

// SDIObserver encapsulates operations to adjust SDIObserver resources.
type SDIObserver struct {
	obs *sdiv1alpha1.SDIObserver
}

// New creates a new SDIObserver instance.
func New(obs *sdiv1alpha1.SDIObserver) *SDIObserver {
	return &SDIObserver{obs: obs}
}

// AdjustNodes adjusts the SDI node configuration based on the observer's spec.
func (so *SDIObserver) AdjustNodes(a *adjuster.Adjuster, ctx context.Context) error {
	if !so.obs.Spec.ManageSDINodeConfig {
		a.Logger().V(0).Info("Node config is unmanaged; skipping adjustment.")
		return nil
	}

	a.Logger().V(0).Info("Adjusting SDI nodes.")
	if err := a.AdjustSDINodes(so.obs, ctx); err != nil {
		return err
	}

	a.Logger().Info("Successfully adjusted SDI Nodes.")
	return nil
}

// AdjustStorage currently does nothing; needs implementation.
func (so *SDIObserver) AdjustStorage(a *adjuster.Adjuster, ctx context.Context) error {
	a.Logger().V(0).Info("Storage adjustment is currently making no changes.")
	return nil
}

// AdjustSDIConfig adjusts SDI configuration components such as namespaces, RBAC, and daemon sets.
func (so *SDIObserver) AdjustSDIConfig(a *adjuster.Adjuster, ctx context.Context) error {
	a.Logger().V(0).Info("Adjusting SDI configuration.")

	for _, ns := range []string{a.Namespace, so.obs.Spec.SDINamespace, so.obs.Spec.SLCBNamespace, "datahub-system"} {
		if err := a.AdjustNamespaceAnnotation(ns, so.obs.Spec.SDINodeLabel, ctx); err != nil {
			return err
		}
	}
	if err := a.AdjustSDIRbac(so.obs.Spec.SDINamespace, so.obs, ctx); err != nil {
		return err
	}

	var errs []error

	if err := a.AdjustSDIDiagnosticsFluentdDaemonsetContainerPrivilege(so.obs.Spec.SDINamespace, so.obs, ctx); err != nil {
		a.Logger().Error(err, "Failed to adjust SDI diagnostics Fluentd DaemonSet container privilege")
		errs = append(errs, err)
	}
	if err := a.AdjustSDIVSystemVrepStatefulSets(so.obs.Spec.SDINamespace, so.obs, ctx); err != nil {
		a.Logger().Error(err, "Failed to adjust SDI VSystem Vrep StatefulSets")
		errs = append(errs, err)
	}

	if len(errs) > 0 {
		for _, err := range errs {
			a.Logger().Error(err, "Error encountered while adjusting SDI configuration")
		}
		return fmt.Errorf("adjust SDI configuration completed with errors")
	}

	a.Logger().Info("Successfully adjusted SDI configuration.")

	return nil
}

// AdjustSLCBNetwork adjusts the SLCB network configuration.
func (so *SDIObserver) AdjustSLCBNetwork(a *adjuster.Adjuster, ctx context.Context) error {
	a.Logger().V(0).Info("Adjusting SLCB route.")

	if err := a.AdjustSLCBRoute(so.obs.Spec.SLCBNamespace, so.obs, ctx); err != nil {
		return err
	}
	a.Logger().Info("Successfully adjusted SLCB route.")
	return nil
}

// AdjustSDINetwork adjusts the SDI network configuration.
func (so *SDIObserver) AdjustSDINetwork(a *adjuster.Adjuster, ctx context.Context) error {
	a.Logger().V(0).Info("Adjusting SDI route.")

	if err := a.AdjustSDIVsystemRoute(so.obs.Spec.SDINamespace, so.obs, ctx); err != nil {
		return fmt.Errorf("failed to adjust SDI VSystem route: %w", err)
	}
	a.Logger().Info("Successfully adjusted SDI route.")
	return nil
}
