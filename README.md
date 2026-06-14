# infrastructure-orchestration

End-to-end infrastructure orchestration pipeline provisioning 5 AWS EC2 instances via Terraform and Spacelift, configuring Docker across all nodes via Ansible, and deploying a containerized Prometheus and Grafana monitoring stack with dynamic node assignment and host-network telemetry collection.

![Terraform](https://img.shields.io/badge/Terraform-IaC-7B42BC?style=flat-square&logo=terraform&logoColor=white)
![Spacelift](https://img.shields.io/badge/Spacelift-CI%2FCD-FF6B6B?style=flat-square)
![Ansible](https://img.shields.io/badge/Ansible-Configuration-EE0000?style=flat-square&logo=ansible&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-EC2-FF9900?style=flat-square&logo=amazon-aws&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Containers-2496ED?style=flat-square&logo=docker&logoColor=white)
![Prometheus](https://img.shields.io/badge/Prometheus-Metrics-E6522C?style=flat-square&logo=prometheus&logoColor=white)
![Grafana](https://img.shields.io/badge/Grafana-Dashboards-F46800?style=flat-square&logo=grafana&logoColor=white)

---

## Project Overview

This project implements a full infrastructure lifecycle across three layers:

1. **Provisioning** — Terraform provisions 5 EC2 instances. Spacelift manages state, plan/apply execution, and CI/CD triggers via VCS integration.
2. **Configuration** — Ansible configures all nodes: purges legacy packages, installs Docker Engine CE, enables the systemd service, and deploys the monitoring stack.
3. **Observability** — A containerized monitoring stack runs across the cluster. Worker nodes expose bare-metal metrics via `node-exporter`. A dedicated monitoring node runs Prometheus and Grafana, with dynamic scrape target generation and Docker bridge-based internal routing.

---
<img width="1408" height="768" alt="infra-orchestration" src="https://github.com/user-attachments/assets/61d7285a-5b51-4ce8-bd5b-ef5333440ee7" />


## Architecture & Network Flow

### Logical Topology

```
+---------------------+          Spacelift CI/CD         +-------------------+
|   Git Repository    |  -------------------------------->|   Spacelift Stack |
|   (Terraform IaC)   |          VCS Push Trigger        |   State + Apply   |
+---------------------+                                   +-------------------+
                                                                    |
                                                         Terraform apply
                                                                    |
                                        +--------------------------+---------------------------+
                                        |                          |                           |
                               +--------+-------+        +---------+------+          +---------+------+
                               |   EC2 Node 1   |        |   EC2 Node 2   |   ...    |   EC2 Node 5   |
                               |   Worker       |        |   Worker       |          |   Monitoring   |
                               +----------------+        +----------------+          +----------------+
                                        |                          |                           |
                               node-exporter              node-exporter              Prometheus :9090
                               --network host             --network host             Grafana    :3000
                               port 9100                  port 9100                           |
                                        |                          |                           |
                                        +----------+---------------+                           |
                                                   |       Prometheus scrapes                  |
                                                   +-------------------------------------------+
                                                         <node_ip>:9100 (x4 targets)

Grafana --> 172.17.0.1:9090 (Docker bridge gateway) --> Prometheus container
```

### Node Role Assignment

| Node | Role | Containers | Ports |
|---|---|---|---|
| Node 1 | Worker | `prom/node-exporter` | 9100 |
| Node 2 | Worker | `prom/node-exporter` | 9100 |
| Node 3 | Worker | `prom/node-exporter` | 9100 |
| Node 4 | Worker | `prom/node-exporter` | 9100 |
| Node 5 | Centralized Monitoring | `prom/prometheus`, `grafana/grafana` | 9090, 3000 |

### Network Configuration

| Component | Network Mode | Routing |
|---|---|---|
| `node-exporter` (Nodes 1-4) | `--network host` | Exposes bare-metal metrics directly on host interface — no NAT, no bridge overhead |
| `prometheus` (Node 5) | Bridge | Scrapes worker nodes via their public/private IPs on port 9100 |
| `grafana` (Node 5) | Bridge | Routes to Prometheus via Docker bridge gateway `172.17.0.1:9090` |

---

## Tech Stack

| Tool | Layer | Purpose |
|---|---|---|
| Terraform | Provisioning | Declares EC2 infrastructure as code |
| Spacelift | CI/CD | Stack orchestration, remote state, plan/apply pipeline |
| AWS EC2 | Compute | 5 Ubuntu instances — worker and monitoring roles |
| Ansible | Configuration Management | Docker installation and monitoring stack deployment |
| Docker | Runtime | Container execution across all nodes |
| Prometheus | Metrics | Scrapes and stores node-level telemetry |
| Grafana | Visualization | Dashboards over Prometheus datasource |

---

## Repository Structure

```
infrastructure-orchestration/
|
|-- main.tf                     # Terraform — EC2 provisioning (5 instances)
|-- variables.tf                # Input variable declarations
|-- outputs.tf                  # Output values (public IPs, instance IDs)
|-- terraform.tfvars            # Variable values (excluded from version control)
|
+-- ansible/
    |-- inventory.ini           # All 5 node IPs grouped under [all]
    |-- install_docker.yml      # Playbook — Docker Engine CE installation
    +-- install_monitoring.yml  # Playbook — Prometheus + Grafana stack deployment
```

---

## Prerequisites

### AWS IAM

The IAM user or role used by Spacelift requires the following minimum permissions:

| Permission | Purpose |
|---|---|
| `ec2:RunInstances` | Launch EC2 instances |
| `ec2:DescribeInstances` | Read instance state for Terraform refresh |
| `ec2:TerminateInstances` | Destroy infrastructure on `terraform destroy` |
| `ec2:CreateSecurityGroup` / `ec2:AuthorizeSecurityGroupIngress` | Configure inbound rules for SSH, 9090, 9100, 3000 |

### Spacelift Configuration

- A Spacelift **Stack** connected to this repository via VCS integration.
- Stack root set to the directory containing `main.tf`.
- **Administrative IAM credentials** injected as Spacelift environment variables:
  - `AWS_ACCESS_KEY_ID`
  - `AWS_SECRET_ACCESS_KEY`
  - `AWS_DEFAULT_REGION`
- **Auto-apply** enabled or manual apply triggered post-plan review.

### Local Control Node

```bash
# Ansible
sudo apt update && sudo apt install -y ansible

# AWS collection (if provisioning via Ansible as well)
ansible-galaxy collection install amazon.aws

# SSH key — must match the key pair attached to EC2 instances at launch
ssh-keygen -t rsa -b 4096 -f ~/.ssh/infra-key
```

### AWS Security Group — Inbound Rules

| Port | Protocol | Purpose |
|---|---|---|
| 22 | TCP | Ansible SSH access |
| 9100 | TCP | Prometheus scraping node-exporter |
| 9090 | TCP | Prometheus UI / API access |
| 3000 | TCP | Grafana dashboard access |

---

## Deployment Instructions

### Step 1 — Provision Infrastructure via Spacelift

Push to the connected branch to trigger the Spacelift pipeline:

```bash
git push origin main
```

Spacelift executes `terraform plan` automatically. Review the plan output in the Spacelift UI, then trigger apply. On completion, 5 EC2 instances are running in AWS.

Retrieve public IPs from Terraform outputs:

```bash
terraform output
```

### Step 2 — Update Ansible Inventory

Populate `ansible/inventory.ini` with the 5 public IPs:

```ini
[all]
<NODE_1_IP>   ansible_user=ubuntu   ansible_ssh_private_key_file=~/.ssh/infra-key
<NODE_2_IP>   ansible_user=ubuntu   ansible_ssh_private_key_file=~/.ssh/infra-key
<NODE_3_IP>   ansible_user=ubuntu   ansible_ssh_private_key_file=~/.ssh/infra-key
<NODE_4_IP>   ansible_user=ubuntu   ansible_ssh_private_key_file=~/.ssh/infra-key
<NODE_5_IP>   ansible_user=ubuntu   ansible_ssh_private_key_file=~/.ssh/infra-key
```

### Step 3 — Verify Connectivity

```bash
ansible all -i ansible/inventory.ini -m ping
```

### Step 4 — Install Docker Engine CE Across All Nodes

```bash
ansible-playbook ansible/install_docker.yml -i ansible/inventory.ini
```

`install_docker.yml` executes in order across all 5 nodes:
- Purges legacy packages (`docker.io`, `docker-compose`, `containerd`, `runc`)
- Installs required keyrings and adds the official Docker apt repository
- Installs `docker-ce`, `docker-ce-cli`, `containerd.io`
- Enables and starts the `docker` systemd service

### Step 5 — Deploy Monitoring Stack

```bash
ansible-playbook ansible/install_monitoring.yml -i ansible/inventory.ini
```

Execution behavior:
- **Nodes 1-4:** Stops and removes any existing `node-exporter` container, then runs `prom/node-exporter` with `--network host` on port 9100.
- **Node 5** (resolved via `ansible_play_batch[-1]`): Generates a dynamic `prometheus.yml` scrape config targeting all 4 worker node IPs, deploys `prom/prometheus` on port 9090 with config volume mount, deploys `grafana/grafana` on port 3000.

### Step 6 — Access Monitoring Interfaces

| Interface | URL |
|---|---|
| Prometheus | `http://<NODE_5_IP>:9090` |
| Grafana | `http://<NODE_5_IP>:3000` |
| Node Exporter (per worker) | `http://<NODE_1-4_IP>:9100/metrics` |

Default Grafana credentials: `admin` / `admin` — change on first login.

Configure Grafana datasource:
- Type: Prometheus
- URL: `http://172.17.0.1:9090`

---

## Technical Highlights

### 1. Dynamic Monitoring Node Assignment via `ansible_play_batch[-1]`

Rather than hardcoding Node 5's IP as the monitoring node, `install_monitoring.yml` uses Ansible's `ansible_play_batch` list — the ordered list of hosts in the current play batch — and indexes the last element with `[-1]`. This resolves the final host in the inventory dynamically, making the playbook portable across inventory changes without modification.

```yaml
when: inventory_hostname == ansible_play_batch[-1]
```

### 2. Idempotent Container Deployment

Before deploying any container, `install_monitoring.yml` explicitly stops and removes existing containers by name. This eliminates Docker's "container name already in use" conflict on re-runs and ensures every execution starts from a clean state — making the playbook safe to run repeatedly.

```yaml
- name: Remove existing node-exporter container
  ansible.builtin.shell: docker rm -f node-exporter || true
```

### 3. Docker Bridge Gateway Routing for Grafana

`prom/prometheus` and `grafana/grafana` run as separate containers on Node 5's default Docker bridge network. Grafana cannot reach Prometheus via `localhost` because each container has an isolated network namespace. The Docker bridge gateway IP `172.17.0.1` — the host-side interface of the `docker0` bridge — is reachable from any container on the bridge network and routes traffic to other containers on the same host. Configuring Grafana's Prometheus datasource to `http://172.17.0.1:9090` resolves this without requiring a custom Docker network or `--network host` on Prometheus.

### 4. Host Network Mode for Bare-Metal Metrics

`prom/node-exporter` runs with `--network host` on worker nodes. This bypasses the Docker bridge entirely and binds the exporter directly to the host network interface, exposing accurate bare-metal metrics — CPU, memory, disk, and network — that would otherwise reflect container-level isolation artifacts if run on a bridge network.

---

*infrastructure-orchestration — Terraform, Spacelift, Ansible, Docker, Prometheus, Grafana, AWS EC2.*
