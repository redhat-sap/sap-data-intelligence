package adjuster

import (
	"context"
	"fmt"
	routev1 "github.com/openshift/api/route/v1"
	sdiv1alpha1 "github.com/redhat-sap/sap-data-intelligence/observer-operator/api/v1alpha1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	ctrl "sigs.k8s.io/controller-runtime"
)

func (a *Adjuster) AdjustSDIRoute(obs *sdiv1alpha1.SDIObserver) error {
	err := a.adjustRoutes(obs.Spec.SDIRoute.Namespace,
		obs.Spec.SDIRoute.TargetedService,
		obs.Spec.SDIRoute.Hostname)
	if err != nil {
		return err
	}

	return nil

}

func (a *Adjuster) AdjustSLCBRoute(obs *sdiv1alpha1.SDIObserver) error {
	err := a.adjustRoutes(obs.Spec.SDIRoute.Namespace,
		obs.Spec.SDIRoute.TargetedService,
		obs.Spec.SDIRoute.Hostname)
	if err != nil {
		return err
	}

	return nil

}

func (a *Adjuster) adjustRoutes(namespace, targetedSerivce, hostname string) error {

	route := routev1.Route{
		ObjectMeta: metav1.ObjectMeta{
			Name:      targetedSerivce,
			Namespace: namespace,
		},
	}

	labels := map[string]string{}
	annotations := map[string]string{}

	updateRoute := func() error {
		adjustOwnerReference(&route.ObjectMeta, a.ownerReference)
		adjustLabels(&route.ObjectMeta, labels)
		adjustAnnotations(&route.ObjectMeta, annotations)
		route.Spec.To.Kind = "Service"
		route.Spec.To.Name = targetedSerivce
		if len(hostname) > 0 {
			route.Spec.Host = hostname
		}
		return nil
	}

	op, err := ctrl.CreateOrUpdate(context.Background(), a.client, &route, updateRoute)
	if err != nil {
		return err
	}

	a.Logger().Info(fmt.Sprintf("route '%s' %s during reconciliation", targetedSerivce, op))
	return nil
}
