# Atividade 5 — Kubernetes (Minikube) na cloud OpenStack do LSD

Grupo: Arthur Gabriel Santos Albuquerque (122110395), Hildon Regis Navarro Neto (122110322) e Victor Vili Xavier Luna (122110387).

As três aplicações das atividades anteriores (CPU-bound, IO-bound e Memory-bound) rodam em um cluster Kubernetes de um nó, criado com o Minikube em uma VM da cloud OpenStack do LSD. Elas são acessadas de fora pelo load balancer `poi-atividades`.

| Aplicação | URL externa | Exemplo |
|---|---|---|
| CPU-bound | http://150.165.85.77:10002 | `GET /health`, `POST /benchmark` |
| IO-bound | http://150.165.85.77:10003 | `GET /health`, `POST /io` |
| Memory-bound | http://150.165.85.77:10004 | `GET /docs`, `POST /memory-test` |

Para testar as três de uma vez, rode:

```bash
./testar-acesso.sh
```

## Estrutura do repositório

| Caminho | Conteúdo |
|---|---|
| [openstack/01-provisionar-vm.sh](openstack/01-provisionar-vm.sh) | Cria o par de chaves, o security group e a VM |
| [openstack/02-configurar-load-balancer.sh](openstack/02-configurar-load-balancer.sh) | Aponta os listeners do grupo no `poi-atividades` para a VM |
| [vm/instalar-minikube.sh](vm/instalar-minikube.sh) | Instala Docker, kubectl e Minikube na VM e sobe o cluster |
| [k8s/](k8s/) | Manifestos do Kubernetes: namespace e um arquivo por aplicação |
| [testar-acesso.sh](testar-acesso.sh) | Testa as três aplicações pelo IP do load balancer |

## Arquitetura

```
Internet ── 150.165.85.77 (floating IP do LB poi-atividades, VIP 10.5.8.242)
              │
              ├─ :10001 TCP  ─► 10.5.9.224:22     SSH da VM
              ├─ :10002 HTTP ─► 10.5.9.224:30001  ─► Service cpu-bound    ─► 2 pods
              ├─ :10003 HTTP ─► 10.5.9.224:30002  ─► Service io-bound     ─► 1 pod + PVC
              └─ :10004 HTTP ─► 10.5.9.224:30003  ─► Service memory-bound ─► 1 pod

VM grupo-2-ahv-k8s-vm (Ubuntu 24.04, general.large: 4 vCPUs, 8 GB, 20 GB)
  └─ Docker ─► container "minikube" (nó único do Kubernetes, 3 vCPUs / 6 GB)
                 portas 30001-30003 publicadas na interface da VM
```

## 1. Limpeza da infraestrutura anterior

Os recursos da atividade 3/4 que eram do grupo foram removidos para liberar cota:

```bash
openstack server delete --wait grupo-2-ahv-vm       # VM general.small (1 vCPU, 2 GB)
openstack volume delete grupo-2-ahv-vol             # volume de 1 GB (fica "available" após apagar a VM)
openstack image delete grupo-2-ahv-vm-snapshot      # snapshot da VM
```

O load balancer `poi-atividades` e os recursos dos outros grupos **não** foram alterados. Os listeners e pools do grupo (portas 10001 a 10004) foram **mantidos e reaproveitados**: só os destinos (members) foram trocados (seção 4).

Observação: existem dois load balancers chamados `poi-atividades`. O correto é o de UUID `57c2b14a-b746-4f34-8719-d0627e409609`, com VIP 10.5.8.242. Por isso os scripts usam o UUID.

## 2. Acesso à CLI do OpenStack

A CLI foi instalada localmente, com o plugin do load balancer (Octavia):

```bash
pipx install python-openstackclient
pipx inject python-openstackclient python-octaviaclient
```

O arquivo OpenRC foi baixado no Horizon, em **Projeto → Acesso à API → Baixar arquivo OpenStack RC**, com o projeto **Provisionamento** selecionado. O domínio do usuário é `External`. A autenticação é feita assim:

```bash
source Provisionamento-openrc.sh   # pede a senha
openstack token issue
```

## 3. Criação da VM — [openstack/01-provisionar-vm.sh](openstack/01-provisionar-vm.sh)

