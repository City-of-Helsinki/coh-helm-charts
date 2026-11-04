# Redis Sentinel Helm Chart

![Version: 1.1.0](https://img.shields.io/badge/version-1.1.0-blue)
![AppVersion: 7.2.11](https://img.shields.io/badge/appVersion-7.2.11-blue)

A production-ready Helm chart for deploying highly available Redis clusters with Sentinel for automatic failover in Kubernetes and OpenShift.

---

## Features

* **Automatic Failover**: Redis Sentinel handles master failures without manual intervention
* **High Availability**: 3+ Redis instances with 3+ Sentinel monitors
* **Production Ready**: Pod disruption budgets, anti-affinity rules, and resource management
* **Secure by Default**: Password authentication and configurable security contexts
* **Persistent Storage**: Optional persistent volumes for data durability
* **OpenShift Compatible**: Works with Security Context Constraints
* **Easy Integration**: Standard Redis client libraries support Sentinel mode

---

## Quick Start

### Install with Default Settings

```bash
# Add Helm repository
helm repo add coh https://city-of-helsinki.github.io/coh-helm-repo
helm repo update

# Install the chart
helm install my-redis coh/redis-cluster
```

### Install with Custom Password

```bash
helm install my-redis coh/redis-cluster \
  --set redis.password.password=mySecurePassword123
```

### Install from Source

```bash
git clone https://github.com/City-of-Helsinki/coh-helm-charts
cd charts/redis-cluster
helm install my-redis . -f values.yaml
```

---

## Architecture

This chart deploys a complete Redis Sentinel cluster with all necessary resources. StatefulSets provide stable network identities for Redis and Sentinel pods, while init containers handle dynamic configuration and replication setup. Applications connect to the Sentinel service to discover the current master.

```mermaid
graph TB
    A[App] --> SS[Sentinel Service]
    
    SS --> S1[Sentinel]
    SS --> S2[Sentinel]
    SS --> S3[Sentinel]
    
    S1 & S2 & S3 --> M[Redis Master]
    S1 & S2 & S3 --> R1[Redis Replica]
    S1 & S2 & S3 --> R2[Redis Replica]
    
    M --> R1
    M --> R2
    
    M --> PVC1[Storage]
    R1 --> PVC2[Storage]
    R2 --> PVC3[Storage]
    
    M & R1 & R2 --> CM[ConfigMap]
    M & R1 & R2 --> SEC[Secret]

    style M fill:#ff6b6b
    style R1 fill:#4ecdc4
    style R2 fill:#4ecdc4
    style S1 fill:#ffe66d
    style S2 fill:#ffe66d
    style S3 fill:#ffe66d
    style CM fill:#a8dadc
    style SEC fill:#ffb5a7
    style PVC1 fill:#f1faee
```

### Components Deployed

* **Redis StatefulSet**: 3 pods (1 master, 2 replicas) with persistent storage
* **Sentinel StatefulSet**: 3 pods monitoring Redis cluster health
* **Headless Services**: Enable DNS-based pod discovery
* **ClusterIP Service**: Single endpoint for Sentinel queries
* **ConfigMaps**: Redis and Sentinel configuration files
* **Secret**: Redis password, owned by the release (generated once and kept), or an existing Secret (legacy)
* **PodDisruptionBudgets**: Prevent too many pods down simultaneously (optional)

---

## Prerequisites

* Kubernetes 1.19+ or OpenShift 4.x+
* Helm 3.0+
* PersistentVolume provisioner (if persistence enabled)
* 3+ worker nodes recommended for pod distribution

---

## Configuration Examples

see values.yaml

## Password ownership

The chart owns the Redis password (Platta Key Vault policy, PLATTA-8196): the password is
needed only inside the namespace, so it is **not** kept in an application Key Vault.

* Leave `redis.password.existingSecret` empty. The chart creates the Secret
  (`redis.password.secretName`, or `<fullname>-secret`) with key `REDIS_PASSWORD`.
* The password is generated on first install and **kept on every upgrade** (the chart reads the
  current Secret with `lookup`). The Secret also survives `helm uninstall` by default.
* Applications in the same namespace read it directly:

  ```yaml
  env:
    - name: REDIS_PASSWORD
      valueFrom:
        secretKeyRef:
          name: redis-password      # redis.password.secretName
          key: REDIS_PASSWORD
  ```

  An explicit `env` entry wins over the same variable coming from `envFrom`, so this can be added
  while the old Key Vault secret is still mounted with `envFrom`.

* `helm template` and a client-side `helm diff` cannot `lookup`, so they show a new random value
  for the Secret. `helm upgrade --install` against the cluster keeps the real password.
* Use a fixed `secretName` so consumers do not depend on the release name. `helm install` fails
  if a Secret with that name already exists and was not created by Helm. Delete it or pick another name.

### Moving an existing release off Key Vault

For a release that uses `existingSecret: <Key Vault/ESO secret>`:

1. Deploy with the chart-owned Secret and a one-time copy of the current password, so clients keep working:
   ```yaml
   redis:
     password:
       secretName: redis-password
       migrateFromSecret: $(EXTERNAL_SECRET_NAME)   # replaced by the pipeline
   ```
   The Redis/Sentinel pods roll once (the Secret reference changes), with the same password.
2. Point the consumers (`REDIS_PASSWORD` via `secretKeyRef`, above) at `redis-password` and deploy them.
3. Remove `REDIS-PASSWORD` from the application Key Vault and re-sync the ExternalSecret.
4. Remove `migrateFromSecret` from the values. Leaving it in place does no harm, because it is
   only read when the chart Secret does not exist yet.

### Rotating the password

The chart never changes the password by itself: it is kept on upgrades and, with
`keepOnUninstall: true`, on reinstall. The pods also read it only when they start (there is no
checksum annotation), so a new value takes effect only after a restart. To rotate:

```bash
NS=<namespace>; REL=<release>; SEC=<secret name>   # e.g. helhist / helhist-redis-cluster-secret

# 1. Write a new random password into the Secret (never printed). Patching keeps the Helm
#    labels, so the next helm upgrade reads the new value and keeps it.
NEWPW=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32)
oc patch secret "$SEC" -n "$NS" --type merge \
  -p "{\"data\":{\"REDIS_PASSWORD\":\"$(printf %s "$NEWPW" | base64 -w0)\"}}"
unset NEWPW

# 2. Restart ALL Redis and Sentinel pods at once - not a rolling restart
oc delete pod -n "$NS" -l app.kubernetes.io/instance="$REL"
oc rollout status sts/"$REL"-redis-cluster-redis    -n "$NS" --timeout=10m
oc rollout status sts/"$REL"-redis-cluster-sentinel -n "$NS" --timeout=10m

# 3. Restart the consumers so they read the new password
oc rollout restart deploy/drupal deploy/drupal-cron -n "$NS"
```

* All pods at once: each pod sets `requirepass`, `masterauth` and Sentinel `auth-pass` when it
  starts. During a rolling restart, pods on the new password cannot authenticate to pods still on
  the old one, so replication and failover break until all of them have restarted.
* Expect a short Redis outage (usually under a minute), with cache errors in the applications until
  Redis and the consumers are back. Plan it outside busy hours in production.
* Alternative: delete the Secret and run `helm upgrade`, and the chart generates a new password.
  Remove `migrateFromSecret` first, otherwise the old password is copied back. Until the upgrade
  has run, the Secret does not exist.
* Do not put a real password in `redis.password.password` in a values file.

## Application Integration

Applications connect to Redis through Sentinels for automatic master discovery. This ensures applications always connect to the current master, even after failovers.

### Connection Pattern

1. Application queries Sentinel service for master address
2. Sentinel returns current master location
3. Application connects directly to master Redis
4. If connection fails, application re-queries Sentinel

### Service DNS Names

After installation, use these DNS names within the cluster:

* **Sentinel Service**: `<release-name>-sentinel.<namespace>.svc.cluster.local:26379`
* **Redis Headless**: `<release-name>-redis-0.<release-name>-headless.<namespace>.svc.cluster.local:6379`

Example for release "my-redis" in "default" namespace:
* Sentinel: `my-redis-sentinel.default.svc.cluster.local:26379`
* Redis Master: `my-redis-redis-0.my-redis-headless.default.svc.cluster.local:6379`

---

### Update Configuration

Modify Redis or Sentinel configuration without reinstalling.

```bash
# Update Redis memory limit
helm upgrade my-redis coh/redis-cluster \
  --set redis.config.maxmemory=2gb \
  --reuse-values
```

---

## Configuration Reference

## **Global Settings**

| Parameter | Description | Default |
|----------|-------------|---------|
| `podSecurityContext.enabled` | Enable pod security context | `false` |
| `podSecurityContext.runAsUser` | User ID for pod | `""` |
| `podSecurityContext.runAsGroup` | Group ID for pod | `""` |
| `podSecurityContext.fsGroup` | FS group for pod | `""` |
| `podSecurityContext.fsGroupChangePolicy` | FS group change policy | `""` |
| `nodeSelector` | Node labels (map); empty = any node, falls back to `global.nodeSelector` | `{}` |
| `tolerations` | Tolerations; falls back to `global.tolerations` | `[]` |
| `affinity` | Kubernetes affinity map; replaces the built-in anti-affinity. Legacy `affinity.enabled` still works | `{}` |
| `podAntiAffinity.enabled` | Built-in soft anti-affinity (spread pods over nodes) when `affinity` is empty | `true` |

---

## **Redis Configuration**

### **Basic Settings**

| Parameter | Description | Default |
|----------|-------------|---------|
| `redis.replicaCount` | Number of Redis instances | `3` |
| `redis.image` | Redis image as map (`registry`, `repository`, `tag`, `digest`) or full reference string | `registry.redhat.io/rhel9/redis-7:9.7-1771417604` |
| `global.imageRegistry` | Registry for images without their own `registry` | `image-registry.int.platta.hel.fi` |
| `global.imagePullSecrets` / `imagePullSecrets` | Pull secrets added to pods | `[]` |
| `redis.securityContext.enabled` | Enable security context | `false` |

---

### **Resources**

| Parameter | Description | Default |
|----------|-------------|---------|
| `redis.resources.requests.cpu` | CPU request | `50m` |
| `redis.resources.requests.memory` | Memory request | `512Mi` |
| `redis.resources.limits.cpu` | CPU limit | `""` |
| `redis.resources.limits.memory` | Memory limit | `1Gi` |

### **Persistence**

| Parameter | Description | Default |
|----------|-------------|---------|
| `redis.persistence.enabled` | Enable PVC | `false` |
| `redis.persistence.size` | PVC size | `10Gi` |
| `redis.persistence.storageClass` | Storage class | `""` |
| `redis.persistence.mountPath` | Mount path | `"/data"` |

### **Password & Security**

| Parameter | Description | Default |
|----------|-------------|---------|
| `redis.password.password` | Explicit password. Empty: generated once on first install, then kept | `""` |
| `redis.password.secretName` | Name of the Secret the chart creates (key `REDIS_PASSWORD`). Empty: `<fullname>-secret` | `""` |
| `redis.password.migrateFromSecret` | One-time copy of the password from another Secret in the namespace (e.g. the old Key Vault/ESO secret) when the chart Secret does not exist yet | `""` |
| `redis.password.migrateFromKey` | Key to read from `migrateFromSecret` | `"REDIS_PASSWORD"` |
| `redis.password.keepOnUninstall` | Keep the Secret on `helm uninstall` (`helm.sh/resource-policy: keep`) | `true` |
| `redis.password.existingSecret` | **Legacy.** Use a Secret managed outside the chart; the chart creates no Secret | `""` |
| `redis.password.secretKey` | Key in `existingSecret` | `"REDIS_PASSWORD"` |

See [Password ownership](#password-ownership) for how applications consume the password.

---

### **Pod Disruption Budget**

| Parameter | Description | Default |
|----------|-------------|---------|
| `redis.pdb.enabled` | Enable PDB | `true` |
| `redis.pdb.minAvailable` | Min available pods | `1` |
| `redis.pdb.maxUnavailable` | Max unavailable | `""` |
| `redis.pdb.annotations` | Annotations | `{}` |

---

### **Redis Config (`redis.conf`)**

| Parameter | Description | Default |
|----------|-------------|---------|
| `redis.config.bind` | Bind address | `"0.0.0.0"` |
| `redis.config.protectedMode` | Protected mode | `"yes"` |
| `redis.config.port` | Port | `6379` |
| `redis.config.timeout` | Client timeout | `"500"` |
| `redis.config.tcpKeepalive` | TCP keepalive | `"300"` |
| `redis.config.tcpBacklog` | TCP backlog | `"511"` |
| `redis.config.requirepass` | Password | `""` |
| `redis.config.daemonize` | Daemonize | `"no"` |
| `redis.config.supervised` | Supervised mode | `"no"` |
| `redis.config.pidfile` | PID file | `"/var/run/redis_6379.pid"` |
| `redis.config.loglevel` | Log level | `"notice"` |
| `redis.config.logfile` | Log file path | `""` |
| `redis.config.databases` | Databases count | `"16"` |
| `redis.config.maxmemory` | Max memory | `"900mb"` |
| `redis.config.maxmemoryPolicy` | Eviction policy | `"allkeys-lru"` |
| `redis.config.save` | RDB save intervals | `""` |
| `redis.config.appendonly` | Enable AOF | `"no"` |
| `redis.config.stopWritesOnBgsaveError` | Stop writes on BGSAVE error | `"no"` |
| `redis.config.rdbcompression` | RDB compression | `"yes"` |
| `redis.config.rdbchecksum` | RDB checksum | `"yes"` |
| `redis.config.rdbDelSyncFiles` | Delete sync files | `"no"` |
| `redis.config.replicaServeStaleData` | Serve stale data | `"yes"` |
| `redis.config.replicaReadOnly` | Replica read-only | `"yes"` |
| `redis.config.replDisklessSync` | Diskless sync | `"no"` |
| `redis.config.replDisklessSyncDelay` | Sync delay | `"5"` |
| `redis.config.replDisklessLoad` | Diskless load | `"disabled"` |
| `redis.config.replDisableTcpNodelay` | Disable NODELAY | `"no"` |
| `redis.config.replicaPriority` | Replica priority | `"100"` |
| `redis.config.acllogMaxLen` | ACL log length | `"128"` |
| `redis.config.alwaysShowLogo` | Always show logo | `"yes"` |
| `redis.config.dir` | Data dir | `"/data"` |
| `redis.extraConfig` | Extra config | `{}` |

---

### **Redis Service**

| Parameter | Description | Default |
|----------|-------------|---------|
| `redis.service.port` | Service port | `6379` |
| `redis.service.targetPort` | Container port | `6379` |

---

## **Sentinel Configuration**

### **Basic Settings**

| Parameter | Description | Default |
|----------|-------------|---------|
| `sentinel.enabled` | Enable Sentinel instances | `true` |
| `sentinel.replicaCount` | Sentinel instances | `3` |
| `sentinel.image` | Sentinel image (map or string); empty = same as `redis.image` | `{}` |
| `sentinel.securityContext.enabled` | Enable security context | `false` |

---

### **Resources**

| Parameter | Description | Default |
|----------|-------------|---------|
| `sentinel.resources.requests.cpu` | CPU request | `50m` |
| `sentinel.resources.requests.memory` | Memory request | `20Mi` |
| `sentinel.resources.limits.cpu` | CPU limit | `""` |
| `sentinel.resources.limits.memory` | Memory limit | `200Mi` |

---

### **Sentinel Pod Disruption Budget**

| Parameter | Description | Default |
|----------|-------------|---------|
| `sentinel.pdb.enabled` | Enable PDB | `true` |
| `sentinel.pdb.minAvailable` | Min available | `1` |
| `sentinel.pdb.maxUnavailable` | Max unavailable | `""` |
| `sentinel.pdb.annotations` | Annotations | `{}` |

---

### **Sentinel Config**

| Parameter | Description | Default |
|----------|-------------|---------|
| `sentinel.config.port` | Sentinel port | `26379` |
| `sentinel.config.masterName` | Redis master name | `"mymaster"` |
| `sentinel.config.quorum` | Failover quorum | `2` |
| `sentinel.config.downAfterMilliseconds` | Down detection | `5000` |
| `sentinel.config.failoverTimeout` | Failover timeout | `10000` |
| `sentinel.config.parallelSyncs` | Parallel syncs | `1` |
| `sentinel.config.resolveHostnames` | Resolve hostnames | `"yes"` |
| `sentinel.config.announceHostnames` | Announce hostnames | `"yes"` |
| `sentinel.extraConfig` | Extra config | `{}` |

---

### **Sentinel Service**

| Parameter | Description | Default |
|----------|-------------|---------|
| `sentinel.service.type` | Service type | `ClusterIP` |
| `sentinel.service.port` | Service port | `26379` |
| `sentinel.service.targetPort` | Container port | `26379` |

---

## **Probes**

### **Redis Probes**

| Parameter | Description | Default |
|----------|-------------|---------|
| `probes.redis.liveness.initialDelaySeconds` | Initial delay | `10` |
| `probes.redis.liveness.timeoutSeconds` | Timeout | `5` |
| `probes.redis.liveness.periodSeconds` | Period | `5` |
| `probes.redis.liveness.failureThreshold` | Failure threshold | `10` |
| `probes.redis.readiness.initialDelaySeconds` | Initial delay | `5` |
| `probes.redis.readiness.timeoutSeconds` | Timeout | `15` |
| `probes.redis.readiness.periodSeconds` | Period | `2` |
| `probes.redis.readiness.successThreshold` | Success threshold | `2` |
| `probes.redis.readiness.failureThreshold` | Failure threshold | `40` |

---

### **Sentinel Probes**

| Parameter | Description | Default |
|----------|-------------|---------|
| `probes.sentinel.liveness.initialDelaySeconds` | Initial delay | `10` |
| `probes.sentinel.liveness.timeoutSeconds` | Timeout | `5` |
| `probes.sentinel.liveness.periodSeconds` | Period | `5` |
| `probes.sentinel.liveness.failureThreshold` | Failure threshold | `10` |
| `probes.sentinel.readiness.initialDelaySeconds` | Initial delay | `5` |
| `probes.sentinel.readiness.timeoutSeconds` | Timeout | `10` |
| `probes.sentinel.readiness.periodSeconds` | Period | `2` |
| `probes.sentinel.readiness.failureThreshold` | Failure threshold | `20` |

---

## **Init Scripts**

| Parameter | Description | Default |
|----------|-------------|---------|
| `scripts.redisInit` | Redis init script | `scripts/redis_init.sh` |
| `scripts.sentinelInit` | Sentinel init script | `scripts/sentinel_init.sh` |
---

## Upgrading

Upgrade the Helm release to apply configuration changes or update to a new chart version.

```bash
# Upgrade with new values file
helm upgrade my-redis coh/redis-cluster -f new-values.yaml

# Upgrade to specific chart version
helm upgrade my-redis coh/redis-cluster --version 1.1.0

# Upgrade single parameter
helm upgrade my-redis coh/redis-cluster \
  --set redis.resources.limits.memory=1Gi \
  --reuse-values
```

The chart uses StatefulSets with RollingUpdate strategy, upgrading one pod at a time. Sentinels automatically handle failover if the master is restarted during upgrade.

---

## Uninstalling

Remove the Helm release and optionally clean up persistent data.

```bash
# Delete the release
helm uninstall my-redis

# Delete PVCs (if persistence was enabled)
oc delete pvc -l app.openshift.io/instance=my-redis

# Verify cleanup
oc get all,pvc -l app.openshift.io/instance=my-redis
```

---

## Troubleshooting

### Pods Not Starting

Check init container logs for configuration errors, verify security context permissions, and ensure PVCs are bound.

```bash
# Check pod status and events
oc get pods -l app.openshift.io/instance=my-redis
oc describe pod my-redis-redis-0

# Check init container logs
oc logs my-redis-redis-0 -c config

# Check main container logs
oc logs my-redis-redis-0

# Verify PVC status
oc get pvc
```

Common causes: incorrect security context, resource constraints, storage provisioning failures, image pull errors.

### Master Not Detected

Verify password configuration, check network connectivity, and confirm Sentinel configuration.

```bash
# Check Sentinel status
oc exec my-redis-sentinel-0 -- redis-cli -p 26379 SENTINEL masters

# Verify password in secret
oc get secret my-redis-secret -o jsonpath='{.data.REDIS_PASSWORD}' | base64 -d

# Test connectivity
oc exec my-redis-sentinel-0 -- \
  redis-cli -h my-redis-redis-0.my-redis-headless -p 6379 -a <password> PING
```

Common causes: password mismatch, network policies blocking traffic, incorrect ConfigMap settings.

### Frequent Failovers

Increase detection timeouts, verify resource allocation, and check network stability.

```bash
# Check Sentinel logs for failover patterns
oc logs my-redis-sentinel-0 | grep -i failover

# Increase timeout
helm upgrade my-redis coh/redis-cluster \
  --set sentinel.config.downAfterMilliseconds=10000 \
  --reuse-values

# Increase resources
helm upgrade my-redis coh/redis-cluster \
  --set redis.resources.limits.memory=2Gi \
  --reuse-values
```

Common causes: aggressive timeouts, master resource exhaustion, network latency, node instability.

### Replication Lag

Monitor replication offset and increase replica resources if needed.

```bash
# Check replication status
oc exec my-redis-redis-0 -- redis-cli -a <password> INFO replication

# Check replica offset
oc exec my-redis-redis-1 -- redis-cli -a <password> INFO replication
```

Solutions: scale up replica resources, increase network bandwidth, reduce write load, enable diskless replication.

---

## Best Practices

### Security

* Always use strong passwords stored in openshift secrets
* Never commit passwords to version control
* Enable TLS for production environments (requires cert-manager)
* Use network policies to restrict pod communication
* Run containers as non-root users with security contexts
* Regularly rotate passwords

### High Availability

* Deploy minimum 3 Redis instances (1 master + 2 replicas)
* Deploy exactly 3 or 5 Sentinel instances (odd number for quorum)
* Enable pod disruption budgets to prevent too many simultaneous restarts
* Use pod anti-affinity to spread pods across nodes
* Deploy in different availability zones if possible

### Resource Management

* Set resource requests and limits based on workload
* Monitor memory usage and adjust `maxmemory` accordingly
* Use persistent storage for data that must survive restarts
* Configure appropriate storage class for performance needs
* Size PVCs based on dataset growth projections

### Monitoring

* Monitor Redis memory usage and eviction rates
* Track replication lag between master and replicas
* Alert on failover events
* Monitor Sentinel consensus and health
* Track client connection counts
* Use Prometheus exporters for metrics collection

---

## Support and Contributing

### Getting Help

* **Issues**: https://github.com/City-of-Helsinki/coh-helm-charts/issues

### Contributing

Contributions are welcome! Please fork the repository, create a feature branch, make your changes, and submit a pull request.

## Images per region

| Image | Sweden Central | West Europe |
|---|---|---|
| redis | `registry.redhat.io/rhel9/redis-7:9.7-1771417604` | same |
| sentinel | same as `redis.image` (unless `sentinel.image` is set) | same |
| Pull secret | none in the chart: OpenShift's cluster pull secret covers `registry.redhat.io` | same |

The Red Hat image sets its own `registry`, so `global.imageRegistry` does not change it; both
regions pull the same image. The tag is pinned in
`pipeline-templates/common/helm-values/images/redis-cluster.yaml`.

How the region is chosen: platform deployments (Azure DevOps, `pipeline-templates`) load
`common/helm-values/region-<se|we>.yaml` (sets `global.imageRegistry` / `global.imagePullSecrets`),
then `common/helm-values/images/<chart>.yaml` (repository + tag, single source of truth) and, for
West Europe only, `common/helm-values/images/we/<chart>.yaml` (legacy paths and pull secrets).
The region follows the service connection name: `*-se` = Sweden Central, anything else = West Europe.
Installing the chart directly (no pipeline) uses the chart defaults, i.e. the Sweden Central images.

---
## Changelog

### 1.2.0
* The chart owns the Redis password Secret (PLATTA-8196). New `redis.password.secretName`,
  `migrateFromSecret` / `migrateFromKey` and `keepOnUninstall`. See [Password ownership](#password-ownership).
* Fix: a generated password is now kept on upgrade. In 1.1.0 every `helm upgrade` without
  `existingSecret` generated a new password, while running pods kept the old one until restart.
* The Secret is annotated `helm.sh/resource-policy: keep` by default.
* `existingSecret` still works unchanged (legacy, rendered manifests identical to 1.1.0).

### 1.1.0
* `affinity` is now a regular Kubernetes affinity map. The built-in soft anti-affinity is
  still on by default (`podAntiAffinity.enabled: true`) and is used when `affinity` is empty;
  the old `affinity: {enabled: true|false}` switch keeps working.
* `redis.image` / `sentinel.image` as a map (`registry` / `repository` / `tag` / `digest`); a
  full reference string still works.
* Images: no registry hostnames in the templates any more. `global.imageRegistry`
  (default `image-registry.int.platta.hel.fi`, set per region by pipeline-templates),
  `global.imagePullSecrets`, and per image `registry` / `repository` / `tag` / `digest`.
* Pod scheduling: the same `nodeSelector` / `tolerations` / `affinity` keys as every coh chart,
  empty by default (any worker node), falling back to `global.*`.
* CI runs on the Sweden Central cluster (namespace `devops-toolchain`).

### Version 1.0.0
* Initial release with Redis 7.0 support
* Automatic failover with Sentinel
* Kubernetes and OpenShift compatible
* Configurable persistence and security contexts
* Pod disruption budgets and anti-affinity
* Comprehensive health probes

---

**Maintained By**: Platta Team  
**Last Updated**: November 2025
