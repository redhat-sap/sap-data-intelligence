package adjuster

import (
	"context"
	"fmt"
	sdiv1alpha1 "github.com/redhat-sap/sap-data-intelligence/observer-operator/api/v1alpha1"
	appsv1 "k8s.io/api/apps/v1"
	v1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/utils/pointer"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"strings"
)

var fluentdDockerVolumeName = "varlibdockercontainers"

func (a *Adjuster) AdjustSDIConfig(ns string, obs *sdiv1alpha1.SDIObserver, ctx context.Context) error {

	return nil

}

func (a *Adjuster) AdjustSDIDaemonsets(ns string, obs *sdiv1alpha1.SDIObserver, ctx context.Context) error {

	//dsList := &appsv1.DaemonSetList{}
	//
	//err := a.Client.List(ctx, dsList, &client.ListOptions{Namespace: ns})
	//if err != nil {
	//	a.logger.Error(err, "failed to list DaemonSets")
	//	meta.SetStatusCondition(&obs.Status.Conditions, metav1.Condition{
	//		Type:               "OperatorDegraded",
	//		Status:             metav1.ConditionTrue,
	//		Reason:             sdiv1alpha1.ReasonRouteNotAvailable,
	//		LastTransitionTime: metav1.NewTime(time.Now()),
	//		Message:            fmt.Sprintf("unable to get Daemonsets: %s", err.Error()),
	//	})
	//	return utilerrors.NewAggregate([]error{err, a.Client.Status().Update(ctx, obs)})
	//}
	//
	//for _, ds := range dsList.Items {
	//
	//}

	diagnosticFluentdName := "diagnostics-fluentd"
	ds := &appsv1.DaemonSet{
		ObjectMeta: metav1.ObjectMeta{
			Name:      diagnosticFluentdName,
			Namespace: ns,
		},
	}

	err := a.Client.Get(ctx, client.ObjectKey{Name: diagnosticFluentdName, Namespace: ns}, ds)

	for _, c := range ds.Spec.Template.Spec.Containers {
		if c.Name == diagnosticFluentdName && *(c.SecurityContext.Privileged) != true {
			c.SecurityContext.Privileged = pointer.Bool(true)
		}
	}

	var newVolumes []v1.Volume
	for _, v := range ds.Spec.Template.Spec.Volumes {
		if strings.Contains(v.HostPath.Path, "/var/lib/docker") {
			for _, c := range ds.Spec.Template.Spec.Containers {
				var newVolumeMounts []v1.VolumeMount
				for _, vm := range c.VolumeMounts {
					if vm.Name != v.Name {
						newVolumeMounts = append(newVolumeMounts, vm)
					}
				}
				c.VolumeMounts = newVolumeMounts
			}
			for _, c := range ds.Spec.Template.Spec.InitContainers {
				var newVolumeMounts []v1.VolumeMount
				for _, vm := range c.VolumeMounts {
					if vm.Name != v.Name {
						newVolumeMounts = append(newVolumeMounts, vm)
					}
				}
				c.VolumeMounts = newVolumeMounts
			}

		} else {
			newVolumes = append(newVolumes, v)
		}
	}
	ds.Spec.Template.Spec.Volumes = newVolumes

	a.logger.Info(fmt.Sprintf("Patching daemonset/%s", diagnosticFluentdName))
	err = a.Client.Update(ctx, ds)
	if err != nil {
		return err
	}

	return nil

}

func (a *Adjuster) AdjustSDIStatefulSets(ns string, obs *sdiv1alpha1.SDIObserver, ctx context.Context) error {

	return nil

}

func (a *Adjuster) AdjustSDIConfigMaps(ns string, obs *sdiv1alpha1.SDIObserver, ctx context.Context) error {

	return nil

}

func (a *Adjuster) AdjustSDIRoles(ns string, obs *sdiv1alpha1.SDIObserver, ctx context.Context) error {

	return nil

}

func (a *Adjuster) AdjustSDINamespace(ns string, obs *sdiv1alpha1.SDIObserver, ctx context.Context) error {

	return nil

}

func removeDSDockerVolume(ds *appsv1.DaemonSet) bool {
	for _, c := range ds.Spec.Template.Spec.Containers {
		for _, vm := range c.VolumeMounts {
			if strings.Contains(vm.Name, fluentdDockerVolumeName) {
				return true
			}
		}
	}

	for _, c := range ds.Spec.Template.Spec.InitContainers {
		for _, vm := range c.VolumeMounts {
			if strings.Contains(vm.Name, fluentdDockerVolumeName) {
				return true
			}
		}
	}

	for _, v := range ds.Spec.Template.Spec.Volumes {
		if strings.Contains(v.Name, fluentdDockerVolumeName) || strings.Contains(v.HostPath.Path, "/var/lib/docker") {
			return true
		}
	}
	return false

}
