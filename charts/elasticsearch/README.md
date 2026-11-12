# Elasticsearch Helm Chart

![Version: 0.2.0](https://img.shields.io/badge/version-0.2.0-blue)
![AppVersion: 9.5.5](https://img.shields.io/badge/appVersion-9.5.5-blue)

Elasticsearch for **new instances on the Sweden OpenShift (ARO) clusters**, run by the ECK
operator, with Platta managed Service TLS (OpenShift service CA). Basic licence only.

> **Status 0.2.0:** Elasticsearch with Platta service TLS and application users.
> Not included yet (later releases): NetworkPolicy, Kibana, default index replicas, backups.

## Prerequisites

Created in the namespace by platform admins via GitOps, **never by this chart**:

| Object | Details |
|---|---|
| ECK operator 3.x | OperatorGroup + Subscription `elasticsearch-eck-operator-certified` (OLM), one operator per namespace. The chart contains no operator and no CRDs. |
| ConfigMap `platta-service-ca` | Annotation `service.beta.openshift.io/inject-cabundle: "true"` (OpenShift fills in `service-ca.crt`). Not used by the chart or by Elasticsearch: **clients mount it themselves** to trust the Elasticsearch certificate (see [TLS for clients](#tls-for-clients)). The chart never creates or deletes it. |

Only when `users` is set: the **External Secrets Operator** (cluster-wide, installed by the
platform; on dev-se "External Secrets Operator for Red Hat OpenShift" 1.2.1). It generates the
user passwords. No SecretStore or Key Vault is needed.

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
| Application user secrets (see [Application users](#application-users)) | `elasticsearch-user-<name>` |

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
| `users` | `[]` | Application users, see [Application users](#application-users) |
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
`image.registry` only while `global.imageRegistry` is set.

The tag is always `version` (no `image.tag` or `image.digest`), and only `global.imagePullSecrets`
is used; this differs from the repo README's general image table on purpose.

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

## Application users

Applications never use the `elastic` superuser. Each application gets its own users, with
a role limited to its own indices:

```yaml
users:
  - name: myapp-indexer      # DNS label, max 44 characters
    role: write              # write or search
    indices: ["myapp-*"]     # required; index names or patterns
  - name: myapp-search
    role: search
    indices: ["myapp-*"]
```

| `role` | Index privileges on `indices` | Cluster privileges |
|---|---|---|
| `search` | `read`, `view_index_metadata` | `monitor` |
| `write` | `read`, `view_index_metadata`, `write`, `create_index`, `manage` | `monitor` |

**Which users?** One `write` user is enough for an application that both reads and writes.
Add a separate `search` user only for read-only clients, above all the **elastic-proxy**: it
is public and must never be able to write.

Rules (checked by the values schema): `role` is `search` or `write`; `indices` must not be `*`
(or only wildcards), must not start with `.` (system indices) and must not contain commas;
`name` must not be a built-in user (`elastic`, `kibana`, `kibana_system`, `logstash_system`,
`beats_system`, `apm_system`, `remote_monitoring_user`) or start with `elastic-internal`
(ECK's own users); every name only once.

### How it works

* Per user the chart creates a `Password` generator and an `ExternalSecret`, both named
  `elasticsearch-user-<name>`. External Secrets generates a 32-character alphanumeric password
  and writes the Secret `elasticsearch-user-<name>` (type `kubernetes.io/basic-auth`) with the
  keys `username`, `password` and `roles`. The password never passes through Helm or the
  pipeline, and teams cannot set their own.
* **When the password changes:** the ExternalSecrets use `refreshPolicy: OnChange` with
  `refreshInterval: "0"`. External Secrets syncs, and so generates a new password, only when
  the ExternalSecret itself changes: its spec, labels or annotations. In practice that means a
  `force-sync` (see [Changing a password](#changing-a-password)). Normal chart upgrades leave
  the ExternalSecret unchanged: it carries no version labels, and roles are named after the
  user, so a role or index change only touches `roles.yml`.
  (Without `OnChange`, the default `Periodic` policy with interval 0 never syncs again and
  ignores `force-sync`; verified on dev-se.)
* The Secret `<fullname>-roles` (key `roles.yml`) holds one Elasticsearch role per user,
  named after the user only: `elasticsearch-user-<name>` (e.g.
  `elasticsearch-user-myapp-indexer`), never after `search`/`write`. So the role name in the
  user Secret never changes, and switching the role cannot rotate the password.
* The Elasticsearch resource lists the user Secrets under `spec.auth.fileRealm` and the roles
  Secret under `spec.auth.roles`; ECK loads them into Elasticsearch's file realm.

Check that the passwords exist: `oc get externalsecret -n <namespace>` (STATUS `SecretSynced`).

### Using a user in an application

Read the Secret into environment variables:

```yaml
env:
  - name: ELASTICSEARCH_URL
    value: https://elasticsearch-es-http.<namespace>.svc:9200
  - name: ELASTICSEARCH_USERNAME
    valueFrom:
      secretKeyRef:
        name: elasticsearch-user-myapp-indexer
        key: username
  - name: ELASTICSEARCH_PASSWORD
    valueFrom:
      secretKeyRef:
        name: elasticsearch-user-myapp-indexer
        key: password
```

The client also needs the CA (see [TLS for clients](#tls-for-clients)).

### elastic-proxy (nginx-standard)

Point `upstreamAuth` at a `search` user:

```yaml
elasticProxy:
  upstreamAuth:
    enabled: true
    secretName: elasticsearch-user-myapp-search
    username: myapp-search          # the user's name (not read from the Secret)
    passwordKey: password
  upstream:
    url: https://elasticsearch-es-http.<namespace>.svc.cluster.local:9200
```

### Changing a password

```bash
oc annotate externalsecret elasticsearch-user-<name> force-sync=$(date +%s) --overwrite -n <namespace>
```

The annotation changes the ExternalSecret, so External Secrets syncs (`refreshPolicy: OnChange`),
generates a new password and updates the Secret, and ECK updates the user in Elasticsearch. Pods do not notice a changed Secret: **restart the applications** that use it
(e.g. `oc rollout restart deployment/<app>`).

Other changes:

| Change in values | Effect |
|---|---|
| `indices` | Only the roles Secret changes; **the password stays**. |
| `role` (`search` ↔ `write`) | Only the privileges in the roles Secret change; **the password stays**. |
| User removed | Its ExternalSecret, Password and Secret are deleted, and ECK removes the user. |
| Chart or Elasticsearch upgrade | Passwords stay (the ExternalSecrets carry no version labels on purpose). |
| Anything else that edits the ExternalSecret (spec, labels, annotations) | **New password**, like `force-sync`. Do not edit the ExternalSecrets by hand. |

## Objects the chart creates

Needed for the rights of the application team's pipeline service account in its namespace:

| Kind | API group |
|---|---|
| `Elasticsearch` | `elasticsearch.k8s.elastic.co/v1` |
| `Secret` (`<fullname>-roles` when `users` is set, and the Helm release records `sh.helm.release.v1.*`) | core |
| `ExternalSecret` (one per user) | `external-secrets.io/v1` |
| `Password` (one per user) | `generators.external-secrets.io/v1alpha1` |

On dev-se, the namespace roles `admin` and `edit` already include all of these (checked
Nov 2026).

Everything else (StatefulSet, Services, Secrets, PVCs, PDB) is created by the ECK operator, and
the user Secrets `elasticsearch-user-<name>` by External Secrets.

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
* **One release with `users` per namespace.** The user Secrets are named
  `elasticsearch-user-<name>` without the release name, so two releases in the same namespace
  cannot both define users with the same name (Helm refuses the second one).
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

This test predates the mirror image default (the image then came from `docker.elastic.co`).
To repeat it on the sandbox now, add [values-sandbox.yaml](values-sandbox.yaml):
`-f values-dev-1node.yaml -f values-sandbox.yaml`.

**dev-se (Nov 2026):** the default mirror image 9.5.5 pulls without a pull secret; green/Ready.

**Application users, 12 Nov 2026**, dev-se, namespace `hki-platta-elastic-smoketest-test`, chart
0.2.0 (branch `feat/PLATTA-7443-elasticsearch-users`), a `write` and a `search` user:

* ECK picks up the user Secrets that External Secrets creates after the Elasticsearch resource:
  both users authenticate via the file realm with their own roles.
* Privileges per role: the `write` user gets 201 on its own index and 403 on another index; the
  `search` user gets 200 on its own index, 403 when writing and 403 on another index.
* A normal upgrade (no changes) keeps the passwords.
* `force-sync` with `refreshPolicy: OnChange` rotates the password: the old one gets 401, the new
  one 200. (Before `OnChange`, `force-sync` was ignored and the old password kept working.)
* Adding `refreshPolicy` to existing ExternalSecrets rotated each password once, as expected.
* Switching `myapp-search` from `search` to `write` kept its password, and the new privileges
  applied at once: writing gave 201 (403 before the switch).
* Removing a user deleted its ExternalSecret and Secret, and Elasticsearch then rejected the
  user (401).

## Still to test

1. Kibana (when it is added): does Kibana trust the Elasticsearch certificate? ECK gives Kibana
   the CA from `ca.crt`, which the OpenShift-generated Secret lacks; if needed, mount
   `platta-service-ca` into Kibana and set `elasticsearch.ssl.certificateAuthorities`.
2. *Low priority:* Elasticsearch 9.4.x with the clusters' ECK version (9.5.5 is tested).
3. Application users: the elastic-proxy (nginx-standard) works with a `search` user.
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

### 0.2.0

Application users (PLATTA-7443):

* **`users`:** a list of `name`, `role` (`search` or `write`) and `indices`. Each user gets an
  Elasticsearch role named after the user (`elasticsearch-user-<name>`) and limited to its
  indices, in the Secret `<fullname>-roles` (`roles.yml`), and is added to ECK's file realm.
* **Passwords:** generated by External Secrets (a `Password` generator and an
  `ExternalSecret` per user with `refreshPolicy: OnChange`, no SecretStore) into the Secret
  `elasticsearch-user-<name>` (`kubernetes.io/basic-auth`: `username`, `password`, `roles`);
  never by Helm. A new password only with `force-sync`; chart and Elasticsearch upgrades and
  role or index changes keep the passwords.
* **Values schema:** rejects other roles, missing indices, the index patterns `*` and `.*`,
  and reserved user names.
* **Examples and docs:** a write and a search user in
  [values-dev-1node.yaml](values-dev-1node.yaml); NOTES lists the user Secrets; README section
  [Application users](#application-users), including the elastic-proxy setup.
* Requires the External Secrets Operator on the cluster when `users` is set.
* Tested on dev-se (12 Nov 2026), see [Tested](#tested); the elastic-proxy with a `search`
  user is [still to test](#still-to-test).

### 0.1.0

First release (PLATTA-7443): a skeleton that runs one Elasticsearch instance through ECK.

* **Elasticsearch:** one nodeSet `default`, `nodeCount` 1 or 3, every node master + data + ingest;
  `version` 9.4.x / 9.5.x (default 9.5.5); `node.store.allow_mmap: false`.
* **Storage:** storage class `platta-azure-ssd-lrs` (fixed), `storage.size` grow-only,
  `volumeClaimDeletePolicy: DeleteOnScaledownOnly` (data volumes kept on uninstall).
* **TLS:** Platta managed Service TLS from the OpenShift service CA (`platta-<name>-es-http-tls`);
  transport TLS from ECK. Clients mount `platta-service-ca` themselves.
* **Image:** the official Elastic image from Platta's mirror by default
  (`image-registry.int.platta.hel.fi/mirrored-images/elasticsearch/elasticsearch:<version>`),
  registry resolved like nginx-standard (`image.registry`, else `global.imageRegistry`);
  `docker.elastic.co` for the sandbox via [values-sandbox.yaml](values-sandbox.yaml).
  `global.imagePullSecrets` passed to the pods.
* **Values schema:** rejects unknown keys and anything the chart fixes (storage class, other
  images, image tags, 7.x/8.x versions, nodeCount other than 1 or 3).
* **Examples:** [values-dev-1node.yaml](values-dev-1node.yaml), [values-sandbox.yaml](values-sandbox.yaml).
* **Docs:** prerequisites, TLS for clients, objects created, known limitations, test results,
  maintenance checklist. NOTES.txt shows the endpoints, including the full `.svc.cluster.local`
  name the elastic-proxy needs.
* **CI:** PR and release workflows with lint, unit tests and schema checks.
* Tested on the sandbox (28 Oct 2026) and dev-se (Nov 2026).
