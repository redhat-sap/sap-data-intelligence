#!/usr/bin/bash
 
# CHECK OCP (Note Files may change after update)
 
for worker in `oc get nodes|awk '/worker/{print $1}'`; do
  echo "Checking node $worker ------------------------------------------------------------------------------"
  # Check for additional kernelmodules
  oc debug node/$worker -- chroot /host cat /etc/crio/crio.conf.d/90-default-capabilities  2> /dev/null
  # Check for additional kernelmodules
  oc debug node/$worker -- chroot /host cat /etc/modules-load.d/sdi-dependencies.conf 2> /dev/null
  # check for module load service
  oc debug node/$worker -- chroot /host systemctl status sdi-modules-load.service 2> /dev/null
  # check for pidsLimit:
  oc debug node/$worker -- chroot /host cat /etc/crio/crio.conf.d/01-ctrcfg-pidsLimit
  echo "--------------------------------------------------------------------------------------------------------"
done
