package adjuster

import (
	"context"
	"fmt"
	operatorv1 "github.com/openshift/api/config/v1"
	configv1 "github.com/openshift/machine-config-operator/pkg/apis/machineconfiguration.openshift.io/v1"
	sdiv1alpha1 "github.com/redhat-sap/sap-data-intelligence/observer-operator/api/v1alpha1"
	"github.com/redhat-sap/sap-data-intelligence/observer-operator/assets"
	"k8s.io/apimachinery/pkg/api/errors"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

func (a *Adjuster) AdjustSDINodes(obs *sdiv1alpha1.SDIObserver, ctx context.Context) error {
	// Check for "machine-config" ClusterOperator
	if err := a.checkClusterOperator(ctx, "machine-config"); err != nil {
		if errors.IsNotFound(err) {
			a.logger.Info("ClusterOperator machine-config does not exist. Using daemonset for the node configuration.")
			return a.createDaemonSetResources(ctx, obs)
		}
		return fmt.Errorf("unable to get operand machine config cluster operator: %w", err)
	}
	a.logger.Info("ClusterOperator machine-config exists. Using MachineConfig and KubeletConfig.")

	if err := a.ensureMachineConfig(ctx); err != nil {
		return err
	}
	if err := a.ensureKubeletConfig(ctx); err != nil {
		return err
	}
	if err := a.ensureObsoleteContainerRuntimeConfig(ctx); err != nil {
		return err
	}
	if err := a.ensureMachineConfigPool(ctx); err != nil {
		return err
	}

	a.logger.Info("Operator successfully reconciling")
	return nil
}

func (a *Adjuster) checkClusterOperator(ctx context.Context, name string) error {
	if err := a.Client.Get(ctx, client.ObjectKey{Name: name}, &operatorv1.ClusterOperator{}); err != nil {
		return fmt.Errorf("failed to get ClusterOperator %s: %w", name, err)
	}
	return nil
}

func (a *Adjuster) createDaemonSetResources(ctx context.Context, obs *sdiv1alpha1.SDIObserver) error {
	assetsToCheck := []struct {
		Name      string
		Namespace string
		GetAsset  func() client.Object
	}{
		{"sdi-node-configurator", obs.Namespace, assets.GetServiceAccountFromFile("manifests/node-configurator/serviceaccount.yaml")},
		{"ocp-tools", obs.Namespace, assets.GetImageStreamFromFile("manifests/node-configurator/imagestream.yaml")},
		{"sdi-node-configurator", obs.Namespace, assets.GetDaemonSetFromFile("manifests/node-configurator/daemonset.yaml")},
		{"sdi-node-configurator", obs.Namespace, assets.GetRoleFromFile("manifests/node-configurator/role.yaml")},
		{"sdi-node-configurator", obs.Namespace, assets.GetRoleBindingFromFile("manifests/node-configurator/rolebinding.yaml")},
	}

	for _, asset := range assetsToCheck {
		if err := a.ensureResource(ctx, obs, asset.Name, asset.Namespace, asset.GetAsset); err != nil {
			return err
		}
	}
	return nil
}

func (a *Adjuster) ensureResource(ctx context.Context, obs *sdiv1alpha1.SDIObserver, name, namespace string, getAsset func() client.Object) error {
	resource := getAsset()
	resourceGVK := resource.GetObjectKind().GroupVersionKind().Kind
	err := a.Client.Get(ctx, client.ObjectKey{Name: name, Namespace: namespace}, resource)
	if err != nil && errors.IsNotFound(err) {
		a.logger.Info(fmt.Sprintf("%s %s does not exist, creating it.", resourceGVK, name))
		if err := a.Client.Create(ctx, resource); err != nil {
			return fmt.Errorf("unable to create operand resource %s: %w", name, err)
		}
		ctrl.SetControllerReference(obs, resource, a.Scheme)
	} else if err != nil {
		return fmt.Errorf("unable to get operand resource %s: %w", name, err)
	}
	return nil
}

func (a *Adjuster) ensureMachineConfig(ctx context.Context) error {
	return a.ensureSpecificMachineConfig(ctx, "75-worker-sap-data-intelligence", assets.GetMachineConfigFromFile("manifests/machineconfiguration/machineconfig-sdi-load-kernel-modules.yaml"))
}

func (a *Adjuster) ensureKubeletConfig(ctx context.Context) error {
	return a.ensureSpecificKubeletConfig(ctx, "sdi-pids-limit", assets.GetKubeletConfigFromFile("manifests/machineconfiguration/kubeletconfig-sdi-pid-limit.yaml"))
}

func (a *Adjuster) ensureSpecificMachineConfig(ctx context.Context, name string, getAsset func() client.Object) error {
	config := &configv1.MachineConfig{}
	err := a.Client.Get(ctx, client.ObjectKey{Name: name}, config)
	if err != nil && errors.IsNotFound(err) {
		a.logger.Info(fmt.Sprintf("%s %s does not exist, creating it.", config.GetObjectKind().GroupVersionKind().Kind, name))
		if err := a.Client.Create(ctx, getAsset()); err != nil {
			return fmt.Errorf("unable to create operand %s: %w", name, err)
		}
	} else if err != nil {
		return fmt.Errorf("unable to get operand %s: %w", name, err)
	}
	return nil
}

func (a *Adjuster) ensureSpecificKubeletConfig(ctx context.Context, name string, getAsset func() client.Object) error {
	config := &configv1.KubeletConfig{}
	err := a.Client.Get(ctx, client.ObjectKey{Name: name}, config)
	if err != nil && errors.IsNotFound(err) {
		a.logger.Info(fmt.Sprintf("%s %s does not exist, creating it.", config.GetObjectKind().GroupVersionKind().Kind, name))
		if err := a.Client.Create(ctx, getAsset()); err != nil {
			return fmt.Errorf("unable to create operand %s: %w", name, err)
		}
	} else if err != nil {
		return fmt.Errorf("unable to get operand %s: %w", name, err)
	}
	return nil
}

func (a *Adjuster) ensureObsoleteContainerRuntimeConfig(ctx context.Context) error {
	// Check and delete obsolete ContainerRuntimeConfig if it exists
	obsoleteConfig := &configv1.ContainerRuntimeConfig{}
	obsoleteConfigName := "sdi-pids-limit"
	err := a.Client.Get(ctx, client.ObjectKey{Name: obsoleteConfigName}, obsoleteConfig)
	if err != nil && errors.IsNotFound(err) {
		a.logger.Info(fmt.Sprintf("ContainerRuntimeConfig %s does not exist. No cleanup needed.", obsoleteConfigName))
		return nil
	} else if err != nil {
		return err
	}

	a.logger.Info(fmt.Sprintf("ContainerRuntimeConfig %s exists. Performing cleanup.", obsoleteConfigName))
	if err := a.Client.Delete(ctx, obsoleteConfig); err != nil {
		return err
	}
	return nil
}

func (a *Adjuster) ensureMachineConfigPool(ctx context.Context) error {
	pool := &configv1.MachineConfigPool{}
	poolName := "sdi"
	err := a.Client.Get(ctx, client.ObjectKey{Name: poolName}, pool)
	if err != nil && errors.IsNotFound(err) {
		a.logger.Info(fmt.Sprintf("MachineConfigPool %s does not exist, creating it.", poolName))
		poolAsset := assets.GetMachineConfigPoolFromFile("manifests/machineconfiguration/machineconfigpool-sdi.yaml")
		if err := a.Client.Create(ctx, poolAsset); err != nil {
			return err
		}
	} else if err != nil {
		return fmt.Errorf("unable to get operand machine config pool %s: %w", poolName, err)
	}
	return nil
}
