package adjuster

import (
	"context"
	"fmt"
	routev1 "github.com/openshift/api/route/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

func (a *Adjuster) AdjustRoute(ns, ts, h string) error {

	route := routev1.Route{
		ObjectMeta: metav1.ObjectMeta{
			Name:      ts,
			Namespace: ns,
		},
	}

	_ = a.client.Get(context.Background(), client.ObjectKey{Name: ts, Namespace: ns}, &route)

	labels := map[string]string{}
	annotations := map[string]string{}

	updateRoute := func() error {
		adjustOwnerReference(&route.ObjectMeta, a.ownerReference)
		adjustLabels(&route.ObjectMeta, labels)
		adjustAnnotations(&route.ObjectMeta, annotations)
		route.Spec.To.Kind = "Service"
		route.Spec.To.Name = ts
		if len(h) > 0 {
			route.Spec.Host = h
		}
		return nil
	}

	op, err := ctrl.CreateOrUpdate(context.Background(), a.client, &route, updateRoute)
	if err != nil {
		return err
	}

	a.Logger().Info(fmt.Sprintf("route '%s' %s during reconciliation", ts, op))
	return nil
}
