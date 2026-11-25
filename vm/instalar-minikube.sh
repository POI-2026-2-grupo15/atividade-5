#!/usr/bin/env bash
# Instala Docker, kubectl e Minikube na VM (Ubuntu 24.04) e sobe o cluster.
# Executar na VM como usuário ubuntu:  bash instalar-minikube.sh
set -euo pipefail

# 1. Docker Engine (driver do Minikube: cada nó do cluster roda como um container)
sudo apt-get update -y
sudo apt-get install -y docker.io conntrack curl
sudo usermod -aG docker "$USER"

# 2. kubectl e Minikube (binários oficiais, versão estável mais recente)
KUBECTL_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
curl -fsSLo /tmp/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
sudo install -m 0755 /tmp/kubectl /usr/local/bin/kubectl
curl -fsSLo /tmp/minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install -m 0755 /tmp/minikube /usr/local/bin/minikube

# 3. Cluster de um nó.
#    --ports publica as NodePorts das aplicações (30001-30003) na interface da VM,
#    para que o load balancer do OpenStack alcance os Services; com o driver docker,
#    sem isso as NodePorts ficariam só no IP interno do container do Minikube.
#    Recursos: 3 vCPUs e 6 GB para o cluster, sobrando 1 vCPU e ~2 GB para o SO e o Docker.
sg docker -c "minikube start \
  --driver=docker \
  --cpus=3 --memory=6144 \
  --listen-address=0.0.0.0 \
  --ports=30001:30001,30002:30002,30003:30003"

sg docker -c "minikube addons enable metrics-server"

# 4. Sobe o cluster de novo após reboot da VM
sudo tee /etc/systemd/system/minikube.service >/dev/null <<UNIT
[Unit]
Description=Minikube (atividade 5)
After=docker.service network-online.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
User=$USER
ExecStart=/usr/local/bin/minikube start
ExecStop=/usr/local/bin/minikube stop

[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload
sudo systemctl enable minikube.service

kubectl version
sg docker -c "minikube status"
kubectl get nodes -o wide
