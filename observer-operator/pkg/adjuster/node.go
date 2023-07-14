package adjuster

import (
	"context"
	"fmt"
	operatorv1 "github.com/openshift/api/config/v1"
	openshiftv1 "github.com/openshift/api/image/v1"
	configv1 "github.com/openshift/machine-config-operator/pkg/apis/machineconfiguration.openshift.io/v1"
	sdiv1alpha1 "github.com/redhat-sap/sap-data-intelligence/observer-operator/api/v1alpha1"
	"github.com/redhat-sap/sap-data-intelligence/observer-operator/assets"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	rbacv1 "k8s.io/api/rbac/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	utilerrors "k8s.io/apimachinery/pkg/util/errors"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"time"
)

func (a *Adjuster) AdjustSDINodes(obs *sdiv1alpha1.SDIObserver, ctx context.Context) error {
	machineConfigClusterOperatorName := "machine-config"
	mcOperator := &operatorv1.ClusterOperator{}

	err := a.Client.Get(ctx, client.ObjectKey{Name: machineConfigClusterOperatorName}, mcOperator)
	if err != nil && errors.IsNotFound(err) {
		a.logger.Info(fmt.Sprintf(
			"ClusterOperator %s does not exist. Use daemonset for the node configuration",
			machineConfigClusterOperatorName,
		))

		serviceAccountName := "sdi-node-configurator"
		serviceAccount := &corev1.ServiceAccount{}
		err = a.Client.Get(ctx, client.ObjectKey{Name: serviceAccountName, Namespace: obs.Namespace}, serviceAccount)
		if err != nil && errors.IsNotFound(err) {
			serviceAccountAsset := assets.GetServiceAccountFromFile("manifests/node-configurator/serviceaccount.yaml")
			serviceAccountAsset.Namespace = obs.Namespace
			if err := a.Client.Create(ctx, serviceAccountAsset); err != nil {
				if err := a.Client.Get(ctx, client.ObjectKey{Name: a.Name, Namespace: a.Namespace}, obs); err != nil {
					a.Logger().Error(err, "Failed to re-fetch SDIObserver")
					return err
				}
				meta.SetStatusCondition(&obs.Status.SDINodeConfigStatus.Conditions, metav1.Condition{
					Type:               "OperatorDegraded",
					Status:             metav1.ConditionTrue,
					Reason:             sdiv1alpha1.ReasonOperandResourceFailed,
					LastTransitionTime: metav1.NewTime(time.Now()),
					Message:            fmt.Sprintf("unable to create operand service account: %s", err.Error()),
				})
				return utilerrors.NewAggregate([]error{err, a.Client.Status().Update(ctx, obs)})
			}
			ctrl.SetControllerReference(obs, serviceAccountAsset, a.Scheme)
		} else if err != nil {
			if err := a.Client.Get(ctx, client.ObjectKey{Name: a.Name, Namespace: a.Namespace}, obs); err != nil {
				a.Logger().Error(err, "Failed to re-fetch SDIObserver")
				return err
			}
			meta.SetStatusCondition(&obs.Status.SDINodeConfigStatus.Conditions, metav1.Condition{
				Type:               "OperatorDegraded",
				Status:             metav1.ConditionTrue,
				Reason:             sdiv1alpha1.ReasonResourceNotAvailable,
				LastTransitionTime: metav1.NewTime(time.Now()),
				Message:            fmt.Sprintf("unable to get operand service account: %s", err.Error()),
			})
			return utilerrors.NewAggregate([]error{err, a.Client.Status().Update(ctx, obs)})
		}

		imageStream := &openshiftv1.ImageStream{}
		imageStreamName := "ocp-tools"
		err = a.Client.Get(ctx, client.ObjectKey{Name: imageStreamName, Namespace: obs.Namespace}, imageStream)
		if err != nil && errors.IsNotFound(err) {
			imageStreamAsset := assets.GetImageStreamFromFile("manifests/node-configurator/imagestream.yaml")
			imageStreamAsset.Namespace = obs.Namespace
			if err := a.Client.Create(ctx, imageStreamAsset); err != nil {
				if err := a.Client.Get(ctx, client.ObjectKey{Name: a.Name, Namespace: a.Namespace}, obs); err != nil {
					a.Logger().Error(err, "Failed to re-fetch SDIObserver")
					return err
				}
				meta.SetStatusCondition(&obs.Status.SDINodeConfigStatus.Conditions, metav1.Condition{
					Type:               "OperatorDegraded",
					Status:             metav1.ConditionTrue,
					Reason:             sdiv1alpha1.ReasonOperandResourceFailed,
					LastTransitionTime: metav1.NewTime(time.Now()),
					Message:            fmt.Sprintf("unable to create operand image stream: %s", err.Error()),
				})
				return utilerrors.NewAggregate([]error{err, a.Client.Status().Update(ctx, obs)})
			}
			ctrl.SetControllerReference(obs, imageStreamAsset, a.Scheme)
		} else if err != nil {
			if err := a.Client.Get(ctx, client.ObjectKey{Name: a.Name, Namespace: a.Namespace}, obs); err != nil {
				a.Logger().Error(err, "Failed to re-fetch SDIObserver")
				return err
			}
			meta.SetStatusCondition(&obs.Status.SDINodeConfigStatus.Conditions, metav1.Condition{
				Type:               "OperatorDegraded",
				Status:             metav1.ConditionTrue,
				Reason:             sdiv1alpha1.ReasonResourceNotAvailable,
				LastTransitionTime: metav1.NewTime(time.Now()),
				Message:            fmt.Sprintf("unable to get operand image stream: %s", err.Error()),
			})
			return utilerrors.NewAggregate([]error{err, a.Client.Status().Update(ctx, obs)})
		}

		daemonset := &appsv1.DaemonSet{}
		daemonsetName := "sdi-node-configurator"
		err = a.Client.Get(ctx, client.ObjectKey{Name: daemonsetName, Namespace: obs.Namespace}, daemonset)
		if err != nil && errors.IsNotFound(err) {
			daemonsetAsset := assets.GetDaemonSetFromFile("manifests/node-configurator/daemonset.yaml")
			daemonsetAsset.Namespace = obs.Namespace
			if err := a.Client.Create(ctx, daemonsetAsset); err != nil {
				if err := a.Client.Get(ctx, client.ObjectKey{Name: a.Name, Namespace: a.Namespace}, obs); err != nil {
					a.Logger().Error(err, "Failed to re-fetch SDIObserver")
					return err
				}
				meta.SetStatusCondition(&obs.Status.SDINodeConfigStatus.Conditions, metav1.Condition{
					Type:               "OperatorDegraded",
					Status:             metav1.ConditionTrue,
					Reason:             sdiv1alpha1.ReasonOperandResourceFailed,
					LastTransitionTime: metav1.NewTime(time.Now()),
					Message:            fmt.Sprintf("unable to get operand daemonset: %s", err.Error()),
				})
				return utilerrors.NewAggregate([]error{err, a.Client.Status().Update(ctx, obs)})
			}
			ctrl.SetControllerReference(obs, daemonsetAsset, a.Scheme)
		} else if err != nil {
			if err := a.Client.Get(ctx, client.ObjectKey{Name: a.Name, Namespace: a.Namespace}, obs); err != nil {
				a.Logger().Error(err, "Failed to re-fetch SDIObserver")
				return err
			}
			meta.SetStatusCondition(&obs.Status.SDINodeConfigStatus.Conditions, metav1.Condition{
				Type:               "OperatorDegraded",
				Status:             metav1.ConditionTrue,
				Reason:             sdiv1alpha1.ReasonResourceNotAvailable,
				LastTransitionTime: metav1.NewTime(time.Now()),
				Message:            fmt.Sprintf("unable to get operand daemonset: %s", err.Error()),
			})
			return utilerrors.NewAggregate([]error{err, a.Client.Status().Update(ctx, obs)})
		}

		role := &rbacv1.Role{}
		roleName := "sdi-node-configurator"
		err = a.Client.Get(ctx, client.ObjectKey{Name: roleName, Namespace: obs.Namespace}, role)
		if err != nil && errors.IsNotFound(err) {
			roleAsset := assets.GetRoleFromFile("manifests/node-configurator/role.yaml")
			roleAsset.Namespace = obs.Namespace
			if err := a.Client.Create(ctx, roleAsset); err != nil {
				if err := a.Client.Get(ctx, client.ObjectKey{Name: a.Name, Namespace: a.Namespace}, obs); err != nil {
					a.Logger().Error(err, "Failed to re-fetch SDIObserver")
					return err
				}
				meta.SetStatusCondition(&obs.Status.SDINodeConfigStatus.Conditions, metav1.Condition{
					Type:               "OperatorDegraded",
					Status:             metav1.ConditionTrue,
					Reason:             sdiv1alpha1.ReasonOperandResourceFailed,
					LastTransitionTime: metav1.NewTime(time.Now()),
					Message:            fmt.Sprintf("unable to get operand role: %s", err.Error()),
				})
				return utilerrors.NewAggregate([]error{err, a.Client.Status().Update(ctx, obs)})
			}
			ctrl.SetControllerReference(obs, roleAsset, a.Scheme)
		} else if err != nil {
			if err := a.Client.Get(ctx, client.ObjectKey{Name: a.Name, Namespace: a.Namespace}, obs); err != nil {
				a.Logger().Error(err, "Failed to re-fetch SDIObserver")
				return err
			}
			meta.SetStatusCondition(&obs.Status.SDINodeConfigStatus.Conditions, metav1.Condition{
				Type:               "OperatorDegraded",
				Status:             metav1.ConditionTrue,
				Reason:             sdiv1alpha1.ReasonResourceNotAvailable,
				LastTransitionTime: metav1.NewTime(time.Now()),
				Message:            fmt.Sprintf("unable to get operand role: %s", err.Error()),
			})
			return utilerrors.NewAggregate([]error{err, a.Client.Status().Update(ctx, obs)})
		}

		roleBinding := &rbacv1.RoleBinding{}
		roleBindingName := "sdi-node-configurator"
		err = a.Client.Get(ctx, client.ObjectKey{Name: roleBindingName, Namespace: obs.Namespace}, roleBinding)
		if err != nil && errors.IsNotFound(err) {
			roleBindingAsset := assets.GetRoleBindingFromFile("manifests/node-configurator/rolebinding.yaml")
			roleBindingAsset.Namespace = obs.Namespace
			if err := a.Client.Create(ctx, roleBindingAsset); err != nil {
				if err := a.Client.Get(ctx, client.ObjectKey{Name: a.Name, Namespace: a.Namespace}, obs); err != nil {
					a.Logger().Error(err, "Failed to re-fetch SDIObserver")
					return err
				}
				meta.SetStatusCondition(&obs.Status.SDINodeConfigStatus.Conditions, metav1.Condition{
					Type:               "OperatorDegraded",
					Status:             metav1.ConditionTrue,
					Reason:             sdiv1alpha1.ReasonOperandResourceFailed,
					LastTransitionTime: metav1.NewTime(time.Now()),
					Message:            fmt.Sprintf("unable to get operand role binding: %s", err.Error()),
				})
				return utilerrors.NewAggregate([]error{err, a.Client.Status().Update(ctx, obs)})
			}
			ctrl.SetControllerReference(obs, roleBindingAsset, a.Scheme)
		} else if err != nil {
			if err := a.Client.Get(ctx, client.ObjectKey{Name: a.Name, Namespace: a.Namespace}, obs); err != nil {
				a.Logger().Error(err, "Failed to re-fetch SDIObserver")
				return err
			}
			meta.SetStatusCondition(&obs.Status.SDINodeConfigStatus.Conditions, metav1.Condition{
				Type:               "OperatorDegraded",
				Status:             metav1.ConditionTrue,
				Reason:             sdiv1alpha1.ReasonResourceNotAvailable,
				LastTransitionTime: metav1.NewTime(time.Now()),
				Message:            fmt.Sprintf("unable to get operand role binding: %s", err.Error()),
			})
			return utilerrors.NewAggregate([]error{err, a.Client.Status().Update(ctx, obs)})
		}
	} else if err != nil {
		if err := a.Client.Get(ctx, client.ObjectKey{Name: a.Name, Namespace: a.Namespace}, obs); err != nil {
			a.Logger().Error(err, "Failed to re-fetch SDIObserver")
			return err
		}
		meta.SetStatusCondition(&obs.Status.SDINodeConfigStatus.Conditions, metav1.Condition{
			Type:               "OperatorDegraded",
			Status:             metav1.ConditionTrue,
			Reason:             sdiv1alpha1.ReasonResourceNotAvailable,
			LastTransitionTime: metav1.NewTime(time.Now()),
			Message:            fmt.Sprintf("unable to get operand machine config cluster operator: %s", err.Error()),
		})
		return utilerrors.NewAggregate([]error{err, a.Client.Status().Update(ctx, obs)})
	} else {

		a.logger.Info(fmt.Sprintf(
			"ClusterOperator %s exists. Use machineConfig and ContainerRuntimeConfig for the node configuration",
			machineConfigClusterOperatorName,
		))

		kernalModuleLoadMachineConfig := &configv1.MachineConfig{}

		machineConfigName := "75-worker-sap-data-intelligence"
		err = a.Client.Get(ctx, client.ObjectKey{Name: machineConfigName}, kernalModuleLoadMachineConfig)
		if err != nil && errors.IsNotFound(err) {
			kernalModuleLoadMachineConfigAsset := assets.GetMachineConfigFromFile("manifests/machineconfiguration/machineconfig-sdi-load-kernal-modules.yaml")
			a.logger.Info(fmt.Sprintf("MachineConfig %s does not exist", kernalModuleLoadMachineConfigAsset.Name))
			if err := a.Client.Create(ctx, kernalModuleLoadMachineConfigAsset); err != nil {
				if err := a.Client.Get(ctx, client.ObjectKey{Name: a.Name, Namespace: a.Namespace}, obs); err != nil {
					a.Logger().Error(err, "Failed to re-fetch SDIObserver")
					return err
				}
				meta.SetStatusCondition(&obs.Status.SDINodeConfigStatus.Conditions, metav1.Condition{
					Type:               "OperatorDegraded",
					Status:             metav1.ConditionTrue,
					Reason:             sdiv1alpha1.ReasonOperandResourceFailed,
					LastTransitionTime: metav1.NewTime(time.Now()),
					Message:            fmt.Sprintf("unable to get operand machine config: %s", err.Error()),
				})
				return utilerrors.NewAggregate([]error{err, a.Client.Status().Update(ctx, obs)})
			}
		} else if err != nil {
			if err := a.Client.Get(ctx, client.ObjectKey{Name: a.Name, Namespace: a.Namespace}, obs); err != nil {
				a.Logger().Error(err, "Failed to re-fetch SDIObserver")
				return err
			}
			meta.SetStatusCondition(&obs.Status.SDINodeConfigStatus.Conditions, metav1.Condition{
				Type:               "OperatorDegraded",
				Status:             metav1.ConditionTrue,
				Reason:             sdiv1alpha1.ReasonResourceNotAvailable,
				LastTransitionTime: metav1.NewTime(time.Now()),
				Message:            fmt.Sprintf("unable to get operand machine config: %s", err.Error()),
			})
			return utilerrors.NewAggregate([]error{err, a.Client.Status().Update(ctx, obs)})
		} else {
			a.logger.Info(fmt.Sprintf("MachineConfig %s already exists. Do nothing", machineConfigName))
		}

		kubeletConfigName := "sdi-pids-limit"
		kubeletConfig := &configv1.KubeletConfig{}

		err = a.Client.Get(ctx, client.ObjectKey{Name: kubeletConfigName}, kubeletConfig)
		if err != nil && errors.IsNotFound(err) {
			kubeletConfigAsset := assets.GetKubeletConfigFromFile("manifests/machineconfiguration/kubeletconfig-sdi-pid-limit.yaml")
			a.logger.Info(fmt.Sprintf("KubeletConfig %s does not exist. Create it.", kubeletConfigAsset.Name))
			if err := a.Client.Create(ctx, kubeletConfigAsset); err != nil {
				if err := a.Client.Get(ctx, client.ObjectKey{Name: a.Name, Namespace: a.Namespace}, obs); err != nil {
					a.Logger().Error(err, "Failed to re-fetch SDIObserver")
					return err
				}
				meta.SetStatusCondition(&obs.Status.SDINodeConfigStatus.Conditions, metav1.Condition{
					Type:               "OperatorDegraded",
					Status:             metav1.ConditionTrue,
					Reason:             sdiv1alpha1.ReasonOperandResourceFailed,
					LastTransitionTime: metav1.NewTime(time.Now()),
					Message:            fmt.Sprintf("unable to get operand machine config: %s", err.Error()),
				})
				return utilerrors.NewAggregate([]error{err, a.Client.Status().Update(ctx, obs)})
			}
		} else if err != nil {
			if err := a.Client.Get(ctx, client.ObjectKey{Name: a.Name, Namespace: a.Namespace}, obs); err != nil {
				a.Logger().Error(err, "Failed to re-fetch SDIObserver")
				return err
			}
			meta.SetStatusCondition(&obs.Status.SDINodeConfigStatus.Conditions, metav1.Condition{
				Type:               "OperatorDegraded",
				Status:             metav1.ConditionTrue,
				Reason:             sdiv1alpha1.ReasonResourceNotAvailable,
				LastTransitionTime: metav1.NewTime(time.Now()),
				Message:            fmt.Sprintf("unable to get operand machine config: %s", err.Error()),
			})
			return utilerrors.NewAggregate([]error{err, a.Client.Status().Update(ctx, obs)})
		} else {
			a.logger.Info(fmt.Sprintf("KubeletConfig %s exists. Do nothing", kubeletConfigName))
		}

		obsoleteContainerRuntimeConfig := &configv1.ContainerRuntimeConfig{}
		obsoleteContainerRuntimeConfigName := "sdi-pids-limit"
		err = a.Client.Get(ctx, client.ObjectKey{Name: obsoleteContainerRuntimeConfigName}, obsoleteContainerRuntimeConfig)
		if err != nil && errors.IsNotFound(err) {
			a.logger.Info(fmt.Sprintf("ContainerRuntimeConfig %s does not exist. No need to make the cleanup.", obsoleteContainerRuntimeConfigName))
		} else if err != nil {
			return err
		} else {
			obsoleteContainerRuntimeConfigAsset := assets.GetContainerRuntimeConfigFromFile("manifests/machineconfiguration/obsolete-containerruntimeconfig-sdi-pid-limit.yaml")
			a.logger.Info(fmt.Sprintf("ContainerRuntimeConfig %s exists. Make the cleanup", obsoleteContainerRuntimeConfigName))
			if err := a.Client.Delete(ctx, obsoleteContainerRuntimeConfigAsset); err != nil {
				return err
			}
		}

		machineConfigPoolName := "sdi"
		machineConfigPool := &configv1.MachineConfigPool{}

		err = a.Client.Get(ctx, client.ObjectKey{Name: machineConfigPoolName}, machineConfigPool)
		if err != nil && errors.IsNotFound(err) {
			machineConfigPoolAsset := assets.GetMachineConfigPoolFromFile("manifests/machineconfiguration/machineconfigpool-sdi.yaml")
			a.logger.Info(fmt.Sprintf("MachineConfigPool %s does not exist", machineConfigPoolAsset.Name))
			if err := a.Client.Create(ctx, machineConfigPoolAsset); err != nil {
				return err
			}
		} else if err != nil {
			if err := a.Client.Get(ctx, client.ObjectKey{Name: a.Name, Namespace: a.Namespace}, obs); err != nil {
				a.Logger().Error(err, "Failed to re-fetch SDIObserver")
				return err
			}
			meta.SetStatusCondition(&obs.Status.SDINodeConfigStatus.Conditions, metav1.Condition{
				Type:               "OperatorDegraded",
				Status:             metav1.ConditionTrue,
				Reason:             sdiv1alpha1.ReasonResourceNotAvailable,
				LastTransitionTime: metav1.NewTime(time.Now()),
				Message:            fmt.Sprintf("unable to get operand machine config pool: %s", err.Error()),
			})
			return utilerrors.NewAggregate([]error{err, a.Client.Status().Update(ctx, obs)})
		} else {
			a.logger.Info(fmt.Sprintf("MachineConfigPool %s already exists. Do nothing", machineConfigPoolName))
		}
	}

	if err := a.Client.Get(ctx, client.ObjectKey{Name: a.Name, Namespace: a.Namespace}, obs); err != nil {
		a.Logger().Error(err, "Failed to re-fetch SDIObserver")
		return err
	}
	meta.SetStatusCondition(&obs.Status.SDINodeConfigStatus.Conditions, metav1.Condition{
		Type:               "OperatorDegraded",
		Status:             metav1.ConditionFalse,
		Reason:             sdiv1alpha1.ReasonSucceeded,
		LastTransitionTime: metav1.NewTime(time.Now()),
		Message:            "operator successfully reconciling",
	})
	return a.Client.Status().Update(ctx, obs)
}