1. **Par de chaves:** uma chave Ed25519 é gerada localmente (`~/.ssh/grupo-2-ahv-k8s`) e a parte pública é registrada como `grupo-2-ahv-k8s-key`.
2. **Security group `grupo-2-ahv-k8s-sg`:**
   - TCP 22 (SSH) e ICMP, liberados de qualquer origem.
   - TCP 30001–30003, liberados apenas para a rede `provider` (10.5.8.0/22), de onde vem o tráfego do load balancer. As NodePorts não ficam abertas para outras origens.
3. **VM `grupo-2-ahv-k8s-vm`:**
   - Flavor `general.large`: 4 vCPUs, 8 GB de RAM e 20 GB de disco, o que atende ao mínimo exigido.
   - Imagem `ubuntu-24.04`, rede `provider`.
   - Nesta versão da API, a busca do flavor pelo nome retorna `400 Additional properties are not allowed ('name' was unexpected)`. Por isso o script usa os IDs do flavor e da imagem.

Resultado:

| Campo | Valor |
|---|---|
| ID da VM | `f8a243ee-36c6-4433-8754-69382227602a` |
| IP | 10.5.9.224 |
| Flavor | general.large (4 vCPUs, 8192 MB) |
| SO | Ubuntu 24.04.3 LTS |

## 4. Load balancer — [openstack/02-configurar-load-balancer.sh](openstack/02-configurar-load-balancer.sh)

A VM só tem IP privado. Todo acesso externo, inclusive o SSH, passa pelo `poi-atividades`, seguindo a cadeia listener → pool → member. O script remove os members antigos, que apontavam para 10.5.11.32, e cria os novos com destino na VM:

| Listener | Protocolo/porta | Pool | Member (destino) |
|---|---|---|---|
| `grupo-2-ahv-ssh` | TCP 10001 | `grupo-2-ahv-ssh-pool` | 10.5.9.224:22 |
| `grupo-2-ahv-cpu` | HTTP 10002 | `grupo-2-ahv-cpu-pool` | 10.5.9.224:30001 |
| `grupo-2-ahv-io` | HTTP 10003 | `grupo-2-ahv-io-pool` | 10.5.9.224:30002 |
| `grupo-2-ahv-memory` | HTTP 10004 | `grupo-2-ahv-memory-pool` | 10.5.9.224:30003 |

Acesso SSH à VM:

```bash
ssh -i ~/.ssh/grupo-2-ahv-k8s -p 10001 ubuntu@150.165.85.77
```

## 5. Instalação do Kubernetes com Minikube — [vm/instalar-minikube.sh](vm/instalar-minikube.sh)

O script é copiado para a VM e executado:

```bash
scp -i ~/.ssh/grupo-2-ahv-k8s -P 10001 vm/instalar-minikube.sh ubuntu@150.165.85.77:~/
ssh -i ~/.ssh/grupo-2-ahv-k8s -p 10001 ubuntu@150.165.85.77 'bash ~/instalar-minikube.sh'
```

O que o script faz:

1. **Docker** (`docker.io`, versão 29.1.3): é o driver do Minikube, ou seja, o nó do cluster roda como um container. O usuário `ubuntu` entra no grupo `docker`, porque o Minikube não deve rodar como root.
2. **kubectl** (v1.37.2) e **Minikube** (v1.39.0): binários oficiais instalados em `/usr/local/bin`.
3. **`minikube start`** com:
   - `--driver=docker`.
   - `--cpus=3 --memory=6144`: sobram 1 vCPU e cerca de 2 GB para o SO e o Docker.
   - `--ports=30001:30001,30002:30002,30003:30003` e `--listen-address=0.0.0.0`. Com o driver docker, as NodePorts existem só no IP interno do container do Minikube (192.168.49.2). Essas opções publicam as três NodePorts na interface da VM, e é assim que o load balancer as alcança. As demais portas do Minikube, como a API do Kubernetes, ficam bloqueadas pelo security group.
4. **Addon `metrics-server`**, para usar `kubectl top`.
5. **Unidade systemd `minikube.service`**: sobe o cluster de novo após um reboot da VM.

Resultado: Kubernetes v1.37.0 com runtime containerd 2.3.4, nó `minikube` em `Ready`.

```bash
minikube status
kubectl get nodes -o wide
```

## 6. Deploy das aplicações — [k8s/](k8s/)

As imagens são as publicadas no Docker Hub na atividade 4. Todas escutam na porta 8000:

