#!/bin/bash


# 1) Set KUBECONFIG for spoke
export KUBECONFIG=/root/spoke/zt-sno1/kubeconfig-zt-sno1.yaml


# 2) Set variables
SPOKE="zt-sno1"
SPOKE_IP="2600:52:7:59::100"
VERSION_LIST='4.11.45 4.12.26 4.13.6 4.14.0-ec.3'


# 3) Start upgrade procedure
for spoke_version in ${VERSION_LIST}; do
  start=$(date)

  echo ""
  echo "====="
  echo "[INFO] Upgrade towards ${spoke_version} started at: ${start}"

  # 3.1) set upgrade channel
  case "${spoke_version}" in
    "4.10."* | "4.11."* | "4.12."*) oc adm upgrade channel eus-4.12 ;;
    "4.13."*) oc adm upgrade channel fast-4.13 ;;
    "4.14."*) oc adm upgrade channel candidate-4.14 ;;
  esac

  # 3.2) pause machine config pools (to avoid extra reboots)
  oc patch mcp/master --patch '{"spec":{"paused":true}}' --type=merge
  oc patch mcp/worker --patch '{"spec":{"paused":true}}' --type=merge

  # 3.3) trigger upgrade operation
    if [ "${spoke_version}" == '4.14.0-ec.3' ]; then
      oc adm upgrade --force --allow-explicit-upgrade --to-image jumphost.inbound.vz.bos2.lab:8443/ocp4/openshift/release-images:4.14.0-ec.3-x86_64
    else
      oc adm upgrade --force --to="${spoke_version}"
    fi

  # 3.4) watch upgrade procedure
  while true;
  do

    if ! nc -zv ${SPOKE_IP} 6443 > /dev/null 2>&1; then
      sleep 30   # -> wait a bit before checking

      # 3.4.1) watch node for reboots
      if ! ping -c 3 ${SPOKE_IP} > /dev/null 2>&1; then
        reboot_start=$(date)
        echo "[INFO] Node started a reboot at ${reboot_start}"
        while ! ping -c 3 ${SPOKE_IP} > /dev/null 2>&1; do
          sleep 10
          reboot_stop=$(date)
        done
        echo "[INFO] Node finished the reboot at ${reboot_stop}"
      fi

      # 3.4.2) watch api server status
      if ! nc -zv ${SPOKE_IP} 6443 > /dev/null 2>&1; then
        api_server_start=$(date)
        echo "[INFO] API server went down at ${api_server_start}"
        while ! nc -zv ${SPOKE_IP} 6443 > /dev/null 2>&1; do
          sleep 10
          reboot_stop=$(date)
        done
        echo "[INFO] API server is up again at ${reboot_stop}"
      fi

      # 3.4.3) watch httpd deployment
      if ! [ "$(curl -o /dev/null -s -w "%{http_code}" httpd-default.apps.${SPOKE}.inbound.vz.bos2.lab)" -eq 200 ]; then
        httpd_start=$(date)
        echo "[INFO] HTTPD server went down at ${httpd_start}"
        while ! [ "$(curl -o /dev/null -s -w "%{http_code}" httpd-default.apps.${SPOKE}.inbound.vz.bos2.lab)" -eq 200 ]; do
          sleep 10
          httpd_stop=$(date)
        done
        echo "[INFO] HTTPD server is up again at ${httpd_stop}"
      fi
    fi

    # 3.4.4) add label to allow upgrade to continue
    oc label mcp/master operator.machineconfiguration.openshift.io/required-for-upgrade- > /dev/null 2>&1

    # 3.4.5) watch CVO for cluster upgrades
    cvo_status=$(oc get clusterversion version --no-headers | awk -v version="${spoke_version}" '{ if($2==version) print "Upgrade finished"; else print}'); echo "[INFO] ($(date)): ${cvo_status}"
    if [ "${cvo_status}" = "Upgrade finished" ]
    then
      cvo_stop=$(date)
      break
    fi

    sleep 25
  done

  # 3.5) unpause machine config pools
  if [ "${spoke_version}" == '4.14.0-ec.3' ]; then
    oc patch mcp/master --patch '{"spec":{"paused":false}}' --type=merge
    oc patch mcp/worker --patch '{"spec":{"paused":false}}' --type=merge
  fi

  echo "[INFO] Upgrade to version ${spoke_version} started at ${start} and finished at ${cvo_stop}"
  echo "====="
  echo ""

  sleep 25
done

echo ""
echo "Finished emulation"
