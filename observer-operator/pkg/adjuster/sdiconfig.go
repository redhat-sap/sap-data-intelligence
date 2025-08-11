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
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/labels"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/utils/pointer"
	"reflect"
	"sigs.k8s.io/controller-runtime/pkg/client"
)


func (a *Adjuster) adjustSDIDataHub(ns string, obs *sdiv1alpha1.SDIObserver, ctx context.Context) error {
	if ns == "" {
		return fmt.Errorf("namespace cannot be empty")
	}
	if obs == nil {
		return fmt.Errorf("SDIObserver cannot be nil")
	}

	obj := &unstructured.Unstructured{}
	obj.SetName("default")
	obj.SetNamespace(ns)
	obj.SetGroupVersionKind(schema.GroupVersionKind{
		Group:   DataHubAPIGroup,
		Version: DataHubAPIVersion,
		Kind:    DataHubKind,
	})

	if err := a.Client.Get(ctx, client.ObjectKeyFromObject(obj), obj); err != nil {
		return fmt.Errorf("failed to get DataHub object: %w", err)
	}

	spec, ok := obj.Object["spec"].(map[string]interface{})
	if !ok {
		return fmt.Errorf("DataHub spec is not a map")
	}
	
	vsystem, ok := spec["vsystem"].(map[string]interface{})
	if !ok {
		return fmt.Errorf("DataHub vsystem is not a map")
	}
	
	vRep, ok := vsystem["vRep"].(map[string]interface{})
	if !ok {
		// Initialize vRep if it doesn't exist
		vRep = make(map[string]interface{})
		vsystem["vRep"] = vRep
	}

	if len(vRep) == 0 {
		a.logger.Info("Patching DataHub vRep to set exportsMask to true", "namespace", ns)
		vRep["exportsMask"] = true
		if err := a.Client.Update(ctx, obj); err != nil {
			return err
		}
	} else {
		a.logger.Info("DataHub vRep is already patched")
	}
	return nil
}

func (a *Adjuster) AdjustSDIDiagnosticsFluentdDaemonsetContainerPrivilege(ns string, obs *sdiv1alpha1.SDIObserver, ctx context.Context) error {
	if ns == "" {
		return fmt.Errorf("namespace cannot be empty")
	}
	if obs == nil {
		return fmt.Errorf("SDIObserver cannot be nil")
	}
	ds := &appsv1.DaemonSet{
		ObjectMeta: metav1.ObjectMeta{
			Name:      DiagnosticFluentdName,
			Namespace: ns,
		},
	}

	if err := a.Client.Get(ctx, client.ObjectKeyFromObject(ds), ds); err != nil {
		return err
	}

	updated := false
	for i, c := range ds.Spec.Template.Spec.Containers {
		if c.Name == DiagnosticFluentdName {
			if c.SecurityContext.Privileged == nil || !*c.SecurityContext.Privileged {
				ds.Spec.Template.Spec.Containers[i].SecurityContext.Privileged = pointer.Bool(true)
				updated = true
				break
			}
		}
	}

	if updated {
		a.logger.Info("Patching daemonset with privileged security context")
		if err := a.Client.Update(ctx, ds); err != nil {
			return err
		}
	} else {
		a.logger.Info(fmt.Sprintf("Daemonset %s is already using privileged security context", DiagnosticFluentdName))
	}
	return nil
}

func (a *Adjuster) AdjustSDIVSystemVrepStatefulSets(ns string, obs *sdiv1alpha1.SDIObserver, ctx context.Context) error {
	ss := &appsv1.StatefulSet{}
	if err := a.Client.Get(ctx, client.ObjectKey{Name: VSystemVrepStsName, Namespace: ns}, ss); err != nil {
		return err
	}

	volumePatched, volumeMountPatched := false, false
	for _, v := range ss.Spec.Template.Spec.Volumes {
		if v.Name == VolumeName {
			volumePatched = true
			break
		}
	}

	for _, c := range ss.Spec.Template.Spec.Containers {
		if c.Name == VSystemVrepStsName {
			for _, vm := range c.VolumeMounts {
				if vm.Name == VolumeName {
					volumeMountPatched = true
					break
				}
			}
			break
		}
	}

	if volumePatched && volumeMountPatched {
		a.logger.Info(fmt.Sprintf("StatefulSet %s volumes and mounts are already patched", VSystemVrepStsName))
		if err := a.pruneStatefulSetOldRevision(ns, obs, ctx); err != nil {
			return err
		}
	} else {
		if !volumePatched {
			a.logger.Info(fmt.Sprintf("Patching StatefulSet %s with new volume", VSystemVrepStsName))
			ss.Spec.Template.Spec.Volumes = append(ss.Spec.Template.Spec.Volumes, corev1.Volume{
				Name: VolumeName,
				VolumeSource: corev1.VolumeSource{
					EmptyDir: &corev1.EmptyDirVolumeSource{},
				},
			})
		}

		if !volumeMountPatched {
			a.logger.Info(fmt.Sprintf("Patching StatefulSet %s with new volume mount", VSystemVrepStsName))
			for i, c := range ss.Spec.Template.Spec.Containers {
				if c.Name == VSystemVrepStsName {
					ss.Spec.Template.Spec.Containers[i].VolumeMounts = append(c.VolumeMounts, corev1.VolumeMount{
						Name:      VolumeName,
						MountPath: "/exports",
					})
				}
			}
		}

		if err := a.Client.Update(ctx, ss); err != nil {
			return fmt.Errorf("unable to update operand statefulset: %w", err)
		}

		if err := a.adjustSDIDataHub(ns, obs, ctx); err != nil {
			return err
		}

		if err := a.pruneStatefulSetOldRevision(ns, obs, ctx); err != nil {
			return err
		}
	}

	return nil
}

