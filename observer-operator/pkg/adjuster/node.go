package adjuster

import (
	"context"
	"fmt"
	operatorv1 "github.com/openshift/api/config/v1"
	configv1 "github.com/openshift/machine-config-operator/pkg/apis/machineconfiguration.openshift.io/v1"
	sdiv1alpha1 "github.com/redhat-sap/sap-data-intelligence/observer-operator/api/v1alpha1"
	"github.com/redhat-sap/sap-data-intelligence/observer-operator/assets"
	"k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

func (a *Adjuster) AdjustSDINodes(obs *sdiv1alpha1.SDIObserver, ctx context.Context) error {
	machineConfigClusterOperatorName := "machine-config"

	mcOperator := &operatorv1.ClusterOperator{
		ObjectMeta: metav1.ObjectMeta{
			Name: "machineConfigClusterOperatorName",
		},
	}
	err := a.Client.Get(ctx, client.ObjectKey{Name: machineConfigClusterOperatorName}, mcOperator)

	if err != nil && errors.IsNotFound(err) {
		a.logger.Info(fmt.Sprintf(
			"ClusterOperator %s does not exist. Use daemonset for the node configuration",
			machineConfigClusterOperatorName,
		))

		serviceAccountAsset := assets.GetServiceAccountFromFile("manifests/node-configurator/serviceaccount.yaml")

		err = a.Client.Get(ctx, client.ObjectKey{Name: serviceAccountAsset.Name}, serviceAccountAsset)
		if err != nil && errors.IsNotFound(err) {
			if err := a.Client.Create(ctx, serviceAccountAsset); err != nil {
				return err
			}
			ctrl.SetControllerReference(obs, serviceAccountAsset, a.Scheme)
		} else if err != nil {
			return err
		}

		imageStreamAsset := assets.GetImageStreamFromFile("manifests/node-configurator/imagestream.yaml")

		err = a.Client.Get(ctx, client.ObjectKey{Name: imageStreamAsset.Name}, imageStreamAsset)
		if err != nil && errors.IsNotFound(err) {
			if err := a.Client.Create(ctx, imageStreamAsset); err != nil {
				return err
			}
			ctrl.SetControllerReference(obs, imageStreamAsset, a.Scheme)
		} else if err != nil {
			return err
		}

		daemonsetAsset := assets.GetDaemonSetFromFile("manifests/node-configurator/daemonset.yaml")

		err = a.Client.Get(ctx, client.ObjectKey{Name: daemonsetAsset.Name}, daemonsetAsset)
		if err != nil && errors.IsNotFound(err) {
			if err := a.Client.Create(ctx, daemonsetAsset); err != nil {
				return err
			}
			ctrl.SetControllerReference(obs, daemonsetAsset, a.Scheme)
		} else if err != nil {
			return err
		}

	} else if err != nil {
		return err
	}

	a.logger.Info(fmt.Sprintf(
		"ClusterOperator %s exists. Use machineConfig and ContainerRuntimeConfig for the node configuration",
		machineConfigClusterOperatorName,
	))

	kernalModuleLoadMachineConfigAsset := assets.GetMachineConfigFromFile("manifests/machineconfiguration/machineconfig-sdi-load-kernal-modules.yaml")

	kernalModuleLoadMachineConfig := &configv1.MachineConfig{
		ObjectMeta: metav1.ObjectMeta{
			Name: kernalModuleLoadMachineConfigAsset.Name,
		},
	}

	err = a.Client.Get(ctx, client.ObjectKey{Name: kernalModuleLoadMachineConfigAsset.Name}, kernalModuleLoadMachineConfig)
	if err != nil && errors.IsNotFound(err) {
		a.logger.Info(fmt.Sprintf("MachineConfig %s does not exist", kernalModuleLoadMachineConfigAsset.Name))
		if err := a.Client.Create(ctx, kernalModuleLoadMachineConfigAsset); err != nil {
			return err
		}
	} else if err != nil {
		return err
	} else {
		a.logger.Info(fmt.Sprintf("MachineConfig %s already exists. Do nothing", kernalModuleLoadMachineConfigAsset.Name))
	}

	kubeletConfigAsset := assets.GetKubeletConfigFromFile("manifests/machineconfiguration/kubeletconfig-sdi-pid-limit.yaml")

	kubeletConfig := &configv1.KubeletConfig{
		ObjectMeta: metav1.ObjectMeta{
			Name: kubeletConfigAsset.Name,
		},
	}

	err = a.Client.Get(ctx, client.ObjectKey{Name: kubeletConfigAsset.Name}, kubeletConfig)
	if err != nil && errors.IsNotFound(err) {
		a.logger.Info(fmt.Sprintf("KubeletConfig %s does not exist. Create it.", kubeletConfigAsset.Name))
		if err := a.Client.Create(ctx, kubeletConfigAsset); err != nil {
			return err
		}
	} else if err != nil {
		return err
	} else {
		a.logger.Info(fmt.Sprintf("KubeletConfig %s exists. Do nothing", kubeletConfigAsset.Name))
	}

	containerRuntimeConfigAsset := assets.GetKubeletConfigFromFile("manifests/machineconfiguration/obsolete-containerruntimeconfig-sdi-pid-limit.yaml")

	containerRuntimeConfig := &configv1.ContainerRuntimeConfig{
		ObjectMeta: metav1.ObjectMeta{
			Name: containerRuntimeConfigAsset.Name,
		},
	}

	err = a.Client.Get(ctx, client.ObjectKey{Name: containerRuntimeConfigAsset.Name}, containerRuntimeConfig)
	if err != nil && errors.IsNotFound(err) {
		a.logger.Info(fmt.Sprintf("ContainerRuntimeConfig %s does not exist. No need to make the cleanup.", containerRuntimeConfigAsset.Name))
	} else if err != nil {
		return err
	} else {
		a.logger.Info(fmt.Sprintf("ContainerRuntimeConfig %s exists. Make the cleanup", containerRuntimeConfigAsset.Name))
		if err := a.Client.Delete(ctx, kubeletConfigAsset); err != nil {
			return err
		}
	}

	machineConfigPoolAsset := assets.GetMachineConfigPoolFromFile("manifests/machineconfiguration/machineconfigpool-sdi.yaml")

	machineConfigPool := &configv1.MachineConfigPool{
		ObjectMeta: metav1.ObjectMeta{
			Name: machineConfigPoolAsset.Name,
		},
	}

	err = a.Client.Get(ctx, client.ObjectKey{Name: machineConfigPoolAsset.Name}, machineConfigPool)
	if err != nil && errors.IsNotFound(err) {
		a.logger.Info(fmt.Sprintf("MachineConfigPool %s does not exist", machineConfigPoolAsset.Name))
		if err := a.Client.Create(ctx, machineConfigPoolAsset); err != nil {
			return err
		}
	} else if err != nil {
		return err
	} else {
		a.logger.Info(fmt.Sprintf("MachineConfigPool %s already exists. Do nothing", machineConfigPoolAsset.Name))
	}

	return nil
}
