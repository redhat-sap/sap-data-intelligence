package adjuster

import (
	"context"
	"fmt"
	routev1 "github.com/openshift/api/route/v1"
	sdiv1alpha1 "github.com/redhat-sap/sap-data-intelligence/observer-operator/api/v1alpha1"
	"github.com/redhat-sap/sap-data-intelligence/observer-operator/assets"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	utilerrors "k8s.io/apimachinery/pkg/util/errors"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"strings"
	"time"
)

const (
	vsystemCaBundleSecretName = "ca-bundle.pem"
	vsystemCaBundleSecretKey  = "ca-bundle.pem"
)

func (a *Adjuster) AdjustSDIVsystemRoute(ns string, obs *sdiv1alpha1.SDIObserver, ctx context.Context) error {

	name := "vsystem"

	route := &routev1.Route{
		ObjectMeta: metav1.ObjectMeta{
			Name:      name,
			Namespace: ns,
		},
	}

	switch obs.Spec.SDIVSystemRoute.ManagementState {
	case sdiv1alpha1.RouteManagementStateManaged:
		create := false
		err := a.Client.Get(ctx, client.ObjectKey{Name: name, Namespace: ns}, route)

		if err != nil && errors.IsNotFound(err) {
			create = true
			route = assets.GetRouteFromFile("manifests/route-management/route-vsystem.yaml")
			route.Namespace = ns
			route.Name = name

			svc := &corev1.Service{
				ObjectMeta: metav1.ObjectMeta{
					Name:      name,
					Namespace: ns,
				},
			}

			err = a.Client.Get(ctx, types.NamespacedName{
				Namespace: ns,
				Name:      name,
			}, svc)

			if err != nil && !errors.IsNotFound(err) {
				return err
			}

			caBundleSecret := &corev1.Secret{}
			err = a.Client.Get(ctx, types.NamespacedName{
				Namespace: ns,
				Name:      vsystemCaBundleSecretName,
			}, caBundleSecret)
			if err != nil {
				return err
			}

			caBundle, err := getCertFromCaBundleSecret(caBundleSecret)
			if err != nil {
				return err
			}
			route.Spec.TLS.DestinationCACertificate = caBundle
		} else if err != nil {
			a.logger.Error(err, "Error getting existing sdi vsystem route.")
			meta.SetStatusCondition(&obs.Status.VSystemRouteStatus.Conditions, metav1.Condition{
				Type:               "OperatorDegraded",
				Status:             metav1.ConditionTrue,
				Reason:             sdiv1alpha1.ReasonRouteNotAvailable,
				LastTransitionTime: metav1.NewTime(time.Now()),
				Message:            fmt.Sprintf("unable to get operand route: %s", err.Error()),
			})
			return utilerrors.NewAggregate([]error{err, a.Client.Status().Update(ctx, obs)})
		} else {
			caBundleSecret := &corev1.Secret{}
			err = a.Client.Get(ctx, types.NamespacedName{
				Namespace: ns,
				Name:      vsystemCaBundleSecretName,
			}, caBundleSecret)
			if err != nil {
				return err
			}

			caBundle, err := getCertFromCaBundleSecret(caBundleSecret)
			if err != nil {
				return err
			}
			if route.Spec.TLS.DestinationCACertificate == caBundle {
				a.logger.Info(fmt.Sprintf("Route %s destination CA certificate is unchanged", name))
				meta.SetStatusCondition(&obs.Status.VSystemRouteStatus.Conditions, metav1.Condition{
					Type:               "OperatorDegraded",
					Status:             metav1.ConditionFalse,
					Reason:             sdiv1alpha1.ReasonSucceeded,
					LastTransitionTime: metav1.NewTime(time.Now()),
					Message:            "Route destination CA certificate is unchanged",
				})
				return nil
			} else {
				route.Spec.TLS.DestinationCACertificate = caBundle
			}
		}
		if create {
			err = a.Client.Create(ctx, route)
		} else {
			err = a.Client.Update(ctx, route)
		}

		if err != nil {
			meta.SetStatusCondition(&obs.Status.VSystemRouteStatus.Conditions, metav1.Condition{
				Type:               "OperatorDegraded",
				Status:             metav1.ConditionTrue,
				Reason:             sdiv1alpha1.ReasonOperandRouteFailed,
				LastTransitionTime: metav1.NewTime(time.Now()),
				Message:            fmt.Sprintf("unable to update operand route: %s", err.Error()),
			})
			return utilerrors.NewAggregate([]error{err, a.Client.Status().Update(ctx, obs)})
		}

		meta.SetStatusCondition(&obs.Status.VSystemRouteStatus.Conditions, metav1.Condition{
			Type:               "OperatorDegraded",
			Status:             metav1.ConditionFalse,
			Reason:             sdiv1alpha1.ReasonSucceeded,
			LastTransitionTime: metav1.NewTime(time.Now()),
			Message:            "operator successfully reconciling",
		})

		//condition, err := conditions.InClusterFactory{Client: a.Client}.
		//	NewCondition(apiv2.ConditionType(apiv2.Upgradeable))
		//if err != nil {
		//	return err
		//}
		//err = condition.Set(ctx, metav1.ConditionTrue,
		//	conditions.WithReason("OperatorUpgradeable"),
		//	conditions.WithMessage("The operator is currently upgradeable"))
		//if err != nil {
		//	return err
		//}

		return utilerrors.NewAggregate([]error{err, a.Client.Status().Update(ctx, obs)})
	case sdiv1alpha1.RouteManagementStateUnmanaged:
		meta.SetStatusCondition(&obs.Status.VSystemRouteStatus.Conditions, metav1.Condition{
			Type:               "OperatorDegraded",
			Status:             metav1.ConditionFalse,
			Reason:             sdiv1alpha1.ReasonSucceeded,
			LastTransitionTime: metav1.NewTime(time.Now()),
			Message:            "operator successfully reconciling",
		})
		return a.Client.Status().Update(ctx, obs)
	case sdiv1alpha1.RouteManagementStateRemoved:
		err := a.Client.Get(ctx, client.ObjectKey{Name: name, Namespace: ns}, route)

		if err != nil && errors.IsNotFound(err) {
			meta.SetStatusCondition(&obs.Status.VSystemRouteStatus.Conditions, metav1.Condition{
				Type:               "OperatorDegraded",
				Status:             metav1.ConditionFalse,
				Reason:             sdiv1alpha1.ReasonRouteNotAvailable,
				LastTransitionTime: metav1.NewTime(time.Now()),
				Message:            fmt.Sprintf("operand route does not exist: %s", err.Error()),
			})

			return a.Client.Status().Update(ctx, obs)
		} else if err != nil {
			a.logger.Error(err, "Error getting existing sdi vsystem route.")
			meta.SetStatusCondition(&obs.Status.VSystemRouteStatus.Conditions, metav1.Condition{
				Type:               "OperatorDegraded",
				Status:             metav1.ConditionTrue,
				Reason:             sdiv1alpha1.ReasonRouteNotAvailable,
				LastTransitionTime: metav1.NewTime(time.Now()),
				Message:            fmt.Sprintf("unable to get operand route: %s", err.Error()),
			})
			return utilerrors.NewAggregate([]error{err, a.Client.Status().Update(ctx, obs)})
		}

		err = a.Client.Delete(ctx, route)

		if err != nil {
			meta.SetStatusCondition(&obs.Status.VSystemRouteStatus.Conditions, metav1.Condition{
				Type:               "OperatorDegraded",
				Status:             metav1.ConditionTrue,
				Reason:             sdiv1alpha1.ReasonOperandRouteFailed,
				LastTransitionTime: metav1.NewTime(time.Now()),
				Message:            fmt.Sprintf("unable to delete operand route: %s", err.Error()),
			})
			return utilerrors.NewAggregate([]error{err, a.Client.Status().Update(ctx, obs)})
		}

		meta.SetStatusCondition(&obs.Status.VSystemRouteStatus.Conditions, metav1.Condition{
			Type:               "OperatorDegraded",
			Status:             metav1.ConditionFalse,
			Reason:             sdiv1alpha1.ReasonSucceeded,
			LastTransitionTime: metav1.NewTime(time.Now()),
			Message:            "operator successfully reconciling",
		})

		//condition, err := conditions.InClusterFactory{Client: a.Client}.
		//	NewCondition(apiv2.ConditionType(apiv2.Upgradeable))
		//if err != nil {
		//	return err
		//}
		//err = condition.Set(ctx, metav1.ConditionTrue,
		//	conditions.WithReason("OperatorUpgradeable"),
		//	conditions.WithMessage("The operator is currently upgradeable"))
		//if err != nil {
		//	return err
		//}
		return utilerrors.NewAggregate([]error{err, a.Client.Status().Update(ctx, obs)})
	default:
		meta.SetStatusCondition(&obs.Status.VSystemRouteStatus.Conditions, metav1.Condition{
			Type:               "OperatorDegraded",
			Status:             metav1.ConditionTrue,
			Reason:             sdiv1alpha1.ReasonRouteManagementStateUnsupported,
			LastTransitionTime: metav1.NewTime(time.Now()),
			Message:            fmt.Sprintf("SDI Vsystem Route Management State is unsupported: %s", obs.Spec.SDIVSystemRoute.ManagementState),
		})
		return utilerrors.NewAggregate([]error{fmt.Errorf("unsupported route management state: %s", obs.Spec.SDIVSystemRoute.ManagementState), a.Client.Status().Update(ctx, obs)})
	}
}

