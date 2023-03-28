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

	} else if err != nil {
		return err
	}

	a.logger.Info(fmt.Sprintf(
		"ClusterOperator %s exists. Use machineConfig and ContainerRuntimeConfig for the node configuration",
		machineConfigClusterOperatorName,
	))

	kernalModuleLoadMachineConfigAsset := assets.GetMachineConfigFromFile("manifests/machineconfig-sdi-load-kernal-modules.yaml")

	kernalModuleLoadMachineConfig := &configv1.MachineConfig{
		ObjectMeta: metav1.ObjectMeta{
			Name: kernalModuleLoadMachineConfigAsset.Name,
		},
	}

	err = a.Client.Get(ctx, client.ObjectKey{Name: kernalModuleLoadMachineConfigAsset.Name}, kernalModuleLoadMachineConfig)
	if err != nil && errors.IsNotFound(err) {
		a.logger.Info(fmt.Sprintf("MachineConfig %s does not exist", kernalModuleLoadMachineConfigAsset.Name))
		a.Client.Create(ctx, kernalModuleLoadMachineConfigAsset)
	} else if err != nil {
		return err
	}

	containerRuntimeConfigAsset := assets.GetContainerRuntimeConfigFromFile("manifests/containerruntimeconfig-sdi-pid-limit.yaml")

	containerRuntimeConfig := &configv1.ContainerRuntimeConfig{
		ObjectMeta: metav1.ObjectMeta{
			Name: containerRuntimeConfigAsset.Name,
		},
	}

	err = a.Client.Get(ctx, client.ObjectKey{Name: containerRuntimeConfigAsset.Name}, containerRuntimeConfig)
	if err != nil && errors.IsNotFound(err) {
		a.logger.Info(fmt.Sprintf("ContainerRuntimeConfig %s does not exist", containerRuntimeConfigAsset.Name))
		a.Client.Create(ctx, containerRuntimeConfigAsset)
	} else if err != nil {
		return err
	}

	return nil
}
