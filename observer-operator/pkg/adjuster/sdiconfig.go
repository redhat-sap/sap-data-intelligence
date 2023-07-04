package adjuster

import (
	"context"
	"fmt"
	sdiv1alpha1 "github.com/redhat-sap/sap-data-intelligence/observer-operator/api/v1alpha1"
	"github.com/redhat-sap/sap-data-intelligence/observer-operator/assets"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	rbacv1 "k8s.io/api/rbac/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/labels"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/utils/pointer"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"time"
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
		meta.SetStatusCondition(&obs.Status.SDINodeConfigStatus.Conditions, metav1.Condition{
			Type:               "OperatorDegraded",
			Status:             metav1.ConditionTrue,
			Reason:             sdiv1alpha1.ReasonResourceNotAvailable,
			LastTransitionTime: metav1.NewTime(time.Now()),
			Message:            fmt.Sprintf("unable to get operand SDI DataHub: %s", err.Error()),
		})
		return err
	}

	spec := obj.Object["spec"].(map[string]interface{})
	vsystem := spec["vsystem"].(map[string]interface{})
	vRep := vsystem["vRep"].(map[string]interface{})

	if len(vRep) == 0 {
		a.logger.Info("patch DataHub vRep by setting exportsMask to true")
		vRep["exportsMask"] = true
		err = a.Client.Update(ctx, obj)
		if err != nil {
			meta.SetStatusCondition(&obs.Status.SDIConfigStatus.Conditions, metav1.Condition{
				Type:               "OperatorDegraded",
				Status:             metav1.ConditionTrue,
				Reason:             sdiv1alpha1.ReasonOperandResourceFailed,
				LastTransitionTime: metav1.NewTime(time.Now()),
				Message:            fmt.Sprintf("unable to update operand DataHub vRep: %s", err.Error()),
			})
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
		meta.SetStatusCondition(&obs.Status.SDINodeConfigStatus.Conditions, metav1.Condition{
			Type:               "OperatorDegraded",
			Status:             metav1.ConditionTrue,
			Reason:             sdiv1alpha1.ReasonResourceNotAvailable,
			LastTransitionTime: metav1.NewTime(time.Now()),
			Message:            fmt.Sprintf("unable to get operand daemonset: %s", err.Error()),
		})
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
		meta.SetStatusCondition(&obs.Status.SDIConfigStatus.Conditions, metav1.Condition{
			Type:               "OperatorDegraded",
			Status:             metav1.ConditionTrue,
			Reason:             sdiv1alpha1.ReasonOperandResourceFailed,
			LastTransitionTime: metav1.NewTime(time.Now()),
			Message:            fmt.Sprintf("unable to update operand daemonset: %s", err.Error()),
		})
		return err
	}

	return nil

}