func (a *Adjuster) pruneStatefulSetOldRevision(ns string, obs *sdiv1alpha1.SDIObserver, ctx context.Context) error {
	ss := &appsv1.StatefulSet{}
	if err := a.Client.Get(ctx, client.ObjectKey{Name: VSystemVrepStsName, Namespace: ns}, ss); err != nil {
		return err
	}

	if ss.Status.UpdateRevision == ss.Status.CurrentRevision {
		a.logger.Info(fmt.Sprintf("StatefulSet %s current revision matches update revision", VSystemVrepStsName))
		return nil
	}

	updateRevisionPodList := &corev1.PodList{}
	updateRevisionSelector := labels.SelectorFromSet(labels.Set{ControllerRevisionHashLabel: ss.Status.UpdateRevision})

	if err := a.Client.List(ctx, updateRevisionPodList, client.InNamespace(ns), client.MatchingLabelsSelector{Selector: updateRevisionSelector}); err != nil {
		return err
	}

	if len(updateRevisionPodList.Items) > 0 {
		a.logger.Info("Pods for the updated revision exist; no action needed")
		return nil
	}

	a.logger.Info("Cleaning up pods from outdated revisions")
	podList := &corev1.PodList{}
	if err := a.Client.List(ctx, podList, client.InNamespace(ns), client.MatchingLabels(ss.Spec.Selector.MatchLabels)); err != nil {
		return fmt.Errorf("unable to get operand pod list: %w", err)
	}

	for _, pod := range podList.Items {
		if pod.Labels[ControllerRevisionHashLabel] != ss.Status.UpdateRevision {
			a.logger.Info(fmt.Sprintf("Deleting pod %s with outdated revision", pod.Name))
			if err := a.Client.Delete(ctx, &pod, client.GracePeriodSeconds(DefaultGracePeriodSeconds)); err != nil {
				return fmt.Errorf("unable to delete operand pod: %w", err)
			}
		}
	}

	return nil
}

func (a *Adjuster) AdjustNamespaceAnnotation(ns, nodeSelector string, ctx context.Context) error {
	namespace := &corev1.Namespace{}
	if err := a.Client.Get(ctx, types.NamespacedName{Name: ns}, namespace); err != nil {
		return fmt.Errorf("unable to get namespace %s: %w", ns, err)
	}

	if namespace.Annotations == nil {
		namespace.Annotations = map[string]string{}
	}

	if currentSelector := namespace.Annotations[AnnotationKey]; currentSelector != nodeSelector {
		a.logger.Info("Updating namespace annotation")
		namespace.Annotations[AnnotationKey] = nodeSelector
		if err := a.Client.Update(ctx, namespace); err != nil {
			return fmt.Errorf("unable to update namespace annotation: %w", err)
		}
	} else {
		a.logger.Info(fmt.Sprintf("Namespace %s annotation is already set", ns))
	}
	return nil
}

