# Elasticsearch Helm Chart

![Version: 0.1.0](https://img.shields.io/badge/version-0.1.0-blue)
![AppVersion: 9.5.5](https://img.shields.io/badge/appVersion-9.5.5-blue)

Elasticsearch for **new instances on the Sweden OpenShift (ARO) clusters**, run by the ECK
operator, with Platta managed Service TLS (OpenShift service CA). Basic licence only.

> **Status 0.1.0: skeleton.** Proves that Elasticsearch starts with Platta service TLS.
> Not included yet (later releases): application users and roles, NetworkPolicy, Kibana,
> default index replicas, backups.

## Prerequisites

Created in the namespace by platform admins via GitOps, **never by this chart**:

| Object | Details |
|---|---|
| ECK operator 3.x | OperatorGroup + Subscription `elasticsearch-eck-operator-certified` (OLM), one operator per namespace. The chart contains no operator and no CRDs. |
| ConfigMap `platta-service-ca` | Annotation `service.beta.openshift.io/inject-cabundle: "true"` (OpenShift fills in `service-ca.crt`). The chart only references it; the name is `serviceCA.configMapName`. **Required**: the Elasticsearch pods do not start without it. |

## Install and upgrade

From the application team's Azure DevOps pipeline:

```bash
helm upgrade --install elasticsearch <chart> -n <namespace> -f elasticsearch-values.yaml
```

Example values for a 1-node dev instance: [values-dev-1node.yaml](values-dev-1node.yaml).

The release name becomes the Elasticsearch name (`elasticsearch` for the command above;
other names get the suffix `-elasticsearch`, max 36 characters). ECK then creates:

| Object | Name (release `elasticsearch`) |
|---|---|
| HTTPS service, port 9200 | `elasticsearch-es-http` |
| Pods | `elasticsearch-es-default-0` … |
| TLS secret (created by the OpenShift service CA) | `platta-elasticsearch-es-http-tls` |
| `elastic` superuser secret (admins only, never for apps) | `elasticsearch-es-elastic-user` |

## Values

Every value is validated by [values.schema.json](values.schema.json). Unknown keys are rejected.

| Value | Default | Allowed |
|---|---|---|
| `version` | `9.5.5` | `9.4.x`, `9.5.x` (the two newest maintained 9.x minors). Upgrade only. |
| `nodeCount` | `1` | `1` or `3`. Every node is master + data + ingest. |
| `storage.size` | `10Gi` | `<n>Gi` or `<n>Ti`. **Can only grow**: Kubernetes and ECK cannot shrink a volume. To get smaller disks, create a new instance and reindex/restore. |
| `resources` | requests `500m`/`2Gi`, limit `2Gi` | `limits.memory` is required. Elasticsearch sets the JVM heap to half of it. Keep `requests.memory` = `limits.memory`. |
| `serviceCA.configMapName` | `platta-service-ca` | Existing ConfigMap with `service-ca.crt` |
| `serviceCA.mountInElasticsearch` | `true` | Mount the service CA into the pods and set `xpack.security.http.ssl.certificate_authorities` (see *To test in the sandbox*) |
| `global.imageRegistry` | `""` | Empty = `docker.elastic.co` (ECK default). Otherwise a mirror of the official image: `<registry>/elasticsearch/elasticsearch:<version>` |
| `nodeSelector`, `tolerations`, `affinity` | empty | Same as every coh chart (fall back to `global.*`). Without `affinity`, ECK spreads the nodes over workers. |

**Fixed by the chart (not overridable):** storage class `platta-azure-ssd-lrs`, HTTP TLS
from the OpenShift service CA, transport (node-to-node) TLS from ECK's own certificates,
no Route (public access only through the nginx-standard elastic-proxy), ECK's default
PodDisruptionBudget, `node.store.allow_mmap: false`, no plugins, init containers or custom
images, and `volumeClaimDeletePolicy: DeleteOnScaledownOnly` (`helm uninstall` keeps the data
volumes; delete the PVCs by hand to remove the data).

## TLS for clients

The HTTP certificate is issued by the OpenShift service CA for
`<name>-es-http.<namespace>.svc` (and `.svc.cluster.local`).

* **Application backends** mount the ConfigMap `platta-service-ca` and point their
  Elasticsearch client's CA setting at `service-ca.crt`. Connect with the service name,
  e.g. `https://elasticsearch-es-http.<namespace>.svc:9200`, never with a pod IP.
* **elastic-proxy** (nginx-standard): currently uses `proxy_ssl_verify off`, so it needs no CA.
  Upstream URL: `https://<name>-es-http.<namespace>.svc:9200`.

## Objects the chart creates

Needed for the rights of the application team's pipeline service account in its namespace:

| Kind | API group |
|---|---|
| `Elasticsearch` | `elasticsearch.k8s.elastic.co/v1` |
| `Secret` (Helm release records `sh.helm.release.v1.*` only) | core |

Everything else (StatefulSet, Services, Secrets, PVCs, PDB) is created by the ECK operator.

## To test in the sandbox

1. Does the ECK operator trust the service-CA certificate (no `ca.crt` in the Secret)?
2. Does ECK recover when `platta-<name>-es-http-tls` does not exist yet? The service CA only
   creates it after ECK has created the `<name>-es-http` Service.
3. Does Elasticsearch need the service CA mount and `certificate_authorities` at all? Test
   with `serviceCA.mountInElasticsearch: false`, and check that ECK keeps our setting.
4. Can the Sweden ARO clusters pull from `docker.elastic.co`, or do we need a mirror
   (`global.imageRegistry`)?
5. Does the storage class `platta-azure-ssd-lrs` have `allowVolumeExpansion: true` (needed to grow `storage.size`)?
6. Does the ECK 3.x version on the clusters support Elasticsearch 9.4 and 9.5?
7. `vm.max_map_count` on the nodes: could `node.store.allow_mmap` be turned back on?

## Changelog

### 0.1.0

* First version (PLATTA-7443): one nodeSet (1 or 3 nodes, master + data + ingest),
  storage class `platta-azure-ssd-lrs`, Platta managed Service TLS, values schema.