func (a *Adjuster) AdjustSDIVSystemVrepStatefulSets(ns string, obs *sdiv1alpha1.SDIObserver, ctx context.Context) error {

	stsName := "vsystem-vrep"
	ss := &appsv1.StatefulSet{}

	err := a.Client.Get(ctx, client.ObjectKey{Name: stsName, Namespace: ns}, ss)
	if err != nil {
		meta.SetStatusCondition(&obs.Status.SDINodeConfigStatus.Conditions, metav1.Condition{
			Type:               "OperatorDegraded",
			Status:             metav1.ConditionTrue,
			Reason:             sdiv1alpha1.ReasonResourceNotAvailable,
			LastTransitionTime: metav1.NewTime(time.Now()),
			Message:            fmt.Sprintf("unable to get operand statefulset: %s", err.Error()),
		})
		return err
	}

	volumeName := "exports-mask"
	volumePatched := false
	volumeMountPatched := false

	for _, v := range ss.Spec.Template.Spec.Volumes {
		if v.Name == volumeName {
			a.logger.Info("Volume is already patched for statefulset " + stsName)
			volumePatched = true
			break
		}
	}

	for _, c := range ss.Spec.Template.Spec.Containers {
		if c.Name == stsName {
			for _, vm := range c.VolumeMounts {
				if vm.Name == volumeName {
					a.logger.Info("VolumeMount is already patched for statefulset " + stsName)
					volumeMountPatched = true
					break
				}
			}
			break
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

	if !volumePatched {
		a.logger.Info("Volume will be patched for statefulset " + stsName)
		ss.Spec.Template.Spec.Volumes = append(ss.Spec.Template.Spec.Volumes, emptyDirVolume)
	}

	if !volumeMountPatched {
		var containers []corev1.Container
		for _, c := range ss.Spec.Template.Spec.Containers {
			if c.Name == stsName {
				emptyDirVolumeMount := corev1.VolumeMount{
					Name:      volumeName,
					MountPath: "/exports",
				}
				a.logger.Info("VolumeMount will be patched for statefulset " + stsName)
				c.VolumeMounts = append(c.VolumeMounts, emptyDirVolumeMount)
			}
			containers = append(containers, c)
		}
		ss.Spec.Template.Spec.Containers = containers
	}

	a.logger.Info("Patching Volume/VolumeMount for statefulset " + stsName)
	err = a.Client.Update(ctx, ss)
	if err != nil {
		meta.SetStatusCondition(&obs.Status.SDINodeConfigStatus.Conditions, metav1.Condition{
			Type:               "OperatorDegraded",
			Status:             metav1.ConditionTrue,
			Reason:             sdiv1alpha1.ReasonResourceNotAvailable,
			LastTransitionTime: metav1.NewTime(time.Now()),
			Message:            fmt.Sprintf("unable to update operand statefulset: %s", err.Error()),
		})
		return err
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
		meta.SetStatusCondition(&obs.Status.SDINodeConfigStatus.Conditions, metav1.Condition{
			Type:               "OperatorDegraded",
			Status:             metav1.ConditionTrue,
			Reason:             sdiv1alpha1.ReasonResourceNotAvailable,
			LastTransitionTime: metav1.NewTime(time.Now()),
			Message:            fmt.Sprintf("unable to get operand statefulset: %s", err.Error()),
		})
		return err
	}

	if ss.Status.UpdateRevision == ss.Status.CurrentRevision {
		a.logger.Info(fmt.Sprintf("Statefulset %s current revision is the same as its update revision.", stsName))
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
		meta.SetStatusCondition(&obs.Status.SDINodeConfigStatus.Conditions, metav1.Condition{
			Type:               "OperatorDegraded",
			Status:             metav1.ConditionTrue,
			Reason:             sdiv1alpha1.ReasonResourceNotAvailable,
			LastTransitionTime: metav1.NewTime(time.Now()),
			Message:            fmt.Sprintf("unable to get operand pod list: %s", err.Error()),
		})
		return err
	}

	if len(updateRevisionPodList.Items) > 0 {
		a.logger.Info(fmt.Sprintf("The pod of the updated revision of statefulset %s exists already. Do nothing.", stsName))
		return nil
	}

	a.logger.Info(fmt.Sprintf("The pod of the updated revision of statefulset %s does not exists. Clean up the pod of outdated revision.", stsName))

	podList := &corev1.PodList{}
	err = a.Client.List(ctx, podList,
		client.InNamespace(namespace),
		client.MatchingLabels(ss.Spec.Selector.MatchLabels))

	if err != nil {
		meta.SetStatusCondition(&obs.Status.SDINodeConfigStatus.Conditions, metav1.Condition{
			Type:               "OperatorDegraded",
			Status:             metav1.ConditionTrue,
			Reason:             sdiv1alpha1.ReasonResourceNotAvailable,
			LastTransitionTime: metav1.NewTime(time.Now()),
			Message:            fmt.Sprintf("unable to get operand pod list: %s", err.Error()),
		})
		return err
	}

	for _, pod := range podList.Items {
		if pod.Labels["controller-revision-hash"] != ss.Status.UpdateRevision {
			a.logger.Info(fmt.Sprintf("Delete pod %s which has the outdated revision of statefulset %s.", pod.Name, stsName))
			err := a.Client.Delete(ctx, &pod, client.GracePeriodSeconds(1))
			if err != nil {
				meta.SetStatusCondition(&obs.Status.SDIConfigStatus.Conditions, metav1.Condition{
					Type:               "OperatorDegraded",
					Status:             metav1.ConditionTrue,
					Reason:             sdiv1alpha1.ReasonOperandResourceFailed,
					LastTransitionTime: metav1.NewTime(time.Now()),
					Message:            fmt.Sprintf("unable to delete operand pod: %s", err.Error()),
				})
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
			meta.SetStatusCondition(&obs.Status.SDIConfigStatus.Conditions, metav1.Condition{
				Type:               "OperatorDegraded",
				Status:             metav1.ConditionTrue,
				Reason:             sdiv1alpha1.ReasonOperandResourceFailed,
				LastTransitionTime: metav1.NewTime(time.Now()),
				Message: fmt.Sprintf(
					"unable to adjust operand namespace node selector annotation: %s",
					err.Error(),
				),
			})
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

func (a *Adjuster) AdjustSDIRbac(ns string, obs *sdiv1alpha1.SDIObserver, ctx context.Context) error {

	privilegedRole := &rbacv1.RoleBinding{}
	privilegedRoleName := "sdi-privileged"
	err := a.Client.Get(ctx, client.ObjectKey{Name: privilegedRoleName, Namespace: ns}, privilegedRole)
	if err != nil && errors.IsNotFound(err) {
		a.logger.Info(fmt.Sprintf(
			"Privileged role %s does not exist in namespace %s. Create a new one",
			privilegedRoleName,
			ns,
		))
		privilegedRoleAsset := assets.GetRoleFromFile("manifests/role-rolebinding-config-for-sdi/privileged-role.yaml")
		privilegedRoleAsset.Namespace = ns
		if err := a.Client.Create(ctx, privilegedRoleAsset); err != nil {
			meta.SetStatusCondition(&obs.Status.SDINodeConfigStatus.Conditions, metav1.Condition{
				Type:               "OperatorDegraded",
				Status:             metav1.ConditionTrue,
				Reason:             sdiv1alpha1.ReasonOperandResourceFailed,
				LastTransitionTime: metav1.NewTime(time.Now()),
				Message:            fmt.Sprintf("unable to get operand role binding: %s", err.Error()),
			})
			return err
		}
		a.logger.Info(fmt.Sprintf(
			"Privileged role %s is created in namespace %s",
			privilegedRoleName,
			ns,
		))
		ctrl.SetControllerReference(obs, privilegedRoleAsset, a.Scheme)
	} else if err != nil {
		meta.SetStatusCondition(&obs.Status.SDINodeConfigStatus.Conditions, metav1.Condition{
			Type:               "OperatorDegraded",
			Status:             metav1.ConditionTrue,
			Reason:             sdiv1alpha1.ReasonResourceNotAvailable,
			LastTransitionTime: metav1.NewTime(time.Now()),
			Message:            fmt.Sprintf("unable to get operand role binding: %s", err.Error()),
		})
		return err
	} else {
		a.logger.Info(fmt.Sprintf(
			"Privileged role %s already exists in namespace %s. Do nothing",
			privilegedRoleName,
			ns,
		))
	}

	privilegedRoleBinding := &rbacv1.RoleBinding{}
	privilegedRoleBindingName := "sdi-privileged"
	err = a.Client.Get(ctx, client.ObjectKey{Name: privilegedRoleBindingName, Namespace: ns}, privilegedRoleBinding)
	if err != nil && errors.IsNotFound(err) {
		privilegedRoleBindingAsset := assets.GetRoleBindingFromFile("manifests/role-rolebinding-config-for-sdi/privileged-rolebinding.yaml")
		privilegedRoleBindingAsset.Namespace = ns

		privilegedRoleBindingAsset.Subjects = []rbacv1.Subject{
			{
				Kind:      "ServiceAccount",
				Name:      "default",
				Namespace: ns,
			},
			{
				Kind:      "ServiceAccount",
				Name:      "mlf-deployment-api",
				Namespace: ns,
			},
			{
				Kind:      "ServiceAccount",
				Name:      "vora-vflow-server",
				Namespace: ns,
			},
			{
				Kind:      "ServiceAccount",
				Name:      "vora-vsystem-" + ns,
				Namespace: ns,
			},
			{
				Kind:      "ServiceAccount",
				Name:      "vora-vsystem-" + ns + "-vrep",
				Namespace: ns,
			},

			// SDI 3.2 compatibility
			{
				Kind:      "ServiceAccount",
				Name:      ns + "-elasticsearch",
				Namespace: ns,
			},
			{
				Kind:      "ServiceAccount",
				Name:      ns + "-fluentd",
				Namespace: ns,
			},

			// SDI 3.3
			{
				Kind:      "ServiceAccount",
				Name:      "diagnostics-elasticsearch",
				Namespace: ns,
			},
			{
				Kind:      "ServiceAccount",
				Name:      "diagnostics-fluentd",
				Namespace: ns,
			},
		}

		a.logger.Info(fmt.Sprintf(
			"Privileged roleBinding %s does not exist in namespace %s. Create a new one",
			privilegedRoleBindingName,
			ns,
		))
		if err := a.Client.Create(ctx, privilegedRoleBindingAsset); err != nil {
			meta.SetStatusCondition(&obs.Status.SDINodeConfigStatus.Conditions, metav1.Condition{
				Type:               "OperatorDegraded",
				Status:             metav1.ConditionTrue,
				Reason:             sdiv1alpha1.ReasonOperandResourceFailed,
				LastTransitionTime: metav1.NewTime(time.Now()),
				Message:            fmt.Sprintf("unable to get operand role binding: %s", err.Error()),
			})
			return err
		}

		a.logger.Info(fmt.Sprintf(
			"Privileged roleBinding %s is created in namespace %s",
			privilegedRoleBindingName,
			ns,
		))
		ctrl.SetControllerReference(obs, privilegedRoleBindingAsset, a.Scheme)

	} else if err != nil {
		meta.SetStatusCondition(&obs.Status.SDINodeConfigStatus.Conditions, metav1.Condition{
			Type:               "OperatorDegraded",
			Status:             metav1.ConditionTrue,
			Reason:             sdiv1alpha1.ReasonResourceNotAvailable,
			LastTransitionTime: metav1.NewTime(time.Now()),
			Message:            fmt.Sprintf("unable to get operand role binding: %s", err.Error()),
		})
		return err
	} else {
		a.logger.Info(fmt.Sprintf(
			"Privileged roleBinding %s already exists in namespace %s. Do nothing",
			privilegedRoleBindingName,
			ns,
		))
	}

	// Handle anyuid role, rolebinding
	anyuidRole := &rbacv1.RoleBinding{}
	anyuidRoleName := "sdi-anyuid"
	err = a.Client.Get(ctx, client.ObjectKey{Name: anyuidRoleName, Namespace: ns}, anyuidRole)
	if err != nil && errors.IsNotFound(err) {
		anyuidRoleAsset := assets.GetRoleFromFile("manifests/role-rolebinding-config-for-sdi/anyuid-role.yaml")
		anyuidRoleAsset.Namespace = ns
		a.logger.Info(fmt.Sprintf(
			"Anyuid role %s does not exist in namespace %s. Create a new one",
			anyuidRoleName,
			ns,
		))
		if err := a.Client.Create(ctx, anyuidRoleAsset); err != nil {
			meta.SetStatusCondition(&obs.Status.SDINodeConfigStatus.Conditions, metav1.Condition{
				Type:               "OperatorDegraded",
				Status:             metav1.ConditionTrue,
				Reason:             sdiv1alpha1.ReasonOperandResourceFailed,
				LastTransitionTime: metav1.NewTime(time.Now()),
				Message:            fmt.Sprintf("unable to get operand role binding: %s", err.Error()),
			})
			return err
		}
		a.logger.Info(fmt.Sprintf(
			"Anyuid role %s is created in namespace %s",
			anyuidRoleName,
			ns,
		))
		ctrl.SetControllerReference(obs, anyuidRoleAsset, a.Scheme)
	} else if err != nil {
		meta.SetStatusCondition(&obs.Status.SDINodeConfigStatus.Conditions, metav1.Condition{
			Type:               "OperatorDegraded",
			Status:             metav1.ConditionTrue,
			Reason:             sdiv1alpha1.ReasonResourceNotAvailable,
			LastTransitionTime: metav1.NewTime(time.Now()),
			Message:            fmt.Sprintf("unable to get operand role binding: %s", err.Error()),
		})
		return err
	} else {
		a.logger.Info(fmt.Sprintf(
			"Anyuid role %s already exists in namespace %s. Do nothing",
			anyuidRoleName,
			ns,
		))
	}

	anyuidRoleBinding := &rbacv1.RoleBinding{}
	anyuidRoleBindingName := "sdi-anyuid"
	err = a.Client.Get(ctx, client.ObjectKey{Name: anyuidRoleBindingName, Namespace: ns}, anyuidRoleBinding)
	if err != nil && errors.IsNotFound(err) {
		anyuidRoleBindingAsset := assets.GetRoleBindingFromFile("manifests/role-rolebinding-config-for-sdi/anyuid-rolebinding.yaml")
		anyuidRoleBindingAsset.Namespace = ns

		anyuidRoleBindingAsset.Subjects = []rbacv1.Subject{
			{
				Kind: "Group",
				Name: "system:serviceaccounts:" + ns,
			},
		}

		a.logger.Info(fmt.Sprintf(
			"Anyuid roleBinding %s does not exist in namespace %s. Create a new one",
			anyuidRoleBindingName,
			ns,
		))

		if err := a.Client.Create(ctx, anyuidRoleBindingAsset); err != nil {
			meta.SetStatusCondition(&obs.Status.SDINodeConfigStatus.Conditions, metav1.Condition{
				Type:               "OperatorDegraded",
				Status:             metav1.ConditionTrue,
				Reason:             sdiv1alpha1.ReasonOperandResourceFailed,
				LastTransitionTime: metav1.NewTime(time.Now()),
				Message:            fmt.Sprintf("unable to get operand role binding: %s", err.Error()),
			})
			return err
		}

		a.logger.Info(fmt.Sprintf(
			"Anyuid roleBinding %s is created in namespace %s",
			anyuidRoleBindingName,
			ns,
		))
		ctrl.SetControllerReference(obs, anyuidRoleBindingAsset, a.Scheme)

	} else if err != nil {
		meta.SetStatusCondition(&obs.Status.SDINodeConfigStatus.Conditions, metav1.Condition{
			Type:               "OperatorDegraded",
			Status:             metav1.ConditionTrue,
			Reason:             sdiv1alpha1.ReasonResourceNotAvailable,
			LastTransitionTime: metav1.NewTime(time.Now()),
			Message:            fmt.Sprintf("unable to get operand role binding: %s", err.Error()),
		})
		return err
	} else {
		a.logger.Info(fmt.Sprintf(
			"Anyuid roleBinding %s already exists in namespace %s. Do nothing",
			anyuidRoleBindingName,
			ns,
		))
	}

	return nil
}
