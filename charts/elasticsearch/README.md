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
| ConfigMap `platta-service-ca` | Annotation `service.beta.openshift.io/inject-cabundle: "true"` (OpenShift fills in `service-ca.crt`). Not used by the chart or by Elasticsearch: **clients mount it themselves** to trust the Elasticsearch certificate (see [TLS for clients](#tls-for-clients)). The chart never creates or deletes it. |

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
| `image.registry` | `""` (= `global.imageRegistry`) | See [Image](#image): empty, the Platta mirror, or `docker.elastic.co`. Wins over `global.imageRegistry` when set. |
| `image.repository` | `mirrored-images/elasticsearch/elasticsearch` | `elasticsearch/elasticsearch` together with `docker.elastic.co` |
| `global.imageRegistry` | `image-registry.int.platta.hel.fi` | Registry for images that do not set their own `image.registry` (same as the other coh charts) |
| `global.imagePullSecrets` | `[]` | Pull secrets for the Elasticsearch pods, `{name: x}` or plain names |
| `nodeSelector`, `tolerations`, `affinity` | empty | Same as every coh chart (fall back to `global.*`). Without `affinity`, ECK spreads the nodes over workers. |

**Fixed by the chart (not overridable):** storage class `platta-azure-ssd-lrs`, HTTP TLS
from the OpenShift service CA, transport (node-to-node) TLS from ECK's own certificates,
no Route (public access only through the nginx-standard elastic-proxy), ECK's default
PodDisruptionBudget, `node.store.allow_mmap: false`, no plugins, init containers or custom
images, and `volumeClaimDeletePolicy: DeleteOnScaledownOnly` (`helm uninstall` keeps the data
volumes; see [Known limitations](#known-limitations) to delete them).

## Image

The chart always runs the **official Elastic image**, tagged with `version`:

```text
image-registry.int.platta.hel.fi/mirrored-images/elasticsearch/elasticsearch:<version>   # default (Platta mirror)
```

* The registry resolves like in nginx-standard: `image.registry` if set, otherwise
  `global.imageRegistry` (default `image-registry.int.platta.hel.fi`; `region-se.yaml` sets the
  same registry for dev-se/prod).
* **Every new Elasticsearch version must be added to the mirror's tags before it is used**,
  otherwise the pods cannot pull the image.
* The sandbox cannot reach the mirror and pulls directly from Elastic instead. The explicit
  `image.registry` wins, so this works even if `global.imageRegistry` is set:

  ```bash
  helm upgrade --install elasticsearch <chart> -n <namespace> -f elasticsearch-values.yaml \
    --set image.registry=docker.elastic.co --set image.repository=elasticsearch/elasticsearch
  ```

The schema accepts only these two registry/repository combinations, and an empty
`image.registry` only while `global.imageRegistry` is set. There is no `image.tag` or
`image.digest`.

## TLS for clients

The HTTP certificate is issued by the OpenShift service CA for
`<name>-es-http.<namespace>.svc` (and `.svc.cluster.local`). Elasticsearch itself needs no CA
for it; only clients do.

* **Application backends** mount the ConfigMap `platta-service-ca` themselves (the chart does
  not do it for them) and point their Elasticsearch client's CA setting at `service-ca.crt`.
  Connect with the service name,
  e.g. `https://elasticsearch-es-http.<namespace>.svc:9200`, never with a pod IP.
* **elastic-proxy** (nginx-standard): currently uses `proxy_ssl_verify off`, so it needs no CA.
  Upstream URL must be the full name `https://<name>-es-http.<namespace>.svc.cluster.local:9200`,
  because nginx resolves without search domains.

## Objects the chart creates

Needed for the rights of the application team's pipeline service account in its namespace:

| Kind | API group |
|---|---|
| `Elasticsearch` | `elasticsearch.k8s.elastic.co/v1` |
| `Secret` (Helm release records `sh.helm.release.v1.*` only) | core |

Everything else (StatefulSet, Services, Secrets, PVCs, PDB) is created by the ECK operator.

## Known limitations

* **Single-node instances turn yellow once an app creates an index.** Elasticsearch's default of
  1 replica per index cannot be placed on a single node. Effects:
  * anything that waits for green, e.g. a pipeline step calling
    `_cluster/health?wait_for_status=green`, times out;
  * ECK's default PodDisruptionBudget blocks pod eviction while the cluster is not green,
    which can hold up node maintenance.

  Until the chart sets a default, applications on 1-node instances must create their indices
  (or index templates) with `"number_of_replicas": 0`:

  ```text
  PUT my-index
  { "settings": { "number_of_replicas": 0 } }
  ```

* **The mirror must have the Elasticsearch version's tag before it can be used.** The pods pull
  `image-registry.int.platta.hel.fi/mirrored-images/elasticsearch/elasticsearch:<version>`
  (or the same path under another `global.imageRegistry`); if that tag has not been mirrored yet, they
  cannot start. Add the tag to the mirror first, then install or upgrade.
* **Data volumes are kept on uninstall** (`volumeClaimDeletePolicy: DeleteOnScaledownOnly`).
  `helm uninstall` removes Elasticsearch, but its PVCs (`elasticsearch-data-<name>-es-default-<n>`)
  stay, and so do the Azure disks behind them, which keep costing money. If the data is not
  needed, delete them once the pods are gone (**irreversible**):

  ```bash
  NS=<namespace>; NAME=elasticsearch        # Elasticsearch name (= release name, see above)
  oc get pvc -n "$NS" -o name | grep "^persistentvolumeclaim/elasticsearch-data-${NAME}-es-"
  oc get pvc -n "$NS" -o name | grep "^persistentvolumeclaim/elasticsearch-data-${NAME}-es-" \
    | xargs oc delete -n "$NS"
  ```

## Tested

**28 Oct 2026**, sandbox cluster, namespace `elastic-smoketest`, ECK operator 3.1.0 (OLM),
storage class `platta-azure-ssd-lrs`, [values-dev-1node.yaml](values-dev-1node.yaml):

* Elasticsearch 9.5.5 reached green / Ready.
* It serves the Platta certificate (issuer `openshift-service-serving-signer`, subject
  `es-elasticsearch-es-http.elastic-smoketest.svc`).
* The ECK operator accepts the certificate without `ca.crt` in the Secret, and copes with the
  Secret appearing after the Service.
* Without the service CA mount and `xpack.security.http.ssl.certificate_authorities`,
  Elasticsearch stayed green and served the same certificate, so the chart no longer sets them.
* The OLM-installed operator pod has the label `control-plane=elastic-operator` (for the
  NetworkPolicy in a later release).
* Growing `storage.size` from 5Gi to 8Gi worked.
* Sandbox and dev-se can pull directly from `docker.elastic.co` (sandbox imageID
  `docker.elastic.co/elasticsearch/elasticsearch@sha256:13b4a40b...`).

## To test in the sandbox

1. dev-se: the default (mirror) image pulls; the mirror has the 9.5.5 tag; no pull secret needed.
2. Kibana (when it is added): does Kibana trust the Elasticsearch certificate? ECK gives Kibana
   the CA from `ca.crt`, which the OpenShift-generated Secret lacks; if needed, mount
   `platta-service-ca` into Kibana and set `elasticsearch.ssl.certificateAuthorities`.
3. *Low priority:* Elasticsearch 9.4.x with the clusters' ECK version (9.5.5 is tested).
4. *Optional performance optimization, not a blocker:* `vm.max_map_count` on the nodes: could
   `node.store.allow_mmap` be turned back on?

## Maintenance

| When | Check | If something changed |
|---|---|---|
| New Elasticsearch version (patch or minor) | Is it newer than the chart's default `version`? Has an old minor lost Elastic's support? | (1) Add the tag to the Quay mirror (`mirrored-images/elasticsearch/elasticsearch`) first. (2) Update the allowed versions in `values.schema.json`, the default `version`, `appVersion` in `Chart.yaml`, and the tests. (3) Release the chart and test it on the sandbox and the dev-se smoke namespace. (4) Tell the teams on minors nearing end of life. |
| New ECK version | Release notes: deprecated fields that our template uses; supported Elasticsearch and OpenShift versions. | Edit the template if needed. Rehearse the upgrade: sandbox → dev-se smoke namespace → teams. |
| OpenShift upgrade on a cluster | Does the running ECK version support the new OpenShift version? | If not, upgrade ECK first. |
| Now and then | Do the Quay mirror's sync logs still succeed? Any GitHub Actions deprecation warnings in CI (repo-wide)? | Fix the mirror sync; act on the warnings. |

These checks are part of Platta's monthly upgrade/update evaluation (see the Elasticsearch support standard in Confluence).

## Changelog

### 0.1.0

* First version (PLATTA-7443): one nodeSet (1 or 3 nodes, master + data + ingest),
  storage class `platta-azure-ssd-lrs`, Platta managed Service TLS, official Elastic image
  from Platta's mirror by default, `global.imagePullSecrets`, values schema.
  Tested on the sandbox cluster on 28 Oct 2026.