func (a *Adjuster) AdjustSDIRbac(ns string, obs *sdiv1alpha1.SDIObserver, ctx context.Context) error {
	// Define role and role binding names
	const (
		privilegedRoleName        = "sdi-privileged"
		anyuidRoleName            = "sdi-anyuid"
		privilegedRoleBindingName = "sdi-privileged"
		anyuidRoleBindingName     = "sdi-anyuid"
	)

	// Ensure roles exist
	if err := a.ensureRole(ns, privilegedRoleName, a.getPrivilegedRole(), ctx); err != nil {
		return fmt.Errorf("unable to ensure privileged role: %w", err)
	}
	if err := a.ensureRole(ns, anyuidRoleName, a.getAnyuidRole(), ctx); err != nil {
		return fmt.Errorf("unable to ensure anyuid role: %w", err)
	}

	// Ensure role bindings exist
	if err := a.ensureRoleBinding(ns, privilegedRoleBindingName, a.getPrivilegedRoleBinding(), ctx); err != nil {
		return fmt.Errorf("unable to ensure privileged role binding: %w", err)
	}
	if err := a.ensureRoleBinding(ns, anyuidRoleBindingName, a.getAnyuidRoleBinding(), ctx); err != nil {
		return fmt.Errorf("unable to ensure anyuid role binding: %w", err)
	}

	a.logger.Info("SDI RBAC settings adjustment is done")
	return nil
}

func (a *Adjuster) ensureRole(ns, name string, getRoleFunc func() client.Object, ctx context.Context) error {
	role := getRoleFunc().(*rbacv1.Role)
	role.Name = name
	role.Namespace = ns

	if err := a.Client.Get(ctx, client.ObjectKeyFromObject(role), role); err != nil {
		if errors.IsNotFound(err) {
			a.logger.Info(fmt.Sprintf("Creating role %s", name))
			if err := a.Client.Create(ctx, role); err != nil {
				return fmt.Errorf("unable to create role %s: %w", name, err)
			}
		} else {
			return fmt.Errorf("unable to get role %s: %w", name, err)
		}
	}
	return nil
}

func (a *Adjuster) ensureRoleBinding(ns, name string, getRoleBindingFunc func() client.Object, ctx context.Context) error {
	desiredRoleBinding := getRoleBindingFunc().(*rbacv1.RoleBinding)
	desiredRoleBinding.Name = name
	desiredRoleBinding.Namespace = ns

	// Modify the subjects based on the role binding name
	switch name {
	case "sdi-privileged":
		desiredRoleBinding.Subjects = []rbacv1.Subject{
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

			// SDI 3.3 SDI restore hana serviceaccount
			{
				Kind:      "ServiceAccount",
				Name:      "hana-service-account",
				Namespace: ns,
			},
		}
	case "sdi-anyuid":
		desiredRoleBinding.Subjects = []rbacv1.Subject{
			{
				Kind:     "Group",
				Name:     "system:serviceaccounts:" + ns,
				APIGroup: "rbac.authorization.k8s.io",
			},
		}
	default:
		return fmt.Errorf("unknown role binding name: %s", name)
	}

	// Check if the role binding already exists
	existingRoleBinding := &rbacv1.RoleBinding{}
	if err := a.Client.Get(ctx, client.ObjectKeyFromObject(desiredRoleBinding), existingRoleBinding); err != nil {
		if errors.IsNotFound(err) {
			a.logger.Info(fmt.Sprintf("Creating role binding %s", name))
			if err := a.Client.Create(ctx, desiredRoleBinding); err != nil {
				return fmt.Errorf("unable to create role binding %s: %w", name, err)
			}
		} else {
			return fmt.Errorf("unable to get role binding %s: %w", name, err)
		}
	} else {
		// Compare using reflect.DeepEqual
		if !reflect.DeepEqual(existingRoleBinding.Subjects, desiredRoleBinding.Subjects) {
			a.logger.Info(fmt.Sprintf("Updating role binding %s", name))
			// Update the existing role binding with the desired subjects
			existingRoleBinding.Subjects = desiredRoleBinding.Subjects
			if err := a.Client.Update(ctx, existingRoleBinding); err != nil {
				return fmt.Errorf("unable to update role binding %s: %w", name, err)
			}
		}
	}
	return nil
}
func (a *Adjuster) getPrivilegedRole() func() client.Object {
	return assets.GetRoleFromFile("manifests/role-rolebinding-config-for-sdi/privileged-role.yaml")
}

func (a *Adjuster) getAnyuidRole() func() client.Object {
	return assets.GetRoleFromFile("manifests/role-rolebinding-config-for-sdi/anyuid-role.yaml")
}

func (a *Adjuster) getPrivilegedRoleBinding() func() client.Object {
	return assets.GetRoleBindingFromFile("manifests/role-rolebinding-config-for-sdi/privileged-rolebinding.yaml")
}

func (a *Adjuster) getAnyuidRoleBinding() func() client.Object {
	return assets.GetRoleBindingFromFile("manifests/role-rolebinding-config-for-sdi/anyuid-rolebinding.yaml")
}
