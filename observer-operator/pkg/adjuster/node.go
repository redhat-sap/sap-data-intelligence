package adjuster

import (
	"context"
	"fmt"
	operatorv1 "github.com/openshift/api/config/v1"
	sdiv1alpha1 "github.com/redhat-sap/sap-data-intelligence/observer-operator/api/v1alpha1"
)

func (a *Adjuster) AdjustSDINodes(obs *sdiv1alpha1.SDIObserver, ctx context.Context) error {

	coList := &operatorv1.ClusterOperatorList{}
	err := a.Client.List(context.Background(), coList)
	if err != nil {
		return err
	}
	machineConfigClusterOperatorName := "machine-config"
	machineConfigExist := false
	for _, co := range coList.Items {

		if co.Name == machineConfigClusterOperatorName {
			machineConfigExist = true
			break
		}
	}

	if machineConfigExist {
		a.logger.Info(fmt.Sprintf(
			"ClusterOperator %s exists. Use machineConfig and ContainerRuntimeConfig for the node configuration",
			machineConfigClusterOperatorName,
		))
	} else {
		a.logger.Info(fmt.Sprintf(
			"ClusterOperator %s exists. Use daemonset for the node configuration",
			machineConfigClusterOperatorName,
		))
	}

	if err != nil {
		return err
	}

	return nil
}
