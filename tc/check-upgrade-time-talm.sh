#!/bin/bash

# label the node to apply the policy (ahead of time!)
#oc --kubeconfig ${KUBECONFIG_HUB} label managedcluster ${SPOKE} vzto="${spoke_version}"


# 1) Set variables
SPOKE="zt-sno1"
SPOKE_IP="2600:52:7:59::100"
VERSION_LIST='4.10.64'


# 2) Set KUBECONFIG for hub and spoke
export KUBECONFIG_SPOKE=/root/spoke/${SPOKE}/kubeconfig-${SPOKE}.yaml
export KUBECONFIG_HUB=/root/hub/02_deploy-scripts/ipv6-cluster/auth/kubeconfig


# 3) Start upgrade procedure
for spoke_version in ${VERSION_LIST}; do
  start=$(date)

  echo ""
  echo "====="
  echo "[INFO] Upgrade towards ${spoke_version} started at: ${start}"

  # 3.1) create CGU upgrade object
  # replace spoke_version dots to create CGU automatically depending on the target version
  spoke_version_beauty=$(echo "${spoke_version}" | tr '.' '-')

  cat <<EOF | oc --kubeconfig ${KUBECONFIG_HUB} apply -f -
---
apiVersion: ran.openshift.io/v1alpha1
kind: ClusterGroupUpgrade
metadata:
  name: pu-${spoke_version_beauty}
  namespace: ztp-eric-vdu-mb-policies
spec:
  preCaching: true
  backup: false
  clusters:
    - ${SPOKE}
  enable: true
  managedPolicies:
    - pu-${spoke_version_beauty}-config-updates
  remediationStrategy:
    maxConcurrency: 2
    timeout: 240
EOF

  # 3.2) watch upgrade procedure
  while true;
  do

    if ! nc -zv ${SPOKE_IP} 6443 > /dev/null 2>&1; then
      sleep 30   # -> wait a bit before checking

      # 3.2.1) watch node for reboots
      if ! ping -c 3 ${SPOKE_IP} > /dev/null 2>&1; then
        reboot_start=$(date)
        echo "[INFO] Node started a reboot at ${reboot_start}"
        while ! ping -c 3 ${SPOKE_IP} > /dev/null 2>&1; do
          sleep 10
          reboot_stop=$(date)
        done
        echo "[INFO] Node finished the reboot at ${reboot_stop}"
      fi

      # 3.2.2) watch api server status
      if ! nc -zv ${SPOKE_IP} 6443 > /dev/null 2>&1; then
        api_server_start=$(date)
        echo "[INFO] API server went down at ${api_server_start}"
        while ! nc -zv ${SPOKE_IP} 6443 > /dev/null 2>&1; do
          sleep 10
          reboot_stop=$(date)
        done
        echo "[INFO] API server is up again at ${reboot_stop}"
      fi

      # 3.2.3) watch httpd deployment
      if ! [ "$(curl -o /dev/null -s -w "%{http_code}" httpd-default.apps.${SPOKE}.inbound.vz.bos2.lab)" -eq 200 ]; then
        httpd_start=$(date)
        echo "[INFO] HTTPD server went down at ${httpd_start}"
        while ! [ "$(curl -o /dev/null -s -w "%{http_code}" httpd-default.apps.${SPOKE}.inbound.vz.bos2.lab)" -eq 200 ]; do
          sleep 10
          httpd_stop=$(date)
        done
        echo "[INFO] HTTPD server is up again at ${httpd_stop}"
      fi

      # TODO: 3.2.4) watch for pre-caching job
      # 1. watch pre-caching time
      # 2. compute the number of images downloaded
    fi

    # 3.2.5) watch CVO for cluster upgrades
    cvo_status=$(oc get --kubeconfig ${KUBECONFIG_SPOKE} clusterversion version --no-headers | awk -v version="${spoke_version}" '{ if($2==version) print "Upgrade finished"; else print}'); echo "[INFO] ($(date)): ${cvo_status}"
    if [ "${cvo_status}" = "Upgrade finished" ]
    then
      cvo_stop=$(date)
      break
    fi

    sleep 25
  done

  echo "[INFO] Upgrade to version ${spoke_version} started at ${start} and finished at ${cvo_stop}"
  echo "====="
  echo ""

  sleep 25
done

echo ""
echo "Finished emulation"
