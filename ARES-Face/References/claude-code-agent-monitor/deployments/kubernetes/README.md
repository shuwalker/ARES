# Kubernetes Manifests

Production-ready Kubernetes resources using Kustomize for environment management, with optional blue-green and canary deployment strategies.

## Structure

```
kubernetes/
├── base/                    # Shared base (all environments inherit from this)
│   ├── kustomization.yaml
│   ├── namespace.yaml       # agent-monitor namespace with Pod Security Standards
│   ├── configmap.yaml       # Environment configuration
│   ├── serviceaccount.yaml  # Minimal-privilege service account
│   ├── deployment.yaml      # Main deployment (2 replicas, 3 health probes)
│   ├── service.yaml         # ClusterIP with WebSocket sticky sessions
│   ├── ingress.yaml         # NGINX ingress with TLS + WebSocket headers
│   ├── pvc.yaml             # 10Gi persistent volume for SQLite
│   ├── hpa.yaml             # Horizontal Pod Autoscaler (2–10 pods)
│   ├── pdb.yaml             # Pod Disruption Budget (minAvailable: 1)
│   └── networkpolicy.yaml   # Ingress restricted to NGINX controller
├── overlays/
│   ├── dev/                 # 1 replica, no HPA, minimal resources
│   ├── staging/             # 2 replicas, standard resources
│   └── production/          # 3 replicas, HPA 3–20, strict anti-affinity
├── strategies/
│   ├── blue-green/          # Dual-slot deployment with service switching
│   └── canary/              # Progressive rollout with Argo Rollouts analysis
└── components/
    ├── mcp-sidecar/         # Adds MCP server container to pods
    └── monitoring/          # Adds Prometheus ServiceMonitor
```

## Usage

```bash
# Apply an environment
kubectl apply -k overlays/dev/
kubectl apply -k overlays/staging/
kubectl apply -k overlays/production/

# Add MCP sidecar (edit overlay kustomization.yaml):
#   components:
#     - ../../components/mcp-sidecar

# Blue-green switch
kubectl patch svc agent-monitor -n agent-monitor \
  -p '{"spec":{"selector":{"slot":"green"}}}'
```

## Security

All manifests enforce:
- `runAsNonRoot: true`
- `readOnlyRootFilesystem: true`
- `drop: [ALL]` capabilities
- `seccompProfile: RuntimeDefault`
- No service account token auto-mount
- NetworkPolicy restricting ingress sources
