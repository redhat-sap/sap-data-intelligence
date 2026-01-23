package adjuster

import (
	"context"
	"fmt"
	"reflect"

	sdiv1alpha1 "github.com/redhat-sap/sap-data-intelligence/observer-operator/api/v1alpha1"
	"github.com/redhat-sap/sap-data-intelligence/observer-operator/assets"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	rbacv1 "k8s.io/api/rbac/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/utils/ptr"
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
		a.logger.Info("DataHub vRep: patching exportsMask", "namespace", ns)
		vRep["exportsMask"] = true
		if err := a.Client.Update(ctx, obj); err != nil {
			return err
		}
	} else {
		a.logger.V(1).Info("DataHub vRep: already configured")
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

	podUpdated := a.patchPodSecurityContext(&ds.Spec.Template.Spec)
	containerUpdated := a.patchContainerSecurityContext(&ds.Spec.Template.Spec, DiagnosticFluentdName)
	initContainerUpdated := a.ensureFluentdInitContainer(&ds.Spec.Template.Spec)
	updated := podUpdated || containerUpdated || initContainerUpdated

	if updated {
		a.logger.Info("DaemonSet: patching security context", "name", DiagnosticFluentdName)
		if err := a.Client.Update(ctx, ds); err != nil {
			return err
		}
	} else {
		a.logger.V(1).Info("DaemonSet: already configured", "name", DiagnosticFluentdName)
	}
	return nil
}

// patchPodSecurityContext patches the pod-level security context.
// Returns true if any changes were made.
func (a *Adjuster) patchPodSecurityContext(podSpec *corev1.PodSpec) bool {
	updated := false
	if podSpec.SecurityContext == nil {
		podSpec.SecurityContext = &corev1.PodSecurityContext{}
	}
	podSecCtx := podSpec.SecurityContext
	// Allow running as any user (not restricted to non-root)
	if podSecCtx.RunAsNonRoot == nil || *podSecCtx.RunAsNonRoot {
		podSecCtx.RunAsNonRoot = ptr.To(false)
		updated = true
	}
	// Remove runAsUser if it was previously set to 0 by this operator
	// Let the container run as the original UID to maintain compatibility
	// with files created by previous versions
	if podSecCtx.RunAsUser != nil && *podSecCtx.RunAsUser == 0 {
		podSecCtx.RunAsUser = nil
		updated = true
	}
	return updated
}

// patchContainerSecurityContext patches the container-level security context for privileged execution.
// Returns true if any changes were made.
func (a *Adjuster) patchContainerSecurityContext(podSpec *corev1.PodSpec, containerName string) bool {
	updated := false
	for i := range podSpec.Containers {
		if podSpec.Containers[i].Name != containerName {
			continue
		}
		if podSpec.Containers[i].SecurityContext == nil {
			podSpec.Containers[i].SecurityContext = &corev1.SecurityContext{}
		}
		secCtx := podSpec.Containers[i].SecurityContext
		if secCtx.Privileged == nil || !*secCtx.Privileged {
			secCtx.Privileged = ptr.To(true)
			updated = true
		}
		if secCtx.AllowPrivilegeEscalation == nil || !*secCtx.AllowPrivilegeEscalation {
			secCtx.AllowPrivilegeEscalation = ptr.To(true)
			updated = true
		}
		if secCtx.RunAsNonRoot == nil || *secCtx.RunAsNonRoot {
			secCtx.RunAsNonRoot = ptr.To(false)
			updated = true
		}
		// Remove runAsUser if it was previously set to 0 by this operator
		// Let the container run as the original UID to maintain compatibility
		// with files created by previous versions
		if secCtx.RunAsUser != nil && *secCtx.RunAsUser == 0 {
			secCtx.RunAsUser = nil
			updated = true
		}
		// Clear capabilities.drop when running privileged to avoid interference
		if secCtx.Capabilities != nil && len(secCtx.Capabilities.Drop) > 0 {
			secCtx.Capabilities.Drop = nil
			updated = true
		}
		// Set SELinux type to spc_t (super privileged container) to bypass SELinux restrictions on host paths
		if secCtx.SELinuxOptions == nil || secCtx.SELinuxOptions.Type != "spc_t" {
			secCtx.SELinuxOptions = &corev1.SELinuxOptions{Type: "spc_t"}
			updated = true
		}
		break
	}
	return updated
}

