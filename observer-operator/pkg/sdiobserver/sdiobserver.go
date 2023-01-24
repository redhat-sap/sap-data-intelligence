package sdiobserver

import (
	sdiv1alpha1 "github.com/redhat-sap/sap-data-intelligence/observer-operator/api/v1alpha1"
	"github.com/redhat-sap/sap-data-intelligence/observer-operator/pkg/adjuster"
	"k8s.io/apimachinery/pkg/runtime"
	"time"
)

type SDIObserver struct {
	obs *sdiv1alpha1.SDIObserver
}

func (so *SDIObserver) AdjustNodes(s *adjuster.Adjuster) error {
	//TODO implement me
	return nil
}

func (so *SDIObserver) AdjustStorage(s *adjuster.Adjuster) error {
	//TODO implement me
	return nil
}

func (so *SDIObserver) AdjustSDIConfig(s *adjuster.Adjuster) error {
	//TODO implement me
	return nil
}

func (so *SDIObserver) AdjustedStatus() runtime.Object {
	//TODO implement me
	return nil
}

func New(obs *sdiv1alpha1.SDIObserver) *SDIObserver {
	return &SDIObserver{
		obs: obs,
	}
}

func (so *SDIObserver) AdjustNetwork(a *adjuster.Adjuster) error {

	a.Logger().V(0).Info("Trying to adjust the network")
	so.updateStatus(a, sdiv1alpha1.SyncStatusState, "adjusting network")
	err := a.AdjustSDIRoute(so.obs)
	if err != nil {
		a.Logger().V(1).Info(err.Error())
		so.updateStatus(a, sdiv1alpha1.ErrorStatusState, err.Error())
		return err
	}

	so.updateStatus(a, sdiv1alpha1.SyncStatusState, "adjusting network")
	err = a.AdjustSLCBRoute(so.obs)
	if err != nil {
		a.Logger().V(1).Info(err.Error())
		so.updateStatus(a, sdiv1alpha1.ErrorStatusState, err.Error())
		return err
	}

	return nil
}

func (so *SDIObserver) SyncedStatus() runtime.Object {
	so.obs.Status.LastSyncAttempt = time.Now().Format(time.RFC1123)
	so.obs.Status.State = sdiv1alpha1.OkStatusState
	so.obs.Status.Message = "sync done successfully"
	return so.obs
}

func (so *SDIObserver) updateStatus(s *adjuster.Adjuster, state sdiv1alpha1.StatusState, message string) {
	so.obs.Status.State = state
	so.obs.Status.Message = message
	s.UpdateStatus(so.obs)
}
