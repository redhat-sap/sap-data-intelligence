package sdiobserver

import (
	"context"
	sdiv1alpha1 "github.com/redhat-sap/sap-data-intelligence/observer-operator/api/v1alpha1"
	"github.com/redhat-sap/sap-data-intelligence/observer-operator/pkg/adjuster"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"time"
)

type SDIObserver struct {
	obs *sdiv1alpha1.SDIObserver
}

func (so *SDIObserver) AdjustNodes(s *adjuster.Adjuster, c context.Context) error {
	//TODO implement me
	return nil
}

func (so *SDIObserver) AdjustStorage(s *adjuster.Adjuster, c context.Context) error {
	//TODO implement me
	return nil
}

func (so *SDIObserver) AdjustSDIConfig(s *adjuster.Adjuster, c context.Context) error {
	//TODO implement me
	return nil
}

func New(obs *sdiv1alpha1.SDIObserver) *SDIObserver {
	return &SDIObserver{
		obs: obs,
	}
}

func (so *SDIObserver) AdjustNetwork(a *adjuster.Adjuster, ctx context.Context) error {

	a.Logger().V(0).Info("Trying to adjust the network")
	// so.updateStatus(a, sdiv1alpha1.SyncStatusState, "adjust SDI VSystem Route", ctx)
	err := a.AdjustSDIVsystemRoute(a.SdiNamespace, so.obs, ctx)
	if err != nil {
		a.Logger().V(1).Info(err.Error())
		// so.updateStatus(a, sdiv1alpha1.ErrorStatusState, err.Error(), ctx)
		return err
	}

	err = a.AdjustSLCBRoute(a.SlcbNamespace, so.obs, ctx)
	if err != nil {
		a.Logger().V(1).Info(err.Error())
		// so.updateStatus(a, sdiv1alpha1.ErrorStatusState, err.Error(), ctx)
		return err
	}

	return nil
}

func (so *SDIObserver) SyncedStatus() client.Object {
	so.obs.Status.LastSyncAttempt = time.Now().Format(time.RFC1123)
	so.obs.Status.State = sdiv1alpha1.OkStatusState
	so.obs.Status.Message = "sync done successfully"
	return so.obs
}

func (so *SDIObserver) updateStatus(s *adjuster.Adjuster, state sdiv1alpha1.StatusState, message string, ctx context.Context) {
	so.obs.Status.State = state
	so.obs.Status.Message = message
	s.UpdateStatus(so.obs, ctx)
}
