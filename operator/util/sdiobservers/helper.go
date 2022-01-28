package sdiobservers

import (
	"context"
	"fmt"

	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/util/retry"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	"github.com/redhat-sap/sap-data-intelligence/operator/api/v1alpha1"
	sdiv1alpha1 "github.com/redhat-sap/sap-data-intelligence/operator/api/v1alpha1"
)

func IsBackup(obs *sdiv1alpha1.SDIObserver) bool {
	return IsStatusInCondition(obs, "Backup")
}

func SetBackup(
	ctx context.Context,
	k8sClient client.Client,
	obs *sdiv1alpha1.SDIObserver,
	backup bool,
	activeInstance types.NamespacedName,
) (update bool) {
	logger := log.FromContext(ctx)
	stateDescription := "active"
	if backup {
		stateDescription = "backup"
	}
	if IsBackup(obs) == backup {
		logger.Info(fmt.Sprintf("SetBackupAndUpdate: instance already marked as %s", stateDescription), "instance", client.ObjectKeyFromObject(obs))
		return
	}
	logger.Info(fmt.Sprintf("SetBackup: setting the observer instance as %s", stateDescription), "instance", client.ObjectKeyFromObject(obs))

	backupStatus := metav1.ConditionFalse
	backupReason := v1alpha1.ConditionReasonActive
	readyStatus := metav1.ConditionUnknown
	readyReason := "Reconciling"
	degradedStatus := metav1.ConditionUnknown
	degradedReason := "Reconciling"
	if backup {
		backupStatus = metav1.ConditionTrue
		backupReason = v1alpha1.ConditionReasonAlreadyManaged
		readyStatus = metav1.ConditionUnknown
		readyReason = v1alpha1.ConditionReasonBackup
		degradedStatus = metav1.ConditionUnknown
		degradedReason = v1alpha1.ConditionReasonBackup
	}
	meta.SetStatusCondition(&obs.Status.Conditions, metav1.Condition{
		Type:               "Backup",
		Status:             backupStatus,
		Reason:             backupReason,
		ObservedGeneration: obs.Generation,
		Message:            fmt.Sprintf("The active SDIObserver instance is (namespace/name): %v", activeInstance),
	})
	meta.SetStatusCondition(&obs.Status.Conditions, metav1.Condition{
		Type:               "Ready",
		Status:             readyStatus,
		Reason:             readyReason,
		ObservedGeneration: obs.Generation,
	})
	meta.SetStatusCondition(&obs.Status.Conditions, metav1.Condition{
		Type:               "Degraded",
		Status:             degradedStatus,
		Reason:             degradedReason,
		ObservedGeneration: obs.Generation,
	})
	return true
}

func SetBackupAndUpdate(
	ctx context.Context,
	k8sClient client.Client,
	obs *sdiv1alpha1.SDIObserver,
	backup bool,
	activeInstance types.NamespacedName,
) error {
	logger := log.FromContext(ctx)
	firstTry := true
	if IsBackup(obs) == backup {
		stateDescription := "active"
		if backup {
			stateDescription = "backup"
		}
		logger.Info(fmt.Sprintf("SetBackupAndUpdate: instance already marked as %s", stateDescription), "instance", client.ObjectKeyFromObject(obs))
		return nil
	}
	return retry.RetryOnConflict(retry.DefaultRetry, func() error {
		if !firstTry {
			if err := k8sClient.Get(ctx, client.ObjectKeyFromObject(obs), obs); err != nil {
				return err
			}
		}
		firstTry = false

		if !SetBackup(ctx, k8sClient, obs, backup, activeInstance) {
			return nil
		}
		return k8sClient.Status().Update(ctx, obs)
	})
}

func IsRouteInCondition(routeStatus sdiv1alpha1.SDIObserverRouteStatus, condType string) bool {
	c := meta.FindStatusCondition(routeStatus.Conditions, condType)
	if c == nil {
		return false
	}
	return c.Status == metav1.ConditionTrue
}

func IsRouteConditionKnown(routeStatus sdiv1alpha1.SDIObserverRouteStatus, condType string) bool {
	c := meta.FindStatusCondition(routeStatus.Conditions, condType)
	if c == nil {
		return false
	}
	return c.Status == metav1.ConditionUnknown
}

func IsStatusInCondition(obs *sdiv1alpha1.SDIObserver, condType string) bool {
	c := meta.FindStatusCondition(obs.Status.Conditions, condType)
	if c == nil {
		return false
	}
	return c.Status == metav1.ConditionTrue
}
