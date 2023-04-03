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
)

var fluentdDockerVolumeName = "varlibdockercontainers"

func (a *Adjuster) adjustSDIDataHub(ns string, obs *sdiv1alpha1.SDIObserver, ctx context.Context) error {
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

func (a *Adjuster) AdjustSDIDiagnosticsFluentdDaemonsetContainerPrivilege(ns string, obs *sdiv1alpha1.SDIObserver, ctx context.Context) error {
	diagnosticFluentdName := "diagnostics-fluentd"
	ds := &appsv1.DaemonSet{
		ObjectMeta: metav1.ObjectMeta{
			Name:      diagnosticFluentdName,
			Namespace: ns,
		},
	}

	err := a.Client.Get(ctx, client.ObjectKey{Name: diagnosticFluentdName, Namespace: ns}, ds)

	if err != nil {
		return err
	}

	for _, c := range ds.Spec.Template.Spec.Containers {
		if c.Name == diagnosticFluentdName {
			if c.Name == diagnosticFluentdName {
				if c.SecurityContext.Privileged == nil {
					c.SecurityContext.Privileged = pointer.Bool(true)
				} else {
					if *c.SecurityContext.Privileged == true {
						a.logger.Info(fmt.Sprintf("Container of daemonset/%s is already privileged", diagnosticFluentdName))
						return nil
					} else {
						c.SecurityContext.Privileged = pointer.Bool(true)
					}
				}
			}
		}
	}

	a.logger.Info(fmt.Sprintf("Patching daemonset/%s", diagnosticFluentdName))
	err = a.Client.Update(ctx, ds)
	if err != nil {
		return err
	}

	return nil

}

func (a *Adjuster) AdjustSDIVSystemVrepStatefulSets(ns string, obs *sdiv1alpha1.SDIObserver, ctx context.Context) error {

	stsName := "vsystem-vrep"
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
		// Prune the old revision of Pod in case something wrong happened to volume patch
		err = a.pruneStateFullSetOldRevision(ns, obs, ctx)
		if err != nil {
			return err
		}
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

	err = a.adjustSDIDataHub(ns, obs, ctx)
	if err != nil {
		return err
	}

	err = a.pruneStateFullSetOldRevision(ns, obs, ctx)
	if err != nil {
		return err
	}
	return nil
}

func (a *Adjuster) pruneStateFullSetOldRevision(ns string, obs *sdiv1alpha1.SDIObserver, ctx context.Context) error {

	stsName := "vsystem-vrep"
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
		client.MatchingLabelsSelector{
			Selector: updateRevisionSelector,
		},
	)
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
		if pod.Labels["controller-revision-hash"] != ss.Status.CurrentRevision {
			err := a.Client.Delete(ctx, &pod, client.GracePeriodSeconds(5))
			if err != nil {
				return err
			}
		}
	}

	return nil

}

func (a *Adjuster) AdjustNamespacesNodeSelectorAnnotation(obs *sdiv1alpha1.SDIObserver, ctx context.Context) error {
	for _, n := range []string{a.Namespace, obs.Spec.SDINamespace, obs.Spec.SLCBNamespace, "datahub-system"} {
		err := a.adjustNamespaceAnnotation(n, obs.Spec.SDINodeLabel, ctx)
		if err != nil {
			return err
		}
	}
	return nil
}

func (a *Adjuster) adjustNamespaceAnnotation(ns, s string, ctx context.Context) error {
	annotationKey := "openshift.io/node-selector"
	annotationValue := s

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
		a.logger.Info(fmt.Sprintf("Annotation '%s' created for namespace '%s'\n", annotationKey, ns))
	}
	return nil
}
