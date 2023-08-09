#!/bin/bash

# 1) Set variables
SPOKE="zt-sno3"
# DNS A records 
#SPOKE_IP="2600:52:7:59::300"

# 2) Set KUBECONFIG for spoke
export KUBECONFIG=/root/spoke/${SPOKE}/kubeconfig-${SPOKE}.yaml

start=$(date)
echo ""
echo "====="
echo "[INFO] Starting Measurement of Reboot ${SPOKE} at ${start}"

ssh -q core@${SPOKE} 'sudo reboot' > /dev/null 2>&1
#sleep 30 # add time for testing

while true;
do  
  if ! ping -c 2 ${SPOKE} > /dev/null 2>&1; then
    reboot_start=$(date)
    echo "[INFO] Node started a reboot at ${reboot_start}"
    
    while ! nc -vz -w 1 ${SPOKE} 22 > /dev/null 2>&1; do
      sleep 1
    done

    reboot_stop=$(date)
    echo "[INFO] Node finished the reboot at ${reboot_stop}"
    break
  fi
  sleep 1
done

complete=$(date)
echo "[INFO] Reboot of ${SPOKE} finished at ${reboot_stop}"
echo [INFO] Reboot Process took $(( $(date -d "${reboot_stop}" +%s) -  $(date -d "${reboot_start}" +%s) )) seconds
echo "====="
echo ""