| Aplicação | Imagem |
|---|---|
| CPU-bound | `arthurgb469/cpu-bound:atividade-4` |
| IO-bound | `arthurgb469/io-bound:atividade-4` |
| Memory-bound | `victorxluna/memory-bound:atv4` |

```bash
kubectl apply -f k8s/
kubectl -n atividade5 rollout status deploy
kubectl -n atividade5 get deploy,pods,svc,pvc
```

Tudo fica no namespace `atividade5`, isolado dos componentes do sistema.

### Escolhas de workload (justificativa)

| Aplicação | Workload | Réplicas | Recursos (request / limit) | Por quê |
|---|---|---|---|---|
| CPU-bound | Deployment | 2 | CPU 500m / 1, mem 128Mi / 512Mi | API **sem estado**: qualquer réplica atende qualquer requisição. Com 2 pods, o Service distribui a carga e o trabalho de CPU usa mais de um núcleo (o container roda Uvicorn com 1 worker). Com 2 réplicas, a aplicação também continua respondendo se um pod cair. O Deployment é o workload padrão para apps sem estado: faz rolling update e recria pods que falham. |
| IO-bound | Deployment + **PersistentVolumeClaim** (2Gi, `ReadWriteOnce`) | 1 | CPU 250m / 1, mem 128Mi / 512Mi | A aplicação mede leitura e escrita em disco em `IO_DATA_DIR=/data`. Esse diretório precisa estar em um disco real, e não na camada gravável do container nem em tmpfs, mantendo o que foi feito com o volume nomeado do Docker na atividade 4. O PVC usa a StorageClass `standard` do Minikube, que provisiona o volume no disco da VM. Como o volume é `ReadWriteOnce` e várias réplicas disputariam o mesmo disco sem ganho, fica 1 réplica, com estratégia `Recreate`: o pod antigo libera o volume antes de o novo subir. Não foi usado StatefulSet porque não há identidade estável nem um volume por réplica. |
| Memory-bound | Deployment | 1 | CPU 250m / 1, mem 512Mi / **2Gi** | É sem estado, mas cada requisição consolida CSVs **em memória**. Ganhou o maior limite de memória, para aceitar cargas maiores sem ser morta por OOM. Ficou com 1 réplica, porque várias cópias disputariam a RAM do nó único (6 GB). |

Em todos os casos:

- **Service do tipo NodePort**, com portas fixas 30001, 30002 e 30003, para que os members do load balancer apontem sempre para a mesma porta.
- **Probes:**
  - `readinessProbe`: o Service só envia tráfego a pods prontos.
  - `livenessProbe`: o kubelet reinicia o container se ele travar.
  - Rotas: `/health` na CPU-bound e na IO-bound. A Memory-bound não tem `/health`, então as probes dela usam `/docs`.
- **Requests e limits:** dão ao scheduler a reserva de cada pod (soma dos requests: 1,5 de 3 vCPUs) e impedem que uma aplicação consuma o nó inteiro.

## 7. Verificação do acesso externo

Pelo IP do load balancer, a partir de uma máquina fora da cloud:

```
$ ./testar-acesso.sh
== CPU-bound (porta 10002)
{"status":"ok"}
{"algorithm":"sha256","data_size_mb":1,"iterations":2,"total_processed_mb":2,...,"digest":"1599677..."}
== IO-bound (porta 10003)
{"status":"ok"}
{"size_kb":1024,"fsync":true,"write_ms":5.06,"read_ms":4.01,"total_ms":9.08,"verified":true}
== Memory-bound (porta 10004)
{"files_processed":2,"records_received":4,"unique_records":3,"replaced_occurrences":1,...}
```

Também foi verificado que o Service da CPU-bound distribui as requisições entre as duas réplicas. Foram enviadas sete requisições `/benchmark`: 3 foram atendidas por um pod e 4 pelo outro (`kubectl -n atividade5 logs <pod>`).

## Comandos úteis na VM

```bash
kubectl -n atividade5 get pods -o wide        # estado dos pods
kubectl -n atividade5 logs deploy/io-bound    # logs de uma aplicação
kubectl -n atividade5 scale deploy/cpu-bound --replicas=3
kubectl top pods -n atividade5                # consumo (metrics-server)
minikube dashboard --url                      # painel web (acessar via túnel SSH)
```