func (a *Adjuster) AdjustSLCBRoute(ns string, obs *sdiv1alpha1.SDIObserver, ctx context.Context) error {

	name := "sap-slcbridge"
	route := &routev1.Route{
		ObjectMeta: metav1.ObjectMeta{
			Name:      name,
			Namespace: ns,
		},
	}

	switch obs.Spec.SLCBRoute.ManagementState {
	case sdiv1alpha1.RouteManagementStateManaged:
		err := a.Client.Get(ctx, client.ObjectKey{Name: name, Namespace: ns}, route)
		create := false
		if err != nil && errors.IsNotFound(err) {
			create = true
			route = assets.GetRouteFromFile("manifests/route-management/route-sap-slcbridge.yaml")
			route.Namespace = ns
			route.Name = name
		} else if err != nil {
			a.logger.Error(err, "Error getting existing sap-slcbridge route.")
			meta.SetStatusCondition(&obs.Status.SLCBRouteStatus.Conditions, metav1.Condition{
				Type:               "OperatorDegraded",
				Status:             metav1.ConditionTrue,
				Reason:             sdiv1alpha1.ReasonRouteNotAvailable,
				LastTransitionTime: metav1.NewTime(time.Now()),
				Message:            fmt.Sprintf("unable to get operand route: %s", err.Error()),
			})
			return utilerrors.NewAggregate([]error{err, a.Client.Status().Update(ctx, obs)})
		} else {
			if route.Spec.To.Name == "slcbridgebase-service" {
				a.logger.Info(fmt.Sprintf("Route configuration %s is unchanged", name))
				meta.SetStatusCondition(&obs.Status.SLCBRouteStatus.Conditions, metav1.Condition{
					Type:               "OperatorDegraded",
					Status:             metav1.ConditionFalse,
					Reason:             sdiv1alpha1.ReasonSucceeded,
					LastTransitionTime: metav1.NewTime(time.Now()),
					Message:            fmt.Sprintf("Route configuration %s is unchanged", name),
				})
				return nil
			} else {
				return fmt.Errorf(
					"Route %s configuration of  is changed. Current route is pointing to service %s",
					name,
					route.Spec.To.Name,
				)
			}
		}

		if create {
			err = a.Client.Create(ctx, route)
		} else {
			err = a.Client.Update(ctx, route)
		}

		meta.SetStatusCondition(&obs.Status.SLCBRouteStatus.Conditions, metav1.Condition{
			Type:               "OperatorDegraded",
			Status:             metav1.ConditionFalse,
			Reason:             sdiv1alpha1.ReasonSucceeded,
			LastTransitionTime: metav1.NewTime(time.Now()),
			Message:            "operator successfully reconciling",
		})

		//condition, err := conditions.InClusterFactory{Client: a.Client}.
		//	NewCondition(apiv2.ConditionType(apiv2.Upgradeable))
		//
		//if err != nil {
		//	return err
		//}
		//
		//err = condition.Set(ctx, metav1.ConditionTrue,
		//	conditions.WithReason("OperatorUpgradeable"),
		//	conditions.WithMessage("The operator is currently upgradeable"))
		//if err != nil {
		//	return err
		//}

		return utilerrors.NewAggregate([]error{err, a.Client.Status().Update(ctx, obs)})
	case sdiv1alpha1.RouteManagementStateUnmanaged:
		meta.SetStatusCondition(&obs.Status.SLCBRouteStatus.Conditions, metav1.Condition{
			Type:               "OperatorDegraded",
			Status:             metav1.ConditionFalse,
			Reason:             sdiv1alpha1.ReasonSucceeded,
			LastTransitionTime: metav1.NewTime(time.Now()),
			Message:            "operator successfully reconciling",
		})
		return a.Client.Status().Update(ctx, obs)
	case sdiv1alpha1.RouteManagementStateRemoved:
		err := a.Client.Get(ctx, client.ObjectKey{Name: name, Namespace: ns}, route)
		if err != nil && errors.IsNotFound(err) {
			meta.SetStatusCondition(&obs.Status.SLCBRouteStatus.Conditions, metav1.Condition{
				Type:               "OperatorDegraded",
				Status:             metav1.ConditionFalse,
				Reason:             sdiv1alpha1.ReasonRouteNotAvailable,
				LastTransitionTime: metav1.NewTime(time.Now()),
				Message:            fmt.Sprintf("operand route does not exist: %s", err.Error()),
			})

			return a.Client.Status().Update(ctx, obs)
		} else if err != nil {
			a.logger.Error(err, "Error getting existing sap-slcbridge route.")
			meta.SetStatusCondition(&obs.Status.SLCBRouteStatus.Conditions, metav1.Condition{
				Type:               "OperatorDegraded",
				Status:             metav1.ConditionTrue,
				Reason:             sdiv1alpha1.ReasonRouteNotAvailable,
				LastTransitionTime: metav1.NewTime(time.Now()),
				Message:            fmt.Sprintf("unable to get operand route: %s", err.Error()),
			})
			return utilerrors.NewAggregate([]error{err, a.Client.Status().Update(ctx, obs)})
		}
		err = a.Client.Delete(ctx, route)

		if err != nil {
			meta.SetStatusCondition(&obs.Status.SLCBRouteStatus.Conditions, metav1.Condition{
				Type:               "OperatorDegraded",
				Status:             metav1.ConditionTrue,
				Reason:             sdiv1alpha1.ReasonOperandRouteFailed,
				LastTransitionTime: metav1.NewTime(time.Now()),
				Message:            fmt.Sprintf("unable to delete operand route: %s", err.Error()),
			})
			return utilerrors.NewAggregate([]error{err, a.Client.Status().Update(ctx, obs)})
		}

		meta.SetStatusCondition(&obs.Status.SLCBRouteStatus.Conditions, metav1.Condition{
			Type:               "OperatorDegraded",
			Status:             metav1.ConditionFalse,
			Reason:             sdiv1alpha1.ReasonSucceeded,
			LastTransitionTime: metav1.NewTime(time.Now()),
			Message:            "operator successfully reconciling",
		})

		//condition, err := conditions.InClusterFactory{Client: a.Client}.
		//	NewCondition(apiv2.ConditionType(apiv2.Upgradeable))
		//
		//if err != nil {
		//	return err
		//}
		//
		//err = condition.Set(ctx, metav1.ConditionTrue,
		//	conditions.WithReason("OperatorUpgradeable"),
		//	conditions.WithMessage("The operator is currently upgradeable"))
		//if err != nil {
		//	return err
		//}

		return utilerrors.NewAggregate([]error{err, a.Client.Status().Update(ctx, obs)})
	default:
		meta.SetStatusCondition(&obs.Status.SLCBRouteStatus.Conditions, metav1.Condition{
			Type:               "OperatorDegraded",
			Status:             metav1.ConditionTrue,
			Reason:             sdiv1alpha1.ReasonRouteManagementStateUnsupported,
			LastTransitionTime: metav1.NewTime(time.Now()),
			Message:            fmt.Sprintf("SLC Bridge Route Management State is unsupported: %s", obs.Spec.SLCBRoute.ManagementState),
		})
		return utilerrors.NewAggregate([]error{fmt.Errorf("unsupported route management status: %s", obs.Spec.SLCBRoute.ManagementState), a.Client.Status().Update(ctx, obs)})
	}
}

func getCertFromCaBundleSecret(secret *corev1.Secret) (string, error) {
	value, ok := secret.Data[vsystemCaBundleSecretKey]
	if !ok {
		return "", fmt.Errorf("failed to find key \"%s\" in \"%s\" secret", vsystemCaBundleSecretKey, secret.ObjectMeta.Name)
	}
	return strings.TrimSpace(string(value[:])), nil
}
