#!/usr/bin/env bash
# Provisiona a VM da atividade 5 na cloud OpenStack do LSD (projeto Provisionamento).
# Pré-requisito: CLI autenticada (source <openrc>).
set -euo pipefail

PREFIXO=grupo-2-ahv-k8s
CHAVE="$HOME/.ssh/$PREFIXO"

# 1. Par de chaves SSH (Ed25519) gerado localmente e registrado no OpenStack
[ -f "$CHAVE" ] || ssh-keygen -t ed25519 -f "$CHAVE" -N "" -C "$PREFIXO"
openstack keypair create --public-key "$CHAVE.pub" "$PREFIXO-key"

# 2. Security group: SSH, ICMP e as NodePorts das três aplicações (30001-30003)
openstack security group create --description "Atividade 5 - Minikube grupo 15" "$PREFIXO-sg"
openstack security group rule create --ingress --protocol tcp --dst-port 22 --remote-ip 0.0.0.0/0 "$PREFIXO-sg"
openstack security group rule create --ingress --protocol icmp --remote-ip 0.0.0.0/0 "$PREFIXO-sg"
openstack security group rule create --ingress --protocol tcp --dst-port 30001:30003 --remote-ip 10.5.8.0/22 "$PREFIXO-sg"

# 3. VM: Ubuntu 24.04, flavor general.large (4 vCPUs, 8 GB RAM, 20 GB disco)
#    IDs usados porque a busca por nome do flavor falha nesta versão da API
#    (openstack flavor list / openstack image list mostram os IDs).
openstack server create \
  --flavor be9875d8-f22b-426e-91e1-79f04c705c09 \
  --image 8ac7c385-d5d2-488a-82a4-4e1b57ffa6b1 \
  --key-name "$PREFIXO-key" \
  --security-group "$PREFIXO-sg" \
  --network provider \
  --wait \
  "$PREFIXO-vm"

openstack server show "$PREFIXO-vm" -c id -c name -c status -c addresses -c flavor
