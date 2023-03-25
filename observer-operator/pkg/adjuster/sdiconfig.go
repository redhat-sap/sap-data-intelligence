package adjuster

import (
	"context"
	"fmt"
	sdiv1alpha1 "github.com/redhat-sap/sap-data-intelligence/observer-operator/api/v1alpha1"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/labels"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/utils/pointer"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"strings"
)

var fluentdDockerVolumeName = "varlibdockercontainers"

func (a *Adjuster) AdjustSDIConfig(ns string, obs *sdiv1alpha1.SDIObserver, ctx context.Context) error {

	return nil

}
func (a *Adjuster) AdjustSDIDataHub(ns string, obs *sdiv1alpha1.SDIObserver, ctx context.Context) error {
	obj := &unstructured.Unstructured{}
	obj.SetName("default")
	obj.SetNamespace(ns)
	gvr := schema.GroupVersionKind{
		Group:   "installers.datahub.sap.com",
		Version: "v1alpha1",
		Kind:    "DataHub",
	}
	obj.SetGroupVersionKind(gvr)

	err := a.Client.Get(context.Background(), client.ObjectKeyFromObject(obj), obj)
	if err != nil {
		panic(err)
	}

	spec := obj.Object["spec"].(map[string]interface{})
	vsystem := spec["vsystem"].(map[string]interface{})
	vRep := vsystem["vRep"].(map[string]interface{})

	if len(vRep) == 0 {
		a.logger.Info("patch DataHub vRep by setting exportsMask to true")
		vRep["exportsMask"] = true
		err = a.Client.Update(ctx, obj)
		if err != nil {
			return err
		}
	} else {
		a.logger.Info("DataHub vRep is already patched")
	}
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

	var newVolumes []corev1.Volume
	for _, v := range ds.Spec.Template.Spec.Volumes {
		if strings.Contains(v.HostPath.Path, "/var/lib/docker") {
			for _, c := range ds.Spec.Template.Spec.Containers {
				var newVolumeMounts []corev1.VolumeMount
				for _, vm := range c.VolumeMounts {
					if vm.Name != v.Name {
						newVolumeMounts = append(newVolumeMounts, vm)
					}
				}
				c.VolumeMounts = newVolumeMounts
			}
			for _, c := range ds.Spec.Template.Spec.InitContainers {
				var newVolumeMounts []corev1.VolumeMount
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

	stsName := "vsystem-verp"
	ss := &appsv1.StatefulSet{
		ObjectMeta: metav1.ObjectMeta{
			Name:      stsName,
			Namespace: ns,
		},
	}

	err := a.Client.Get(ctx, client.ObjectKey{Name: stsName, Namespace: ns}, ss)
	if err != nil {
		return err
	}

	volumeName := "exports-mask"
	volumePatched := false
	volumeMountPatched := false

	for _, v := range ss.Spec.Template.Spec.Volumes {
		if v.Name == volumeName {
			a.logger.Info("volume is already patched for statefulset " + stsName)
			volumePatched = true
			break
		}
	}

	for _, c := range ss.Spec.Template.Spec.Containers {
		if c.Name == stsName {
			for _, vm := range c.VolumeMounts {
				if vm.Name == volumeName {
					a.logger.Info("volumeMount is already patched for statefulset " + stsName)
					volumeMountPatched = true
					break
				}
			}
		}
	}

	if volumePatched && volumeMountPatched {
		return nil
	}

	emptyDirVolume := corev1.Volume{
		Name: volumeName,
		VolumeSource: corev1.VolumeSource{
			EmptyDir: &corev1.EmptyDirVolumeSource{},
		},
	}

	ss.Spec.Template.Spec.Volumes = append(ss.Spec.Template.Spec.Volumes, emptyDirVolume)

	for _, c := range ss.Spec.Template.Spec.Containers {
		if c.Name == stsName {
			emptyDirVolumeMount := corev1.VolumeMount{
				Name:      volumeName,
				MountPath: "/exports",
			}

			c.VolumeMounts = append(c.VolumeMounts, emptyDirVolumeMount)
		}
	}

	err = a.pruneStateFullSetOldRevision(ns, obs, ctx)
	if err != nil {
		return err
	}
	return nil
}

func (a *Adjuster) pruneStateFullSetOldRevision(ns string, obs *sdiv1alpha1.SDIObserver, ctx context.Context) error {

	stsName := "vsystem-verp"
	namespace := ns

	ss := &appsv1.StatefulSet{
		ObjectMeta: metav1.ObjectMeta{
			Name:      stsName,
			Namespace: ns,
		},
	}

	err := a.Client.Get(ctx, client.ObjectKey{Name: stsName, Namespace: ns}, ss)
	if err != nil {
		return err
	}

	if ss.Status.UpdateRevision == ss.Status.CurrentRevision {
		a.logger.Info(fmt.Sprintf("statefulset %s has the updated revision running already.", stsName))
		return nil
	}

	updateRevisionPodList := &corev1.PodList{}

	updateRevisionSelector := labels.SelectorFromSet(labels.Set(map[string]string{
		"controller-revision-hash": ss.Status.UpdateRevision,
	}))

	err = a.Client.List(ctx, updateRevisionPodList,
		client.InNamespace(namespace),
		client.MatchingLabelsSelector{updateRevisionSelector},
		client.MatchingLabels(ss.Spec.Selector.MatchLabels))
	if err != nil {
		return err
	}

	if len(updateRevisionPodList.Items) > 0 {
		a.logger.Info(fmt.Sprintf("The pod of the updated revision of statefulset %s exists already.", stsName))
		return nil
	}

	podList := &corev1.PodList{}
	err = a.Client.List(ctx, updateRevisionPodList,
		client.InNamespace(namespace),
		client.MatchingLabels(ss.Spec.Selector.MatchLabels))
	if err != nil {
		return err
	}

	for _, pod := range podList.Items {
		if pod.Labels["controller-revision-hash"] != ss.Status.UpdateRevision {
			err := a.Client.Delete(ctx, &pod, client.GracePeriodSeconds(5))
			if err != nil {
				return err
			}
		}
	}

	return nil

}

func (a *Adjuster) AdjustSDIConfigMaps(ns string, obs *sdiv1alpha1.SDIObserver, ctx context.Context) error {

	return nil

}

func (a *Adjuster) AdjustSDIRoles(ns string, obs *sdiv1alpha1.SDIObserver, ctx context.Context) error {

	return nil

}

func (a *Adjuster) AdjustSDINamespace(ns string, obs *sdiv1alpha1.SDIObserver, ctx context.Context) error {
	for _, n := range []string{ns, a.SdiNamespace, a.SlcbNamespace, "datahub-system"} {
		err := a.adjustNamespaceAnnotation(n, ctx)
		if err != nil {
			return err
		}
	}
	return nil
}

func (a *Adjuster) adjustNamespaceAnnotation(ns string, ctx context.Context) error {
	annotationKey := "openshift.io/node-selector"
	annotationValue := "node-role.kubernetes.io/sdi="

	namespace := &corev1.Namespace{}
	err := a.Client.Get(ctx, types.NamespacedName{Name: ns}, namespace)
	if err != nil {
		return err
	}
	annotations := namespace.GetAnnotations()
	if annotations == nil {
		annotations = map[string]string{}
	}
	_, ok := annotations[annotationKey]
	if ok {
		a.logger.Info(fmt.Sprintf("Annotation '%s' exists for namespace '%s'\n", annotationKey, ns))
		if annotations[annotationKey] == annotationValue {
			a.logger.Info(fmt.Sprintf("Annotation '%s' is unchanged for namespace '%s'\n", annotationKey, ns))
			return nil
		}

		annotations[annotationKey] = annotationValue
		namespace.SetAnnotations(annotations)
		err = a.Client.Update(context.Background(), namespace)
		if err != nil {
			return err
		}
		a.logger.Info(fmt.Sprintf("Annotation '%s' updated for namespace '%s'\n", annotationKey, ns))
	} else {
		a.logger.Info(fmt.Sprintf("Annotation '%s' does not exist for namespace '%s'\n", annotationKey, ns))
		annotations[annotationKey] = annotationValue
		namespace.SetAnnotations(annotations)
		err = a.Client.Update(context.Background(), namespace)
		if err != nil {
			return err
		}
		a.logger.Info(fmt.Sprintf("Annotation '%s' created for namespace '%s'\n", annotationKey, namespace))
	}
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
