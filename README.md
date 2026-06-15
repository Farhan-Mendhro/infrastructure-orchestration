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

<img width="1408" height="768" alt="infra-orchestration" src="https://github.com/user-attachments/assets/bfd529fe-7861-437f-b856-018881f7c66f" />


## Problem Statement

Managing infrastructure manually at scale is slow, error-prone, and not repeatable. Spinning up EC2 instances through the AWS Console has no version control and cannot be automated. Installing Docker across multiple nodes manually introduces configuration drift. Setting up monitoring node-by-node is fragile and produces inconsistent results.

This project solves all three layers in a single command — `git push`. Spacelift orchestrates a dependency-chained stack pipeline: infrastructure provisioning triggers Docker installation, which triggers monitoring stack deployment. No manual console interaction at any layer.

---

## Architecture & Network Flow

> See architecture diagram above for full visual topology.

### Spacelift Stack Pipeline

| Stack | Trigger | Responsibility |
|---|---|---|
| `spacelift/infra-orchestration` | VCS push to `main` | Runs Terraform — provisions 5 EC2 instances |
| `spacelift/ansible` | Depends on `infra-orchestration` | Runs `install_docker.yml` — installs Docker CE across all nodes |
| `spacelift/ansible-monitoring` | Depends on `spacelift/ansible` | Runs `install_monitoring.yml` — deploys Prometheus and Grafana stack |

All three stacks are chained via Spacelift stack dependencies. A single `git push origin main` triggers the full pipeline in sequence.

### Node Role Assignment

| Node | Role | Containers | Ports |
|---|---|---|---|
| Node 1 | Worker | `prom/node-exporter` | 9100 |
| Node 2 | Worker | `prom/node-exporter` | 9100 |
| Node 3 | Worker | `prom/node-exporter` | 9100 |
| Node 4 | Worker | `prom/node-exporter` | 9100 |
| Node 5 | Centralized Monitoring | `prom/prometheus`, `grafana/grafana` | 9090, 3000 |

### Network Configuration

| Component | Network Mode | Reason |
|---|---|---|
| `node-exporter` (Nodes 1-4) | `--network host` | Exposes bare-metal metrics directly on host interface — no NAT, no bridge overhead |
| `prometheus` (Node 5) | Bridge | Scrapes worker nodes via their IPs on port 9100 |
| `grafana` (Node 5) | Bridge | Routes to Prometheus via Docker bridge gateway `172.17.0.1:9090` |

---

## Repository Structure

```
infrastructure-orchestration/
|
|-- spacelift_key.pub           # Public key injected into EC2 instances for Spacelift SSH access
|-- .gitignore
|
+-- tf/                         # Terraform — EC2 provisioning (5 instances)
+-- ansible/
    |-- install_docker.yml      # Playbook — Docker Engine CE installation
    +-- install_monitoring.yml  # Playbook — Prometheus + Grafana stack deployment
```

---

## Prerequisites

- Three Spacelift stacks configured (`infra-orchestration`, `ansible`, `ansible-monitoring`) with stack dependencies set in the Spacelift UI.
- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `AWS_DEFAULT_REGION` injected as environment variables in each stack.
- `spacelift_key.pub` committed to the repository — Spacelift uses the corresponding private key to SSH into EC2 nodes for Ansible execution.

---

## Deployment

The entire pipeline is triggered by a single command:

```bash
git push origin main
```

Spacelift detects the VCS push and executes the stack pipeline in order:

1. **`infra-orchestration` stack** — runs `terraform apply`, provisions 5 EC2 instances in AWS.
2. **`ansible` stack** — triggered automatically on `infra-orchestration` success, runs `install_docker.yml` across all 5 nodes.
3. **`ansible-monitoring` stack** — triggered automatically on `ansible` success, runs `install_monitoring.yml`, deploys the full monitoring stack.

No manual steps required after the push. Monitor progress in the Spacelift UI under each stack's run history.

---

## Technical Highlights

### Dynamic Monitoring Node Assignment

Rather than hardcoding Node 5's IP, `install_monitoring.yml` uses `ansible_play_batch[-1]` to dynamically resolve the last host in the play — making the playbook portable across inventory changes without modification.

```yaml
when: inventory_hostname == ansible_play_batch[-1]
```

### Idempotent Container Deployment

Before deploying any container, existing containers are stopped and removed by name — eliminating Docker's naming conflict error on re-runs and making the playbook safe to execute repeatedly.

```yaml
- name: Remove existing container
  ansible.builtin.shell: docker rm -f node-exporter || true
```

### Docker Bridge Gateway Routing

Grafana and Prometheus run as separate containers on Node 5's default bridge network. Grafana cannot reach Prometheus via `localhost` due to isolated network namespaces. The Docker bridge gateway IP `172.17.0.1` — the host-side interface of the `docker0` bridge — is reachable from any container on the bridge, routing traffic to Prometheus without requiring a custom Docker network.

### Host Network Mode for Accurate Metrics

`node-exporter` runs with `--network host` on worker nodes, binding directly to the host network interface. This exposes accurate bare-metal metrics that would otherwise reflect container-level isolation if run on a bridge network.

---

*infrastructure-orchestration — Terraform, Spacelift, Ansible, Docker, Prometheus, Grafana, AWS EC2.*
