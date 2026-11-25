#!/usr/bin/env bash
# Aponta os listeners do grupo no load balancer compartilhado poi-atividades para a VM nova.
# Os listeners e pools (portas 10001-10004) já existem desde a atividade 3; aqui só
# trocamos os members (destinos) pelo IP da VM do Minikube.
set -euo pipefail

LB=57c2b14a-b746-4f34-8719-d0627e409609   # poi-atividades (há outro LB com o mesmo nome, por isso o UUID)
VM_IP=$(openstack server show grupo-2-ahv-k8s-vm -f json -c addresses | python3 -c 'import json,sys; print(json.load(sys.stdin)["addresses"]["provider"][0])')

# pool : porta de destino na VM
#   ssh    -> 22     (listener TCP  10001)
#   cpu    -> 30001  (listener HTTP 10002, NodePort do Service cpu-bound)
#   io     -> 30002  (listener HTTP 10003, NodePort do Service io-bound)
#   memory -> 30003  (listener HTTP 10004, NodePort do Service memory-bound)
for par in ssh:22 cpu:30001 io:30002 memory:30003; do
  app=${par%%:*}; porta=${par##*:}; pool="grupo-2-ahv-$app-pool"
  for m in $(openstack loadbalancer member list "$pool" -f value -c id); do
    openstack loadbalancer member delete --wait "$pool" "$m"
  done
  openstack loadbalancer member create --name "grupo-2-ahv-k8s-$app-member" \
    --address "$VM_IP" --protocol-port "$porta" --subnet-id provider-sub --wait "$pool"
done

openstack loadbalancer listener list --loadbalancer "$LB" -c name -c protocol -c protocol_port | grep -E 'name|grupo-2-ahv'
for app in ssh cpu io memory; do
  openstack loadbalancer member list "grupo-2-ahv-$app-pool" -c name -c address -c protocol_port -c operating_status
done