// ensureFluentdInitContainer adds an init container to fix permissions on the pos file.
// This handles the upgrade case where the pos file was created by a previous version
// running as a different UID. Returns true if any changes were made.
func (a *Adjuster) ensureFluentdInitContainer(podSpec *corev1.PodSpec) bool {
	expectedCommand := "if [ -f " + DiagnosticFluentdPosFile + " ]; then chmod 666 " + DiagnosticFluentdPosFile + " || true; fi"

	// Check if init container already exists with correct command
	for i := range podSpec.InitContainers {
		if podSpec.InitContainers[i].Name == DiagnosticFluentdInitName {
			// Check if command matches expected
			if len(podSpec.InitContainers[i].Command) == 3 &&
				podSpec.InitContainers[i].Command[2] == expectedCommand {
				return false // Already configured correctly
			}
			// Update command to use chmod instead of chown
			podSpec.InitContainers[i].Command = []string{"/bin/sh", "-c", expectedCommand}
			return true
		}
	}

	// Get the main container's image to use for the init container
	var fluentdImage string
	for i := range podSpec.Containers {
		if podSpec.Containers[i].Name == DiagnosticFluentdName {
			fluentdImage = podSpec.Containers[i].Image
			break
		}
	}
	if fluentdImage == "" {
		return false
	}

	// Create init container that fixes file permissions
	// Use chmod 666 to make the file writable by any UID, avoiding hardcoded UID dependencies
	initContainer := corev1.Container{
		Name:  DiagnosticFluentdInitName,
		Image: fluentdImage,
		Command: []string{
			"/bin/sh",
			"-c",
			expectedCommand,
		},
		VolumeMounts: []corev1.VolumeMount{
			{
				Name:      DiagnosticFluentdVarTmpVolume,
				MountPath: "/var/tmp",
			},
		},
		SecurityContext: &corev1.SecurityContext{
			RunAsUser:                ptr.To(int64(0)),
			RunAsNonRoot:             ptr.To(false),
			Privileged:               ptr.To(true),
			AllowPrivilegeEscalation: ptr.To(true),
			SELinuxOptions:           &corev1.SELinuxOptions{Type: "spc_t"},
		},
		Resources: corev1.ResourceRequirements{
			Requests: corev1.ResourceList{
				corev1.ResourceCPU:    resource.MustParse("10m"),
				corev1.ResourceMemory: resource.MustParse("10Mi"),
			},
			Limits: corev1.ResourceList{
				corev1.ResourceCPU:    resource.MustParse("50m"),
				corev1.ResourceMemory: resource.MustParse("50Mi"),
			},
		},
	}

	podSpec.InitContainers = append(podSpec.InitContainers, initContainer)
	return true
}

func (a *Adjuster) AdjustSDIVSystemVrepStatefulSets(ns string, obs *sdiv1alpha1.SDIObserver, ctx context.Context) error {
	ss := &appsv1.StatefulSet{}
	if err := a.Client.Get(ctx, client.ObjectKey{Name: VSystemVrepStsName, Namespace: ns}, ss); err != nil {
		return err
	}

	volumePatched := a.isVolumePatched(ss)
	volumeMountPatched := a.isVolumeMountPatched(ss)

	if volumePatched && volumeMountPatched {
		a.logger.V(1).Info("StatefulSet: already configured", "name", VSystemVrepStsName)
		return a.pruneStatefulSetOldRevision(ns, ctx)
	}

	return a.patchStatefulSet(ss, ns, obs, ctx, volumePatched, volumeMountPatched)
}

// isVolumePatched checks if the required volume is already present in the StatefulSet
func (a *Adjuster) isVolumePatched(ss *appsv1.StatefulSet) bool {
	for i := range ss.Spec.Template.Spec.Volumes {
		if ss.Spec.Template.Spec.Volumes[i].Name == VolumeName {
			return true
		}
	}
	return false
}

// isVolumeMountPatched checks if the required volume mount is already present in the StatefulSet
func (a *Adjuster) isVolumeMountPatched(ss *appsv1.StatefulSet) bool {
	for i := range ss.Spec.Template.Spec.Containers {
		if ss.Spec.Template.Spec.Containers[i].Name == VSystemVrepStsName {
			for j := range ss.Spec.Template.Spec.Containers[i].VolumeMounts {
				if ss.Spec.Template.Spec.Containers[i].VolumeMounts[j].Name == VolumeName {
					return true
				}
			}
			break
		}
	}
	return false
}

// patchStatefulSet applies the required volume and volume mount patches to the StatefulSet
func (a *Adjuster) patchStatefulSet(ss *appsv1.StatefulSet, ns string, obs *sdiv1alpha1.SDIObserver, ctx context.Context, volumePatched, volumeMountPatched bool) error {
	if !volumePatched {
		a.logger.Info("StatefulSet: adding volume", "name", VSystemVrepStsName, "volume", VolumeName)
		ss.Spec.Template.Spec.Volumes = append(ss.Spec.Template.Spec.Volumes, corev1.Volume{
			Name: VolumeName,
			VolumeSource: corev1.VolumeSource{
				EmptyDir: &corev1.EmptyDirVolumeSource{},
			},
		})
	}

	if !volumeMountPatched {
		a.logger.Info("StatefulSet: adding volume mount", "name", VSystemVrepStsName, "mount", "/exports")
		for i := range ss.Spec.Template.Spec.Containers {
			if ss.Spec.Template.Spec.Containers[i].Name == VSystemVrepStsName {
				ss.Spec.Template.Spec.Containers[i].VolumeMounts = append(ss.Spec.Template.Spec.Containers[i].VolumeMounts, corev1.VolumeMount{
					Name:      VolumeName,
					MountPath: "/exports",
				})
				break
			}
		}
	}

	if err := a.Client.Update(ctx, ss); err != nil {
		return fmt.Errorf("unable to update operand statefulset: %w", err)
	}

	if err := a.adjustSDIDataHub(ns, obs, ctx); err != nil {
		return err
	}

	return a.pruneStatefulSetOldRevision(ns, ctx)
}

// pruneStatefulSetOldRevision deletes pods running on old StatefulSet revisions.
// This is needed because the StatefulSet controller may not automatically roll out
// changes when the current pod is unhealthy (e.g., failing due to missing volume mounts).
// We cannot rely on Status.UpdateRevision == Status.CurrentRevision because the controller
// may report matching revisions even when pods are running on old revisions (e.g., when
// pods are not ready and not counted in status.currentReplicas).
func (a *Adjuster) pruneStatefulSetOldRevision(ns string, ctx context.Context) error {
	ss := &appsv1.StatefulSet{}
	if err := a.Client.Get(ctx, client.ObjectKey{Name: VSystemVrepStsName, Namespace: ns}, ss); err != nil {
		return err
	}

	// List all pods belonging to this StatefulSet
	podList := &corev1.PodList{}
	if err := a.Client.List(ctx, podList, client.InNamespace(ns), client.MatchingLabels(ss.Spec.Selector.MatchLabels)); err != nil {
		return fmt.Errorf("unable to get operand pod list: %w", err)
	}

	// Delete any pods not running the desired UpdateRevision
	for i := range podList.Items {
		podRevision := podList.Items[i].Labels[ControllerRevisionHashLabel]
		if podRevision != ss.Status.UpdateRevision {
			a.logger.Info("Pod: deleting outdated revision",
				"pod", podList.Items[i].Name,
				"podRevision", podRevision,
				"desiredRevision", ss.Status.UpdateRevision)
			if err := a.Client.Delete(ctx, &podList.Items[i], client.GracePeriodSeconds(DefaultGracePeriodSeconds)); err != nil {
				if !errors.IsNotFound(err) {
					return fmt.Errorf("unable to delete operand pod: %w", err)
				}
				// Pod already deleted, continue
			}
		} else {
			a.logger.V(1).Info("Pod: already on correct revision",
				"pod", podList.Items[i].Name,
				"revision", podRevision)
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
		a.logger.Info("Namespace: updating annotation", "namespace", ns)
		namespace.Annotations[AnnotationKey] = nodeSelector
		if err := a.Client.Update(ctx, namespace); err != nil {
			return fmt.Errorf("unable to update namespace annotation: %w", err)
		}
	} else {
		a.logger.V(1).Info("Namespace: annotation already set", "namespace", ns)
	}
	return nil
}

func (a *Adjuster) AdjustSDIRbac(ns string, _ *sdiv1alpha1.SDIObserver, ctx context.Context) error {
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

	a.logger.V(1).Info("RBAC: adjustment complete")
	return nil
}

func (a *Adjuster) ensureRole(ns, name string, getRoleFunc func() client.Object, ctx context.Context) error {
	desiredRole := getRoleFunc().(*rbacv1.Role)
	desiredRole.Name = name
	desiredRole.Namespace = ns

	existingRole := &rbacv1.Role{}
	if err := a.Client.Get(ctx, client.ObjectKeyFromObject(desiredRole), existingRole); err != nil {
		if errors.IsNotFound(err) {
			a.logger.Info("Role: creating", "name", name)
			if err := a.Client.Create(ctx, desiredRole); err != nil {
				return fmt.Errorf("unable to create role %s: %w", name, err)
			}
		} else {
			return fmt.Errorf("unable to get role %s: %w", name, err)
		}
	} else {
		// Compare rules and update if they differ
		if !reflect.DeepEqual(existingRole.Rules, desiredRole.Rules) {
			a.logger.Info("Role: updating", "name", name)
			existingRole.Rules = desiredRole.Rules
			if err := a.Client.Update(ctx, existingRole); err != nil {
				return fmt.Errorf("unable to update role %s: %w", name, err)
			}
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
			a.logger.Info("RoleBinding: creating", "name", name)
			if err := a.Client.Create(ctx, desiredRoleBinding); err != nil {
				return fmt.Errorf("unable to create role binding %s: %w", name, err)
			}
		} else {
			return fmt.Errorf("unable to get role binding %s: %w", name, err)
		}
	} else {
		// Compare using reflect.DeepEqual
		if !reflect.DeepEqual(existingRoleBinding.Subjects, desiredRoleBinding.Subjects) {
			a.logger.Info("RoleBinding: updating", "name", name)
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
