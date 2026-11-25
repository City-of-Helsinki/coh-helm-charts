# Elasticsearch Helm Chart

![Version: 0.4.0](https://img.shields.io/badge/version-0.4.0-blue)
![AppVersion: 9.5.5](https://img.shields.io/badge/appVersion-9.5.5-blue)

Elasticsearch for **new instances on the Sweden OpenShift (ARO) clusters**, run by the ECK
operator, with Platta managed Service TLS (OpenShift service CA). Basic licence only.

> **Status 0.4.0:** Elasticsearch with Platta service TLS, application users and default index
> replicas, optional backups. Not included yet (later releases): NetworkPolicy, Kibana.

## Prerequisites

Created in the namespace by platform admins via GitOps, **never by this chart**:

| Object | Details |
|---|---|
| ECK operator 3.x | OperatorGroup + Subscription `elasticsearch-eck-operator-certified` (OLM), one operator per namespace. The chart contains no operator and no CRDs. |
| ConfigMap `platta-service-ca` | Annotation `service.beta.openshift.io/inject-cabundle: "true"` (OpenShift fills in `service-ca.crt`). Elasticsearch itself does not need it. The chart's [index-defaults Job](#default-index-replicas) mounts it, and **application clients mount it themselves** to trust the Elasticsearch certificate (see [TLS for clients](#tls-for-clients)). The chart never creates or deletes it. Without it, the Job cannot start and the install fails. |

**With backups** (optional): an Azure blob container, a SAS token for it and a Secret with
the keys `account` and `sas_token`, see [Backups](#backups).

The **External Secrets Operator** (cluster-wide, installed by the platform; on dev-se "External
Secrets Operator for Red Hat OpenShift" 1.2.1). It generates the user passwords, including the
chart's own technical user (since 0.3.0, so it is needed even without `users`). No SecretStore
or Key Vault is needed.

## Install and upgrade

From the application team's Azure DevOps pipeline:

```bash
helm upgrade --install elasticsearch <chart> -n <namespace> -f elasticsearch-values.yaml --timeout 15m
```

**Helm waits for the [index-defaults Job](#default-index-replicas)** after every install and
upgrade. On a first install the Job can only finish once Elasticsearch has started (about
5 minutes for 3 nodes), so Helm's default `--timeout` of 5 minutes is too short: use
`--timeout 15m`, and make sure the pipeline step's own timeout allows it too. Upgrades of a
running instance usually take seconds. **Turning on backups** restarts the nodes (new keystore
settings) while Helm waits for the [backup Job](#backups); 15 minutes cover that too.

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
| Technical user secret (index-defaults Job only, see [Default index replicas](#default-index-replicas)) | `elasticsearch-platta-defaults` |
| Technical user secret (backup Job only, with `backup.enabled`, see [Backups](#backups)) | `elasticsearch-platta-backup` |

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
| `backup.enabled` | `false` | Nightly snapshots to Azure, see [Backups](#backups). Schedule and retention are fixed. |
| `backup.secretName` | `""` | Required with backups: the admins' Secret with the keys `account` and `sas_token` |
| `backup.container` | `""` | Required with backups: the Azure blob container, e.g. `elastic-smoketest-test-snapshots` |
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
(ECK's own users) or `platta-` (the chart's technical users); every name only once.

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

## Default index replicas

Every new index in **the index patterns declared for the chart's users** (`users[].indices`)
gets **`index.auto_expand_replicas: "0-1"`** unless the application sets its own replicas:
0 replicas on a 1-node instance (so it stays green), 1 replica on 3 nodes.
Elasticsearch adjusts existing indices with this setting automatically when `nodeCount`
changes.

### How it works

The chart stores two templates in Elasticsearch:

| Template | Content |
|---|---|
| Component template `platta-defaults` | Only `settings.index.auto_expand_replicas: "0-1"` |
| Index template `platta-default-replicas` | `index_patterns`: the users' patterns (all `users[].indices`, search and write, deduplicated and sorted), `composed_of: ["platta-defaults"]`, `priority: 0` (the lowest) |

Applications can create indices only inside their users' patterns, so the template covers
exactly the indices they can create. Indices created outside them, for example by an
administrator as `elastic`, do not get the default. The patterns are never `"*"`: the
schema forbids `"*"` and dot-patterns, and a `"*"` would overlap Elasticsearch's built-in
templates for dot (system and hidden) indices, such as `.monitoring-*-mb`. Those also have
priority 0, and Elasticsearch refuses overlapping templates with the same priority.

**Without users** there is no index template: the Job stores only `platta-defaults` and
deletes `platta-default-replicas` if it exists, so removing all users leaves no stale
template behind. Changing a user's `indices` changes the patterns on the next upgrade.

* The Job `<fullname>-index-defaults` stores them after every `helm install` and `helm upgrade`
  (Helm hook; bodies in the ConfigMap `<fullname>-index-defaults`). It overwrites them each
  time, so manual edits do not last.
* It runs on the chart's Elasticsearch image, trusts the certificate through `platta-service-ca`,
  and logs in as the technical user `platta-defaults`. That user's role has only the cluster
  privilege `manage_index_templates` and no access to any index. Its password is generated
  like the application users' (Secret `<fullname>-platta-defaults`).
* It retries until Elasticsearch answers and ECK has loaded the user, and gives up after
  15 minutes. A failed Job fails the Helm release and stays in the namespace until the next
  run, for its logs:

  ```bash
  oc logs job/<fullname>-index-defaults -n <namespace>
  ```

### Your own index templates

Elasticsearch applies **only one index template** to a new index: the matching one with the
highest priority. So:

* **Use `"priority": 1` or higher.** Elasticsearch refuses two index templates with
  overlapping patterns and the same priority, and `platta-default-replicas` matches your
  users' patterns with priority 0. (A template without `priority` has priority 0.) If such a template
  already exists, the Job fails and prints the names of the conflicting templates, as
  Elasticsearch reports them. If one is yours, raise its priority and run the upgrade again;
  if none is, tell Platta.
* **Add `"composed_of": ["platta-defaults"]`** to keep the default replicas in indices your
  template matches. Everything else in your template is yours.

```text
PUT _index_template/myapp
{
  "index_patterns": ["myapp-*"],
  "priority": 1,
  "composed_of": ["platta-defaults"],
  "template": { "mappings": { ... } }
}
```

* An explicit `number_of_replicas` (or `auto_expand_replicas`) in your template or in the
  create-index request **overrides** the default. On a 1-node instance, any replicas above 0
  turn the cluster yellow again.
* Templates apply to **new indices only**. Indices that already exist keep their settings; on a
  1-node instance, fix an old yellow index with:

  ```text
  PUT my-index/_settings
  { "index": { "auto_expand_replicas": "0-1" } }
  ```

### Upgrading from 0.2.0

The upgrade adds the technical user `platta-defaults` to `spec.auth` (its Secret is added to
`fileRealm`, its role to the roles Secret, which is now always rendered). ECK applies this to
the running nodes. Existing application users and their passwords are unchanged.

## Backups

Optional (`backup.enabled: true`): nightly snapshots of all indices and data streams to an Azure
blob container. The schedule and retention are fixed; teams cannot change them.

### What the admins provide

Before `backup.enabled` is set, in this order:

1. **A blob container** per project and environment, e.g. `elastic-smoketest-test-snapshots`, in
   the private ops storage account. It must be reachable from the cluster (storage firewall /
   private endpoint).
2. **A SAS token** for that container (service SAS, HTTPS only) with the permissions
   **read, add, create, write, delete, list** (`racwdl`), and an expiry date (e.g. one year),
   without a leading `?`.
3. **A Secret in the namespace, created by an ExternalSecret** (never by the chart), with two keys:

   | Key | Value |
   |---|---|
   | `account` | storage account name |
   | `sas_token` | the SAS token |

   Its name goes into `backup.secretName`.

### Values

```yaml
backup:
  enabled: true
  secretName: elastic-smoketest-snapshots          # the admins' Secret
  container: elastic-smoketest-test-snapshots      # the admins' container
```

### What happens

| Where | What |
|---|---|
| Elasticsearch keystore | ECK `spec.secureSettings` maps `account` and `sas_token` to `azure.client.default.account` and `azure.client.default.sas_token`. **Enabling backups restarts the nodes one by one** (new keystore). |
| Technical user `platta-backup` | Created like `platta-defaults` (Secret `<fullname>-platta-backup`). Role, least privilege: `manage_slm` (create the policy), `create_snapshot` (what SLM runs as), `cluster:admin/repository/put` (register the repository; the only named privilege covering it is `manage`, which is far too broad). No index privileges. |
| Job `<fullname>-backup` | Helm hook after every install and upgrade, like the index-defaults Job. Logs in as `platta-backup` and PUTs the repository and the policy (bodies in the ConfigMap `<fullname>-backup`). A 400 (wrong body) or 403 (a privilege missing from the role) fails it at once; anything else (Elasticsearch restarting, the user not loaded yet (401), repository verification failing on a node that has not restarted yet) is retried for up to 15 minutes. |
| Repository `platta-backup` | `type: azure`, `container: <backup.container>`, `base_path: <fullname>` (two instances in one container never share a path), client `default`. Verified on every node when registered: a wrong token or container fails the Job. |
| SLM policy `platta-nightly` | Schedule `0 0 0 * * ?`: **00:00 UTC**, i.e. 02:00 in Helsinki in winter and 03:00 in summer (SLM cron is always UTC and has no time zone option). Snapshot names `nightly-<date>-<id>`. Retention: deleted after **30 days**, but at least **5** and at most **40** are kept. |

**`include_global_state: false`.** The snapshots hold indices and data streams only. Restoring
global state would bring back old persistent cluster settings (for example ECK's shard
allocation excludes from a downscale), old index templates and system feature states over a
running cluster. The Platta templates are recreated by the index-defaults Job; **team index
templates are not in the snapshots**, so teams keep them in their application (as they should
anyway).

**SLM runs with the privileges of the user who last updated the policy.** That is
`platta-backup` after every Helm run. If an admin edits the policy by hand as `elastic`, the
snapshots run as `elastic` until the next `helm upgrade` resets it.

### Token renewal

When the SAS token expires, snapshots fail. Renew it before then: put the new token where the
ExternalSecret reads it; External Secrets updates the Secret. With **ECK 3.1** (the clusters'
version) **every change to the Secret restarts the Elasticsearch nodes one by one**, so plan
the renewal (yearly) in an announced window: a 1-node instance is unavailable for a minute or
two, a 3-node instance stays available. No `helm upgrade` is needed.

*Later, after ECK 3.5:* the annotation `eck.k8s.elastic.co/file-based-secure-settings: "true"`
on the Elasticsearch resource applies changed secure settings without a restart (Elasticsearch
9.5 and later; both Azure settings are reloadable). Turning it on restarts the nodes once.

### Status (for monitoring, PLATTA-7446)

Nothing is monitored yet. SLM's status can be read with the `elastic` user or a user with
`read_slm` (and `monitor_snapshot` for the snapshot list):

| Request | Shows |
|---|---|
| `GET _slm/policy/platta-nightly?human` | `last_success`, `last_failure` (with the error), `next_execution`, counts of taken, failed and deleted snapshots |
| `GET _slm/stats` | totals for all policies, including retention runs and failures |
| `GET _slm/status` | `operation_mode`: `RUNNING` (SLM stopped otherwise) |
| `GET _cat/snapshots/platta-backup?v&s=end_epoch` | every snapshot with its state (`SUCCESS`, `PARTIAL`, `FAILED`) |

### Restore runbook

Run by an administrator with `oc` access to the namespace. **Credentials are read from Secrets,
never typed**, and go into the pod through stdin, never onto a command line.

1. Variables and access (on your workstation):

   ```bash
   NS=<namespace>; ES=<fullname>                 # e.g. elasticsearch (= release name, see above)
   POD=$ES-es-default-0
   ELASTIC_PASSWORD=$(oc get secret "$ES-es-elastic-user" -n "$NS" -o jsonpath='{.data.elastic}' | base64 -d)
   # netrc and the service CA into the pod (stdin; nothing on a command line)
   printf 'machine %s login elastic password %s\n' "$ES-es-http.$NS.svc" "$ELASTIC_PASSWORD" \
     | oc exec -i -n "$NS" "$POD" -c elasticsearch -- sh -c 'umask 077; cat > /tmp/restore.netrc'
   unset ELASTIC_PASSWORD
   oc get configmap platta-service-ca -n "$NS" -o jsonpath='{.data.service-ca\.crt}' \
     | oc exec -i -n "$NS" "$POD" -c elasticsearch -- sh -c 'cat > /tmp/service-ca.crt'
   oc exec -it -n "$NS" "$POD" -c elasticsearch -- env ES_URL="https://$ES-es-http.$NS.svc:9200" bash
   ```

2. In the pod, a helper and the list of snapshots:

   ```bash
   es() { local m="$1" p="$2"; shift 2
          curl -sS --cacert /tmp/service-ca.crt --netrc-file /tmp/restore.netrc \
            -H 'Content-Type: application/json' -X "$m" "$ES_URL/$p" "$@"; echo; }
   es GET '_cat/snapshots/platta-backup?v&s=end_epoch'
   SNAP=<snapshot name from the list>
   es GET "_snapshot/platta-backup/$SNAP?filter_path=snapshots.indices,snapshots.data_streams&pretty"
   ```

3. **Restore beside the live data first** (safe; nothing is overwritten). The `-restored` suffix
   keeps the names inside the app's patterns (`myapp-*`), so its users can read them:

   ```bash
   es POST "_snapshot/platta-backup/$SNAP/_restore?wait_for_completion=true" -d '{
     "indices": "myapp-*",
     "rename_pattern": "(.+)", "rename_replacement": "$1-restored",
     "include_global_state": false, "include_aliases": false }'
   es GET '_cat/indices/*-restored?v&h=health,index,docs.count'
   ```

4. **Or replace the live indices.** Stop the application's writes first (scale it to 0). Delete
   the indices by their exact names (wildcards are refused for deletes), then restore:

   ```bash
   es DELETE 'myapp-2026.11,myapp-users'                 # exact names from step 2
   es POST "_snapshot/platta-backup/$SNAP/_restore?wait_for_completion=true" -d '{
     "indices": "myapp-2026.11,myapp-users", "include_global_state": false }'
   ```

   A data stream is deleted with `es DELETE _data_stream/<name>` and restored by its name.
   Aliases come back with their indices (`include_aliases` defaults to true).

5. Check and clean up:

   ```bash
   es GET '_cluster/health?pretty'                       # green (1 node: auto_expand_replicas)
   rm -f /tmp/restore.netrc /tmp/service-ca.crt; exit
   ```

   Then start the application again.

**Into a new instance** (the old one is lost): install it with the same release name and
`backup` values; the Job registers the same repository (same `base_path`) and the snapshots
appear in step 2. Never let two running instances write to the same repository: if the old one
still runs, register the repository in the new one by hand with another name and
`"readonly": true`.

### Turning backups off

`backup.enabled: false` removes the Job, `platta-backup` and the secure settings (the nodes
restart once). It **does not delete** the policy, the repository or the snapshots. Without
its user the policy's snapshots fail, so an admin deletes the policy; deleting the repository
registration keeps the snapshots in the container:

```bash
es DELETE _slm/policy/platta-nightly
es DELETE _snapshot/platta-backup        # registration only; the blobs stay in Azure
```

## Objects the chart creates

Needed for the rights of the application team's pipeline service account in its namespace:

| Kind | API group |
|---|---|
| `Elasticsearch` | `elasticsearch.k8s.elastic.co/v1` |
| `Secret` (`<fullname>-roles`, and the Helm release records `sh.helm.release.v1.*`) | core |
| `ConfigMap` (`<fullname>-index-defaults`) | core |
| `ConfigMap` (`<fullname>-backup`, with backups) | core |
| `Job` (`<fullname>-index-defaults` and, with backups, `<fullname>-backup`; Helm hooks) | `batch/v1` |
| `ExternalSecret` (one per user, plus the technical users) | `external-secrets.io/v1` |
| `Password` (one per user, plus the technical users) | `generators.external-secrets.io/v1alpha1` |

On dev-se, the namespace roles `admin` and `edit` include the Elasticsearch and External
Secrets kinds (checked Nov 2026); `Job` and `ConfigMap` are in them by default in Kubernetes.

Everything else (StatefulSet, Services, Secrets, PVCs, PDB) is created by the ECK operator, and
the user Secrets (`elasticsearch-user-<name>`, `<fullname>-platta-defaults`,
`<fullname>-platta-backup`) by External Secrets. The backup credentials Secret
(`backup.secretName`) is the admins'.

## Known limitations

* **Renewing the backup SAS token restarts the Elasticsearch nodes** (ECK 3.1 rebuilds the
  keystore on every change of a secure settings Secret). Plan it in an announced window; see
  [Token renewal](#token-renewal).

* **A 1-node instance turns yellow if an index asks for replicas.** Since 0.3.0 new indices
  get 0 replicas on one node (see [Default index replicas](#default-index-replicas)), but not
  if an application sets `number_of_replicas` itself, uses an index template without
  `composed_of: ["platta-defaults"]`, creates the index outside its users' patterns, or
  created it before 0.3.0. A yellow cluster makes
  waits for green (e.g. `_cluster/health?wait_for_status=green`) time out, and ECK's
  PodDisruptionBudget then blocks pod eviction, which can hold up node maintenance.

* **Index names that match Elasticsearch's built-in templates do not get the default
  replicas.** Elasticsearch 9 has built-in index templates with priority 100 for names like
  `logs-*-*`, `metrics-*-*`, `traces-*-*` and `synthetics-*-*`. They win over
  `platta-default-replicas` (priority 0), so such indices (data streams) use Elastic's settings
  instead. **Avoid those name shapes** for your indices. Only if a name cannot be changed, add
  your own index template for it with a priority above 100 and
  `composed_of: ["platta-defaults"]`.

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

**dev-se, 13 Nov 2026:** nginx-standard 1.4.0 elastic-proxy with `upstreamAuth` on a `search`
user: health and searches pass; admin paths, writes and deletes are blocked by the proxy.

**3 nodes, dev-se, 13 Nov 2026:**

* Growing from 1 to 3 nodes (`helm upgrade … --set nodeCount=3`): the new nodes joined and the
  cluster was green; ECK's PodDisruptionBudget had `minAvailable` 2 / allowed disruptions 1.
  A new index with the default replica stayed green with 0 unassigned shards. Back to 1 node:
  green, and the extra PVCs were deleted (`DeleteOnScaledownOnly`).
* Fresh 3-node install (no existing data): all three nodes started together and formed a green
  cluster within about 5 minutes.

**Default index replicas, dev-se, 17 Nov 2026**, chart 0.3.0 (branch
`fix/PLATTA-8657-index-template-patterns`, index patterns from the users):

* Upgrade from 0.2.0: passed; the index-defaults Job stored the templates and the release
  succeeded.
* Fresh install: passed; `helm install` with the Job took 1 min 46 s.

## Still to test

1. Kibana (when it is added): does Kibana trust the Elasticsearch certificate? ECK gives Kibana
   the CA from `ca.crt`, which the OpenShift-generated Secret lacks; if needed, mount
   `platta-service-ca` into Kibana and set `elasticsearch.ssl.certificateAuthorities`.
2. *Low priority:* Elasticsearch 9.4.x with the clusters' ECK version (9.5.5 is tested).
3. Default index replicas (0.3.0):
   * the index-defaults Job on a fresh 3-node install (the upgrade from 0.2.0 and a fresh
     install are [tested](#tested));
   * the index template's patterns match the users' `indices`, change when they change, and
     the template is deleted when all users are removed (and a 404 is fine without one);
   * a new index on 1 node stays green with `auto_expand_replicas` (0 replicas);
   * growing 1 → 3 nodes gives it 1 replica, shrinking back to 1 node 0 replicas, green both
     times;
   * a team template with `priority: 1` and `composed_of: ["platta-defaults"]` keeps the
     default, and one with priority 0 makes the Job fail and name that template;
   * the technical user can manage templates only (403 on reading or writing an index).
4. *Optional performance optimization, not a blocker:* `vm.max_map_count` on the nodes: could
   `node.store.allow_mmap` be turned back on?
5. Backups (0.4.0), once the container and SAS token exist (on the smoke-test app):
   * **repository registration:** enabling backups restarts the nodes and the Job registers
     `platta-backup` within the Helm timeout (1 and 3 nodes); a wrong token or container fails it;
   * **least privilege:** `platta-backup` can register the repository and the policy with only
     `manage_slm`, `create_snapshot` and `cluster:admin/repository/put` (the policy API docs
     also mention index `manage`), and gets 403 on index data;
   * **a nightly snapshot:** taken at 00:00 UTC as `platta-backup`, state `SUCCESS`;
   * **retention:** runs without delete privileges for `platta-backup` (SLM's internal user),
     keeps 5–40 snapshots and deletes those older than 30 days (shorten `expire_after` by hand
     on a test instance to see it, the Job resets it);
   * **token renewal:** a changed `sas_token` in the Secret restarts the nodes one by one and
     the next snapshot succeeds with the new token;
   * **full restore** with the [runbook](#restore-runbook): beside the live data and in place,
     including `/tmp` being writable in the Elasticsearch pod;
   * turning backups off leaves the policy and snapshots, as documented.

## Maintenance

| When | Check | If something changed |
|---|---|---|
| New Elasticsearch version (patch or minor) | Is it newer than the chart's default `version`? Has an old minor lost Elastic's support? | (1) Add the tag to the Quay mirror (`mirrored-images/elasticsearch/elasticsearch`) first. (2) Update the allowed versions in `values.schema.json`, the default `version`, `appVersion` in `Chart.yaml`, and the tests. (3) Release the chart and test it on the sandbox and the dev-se smoke namespace. (4) Tell the teams on minors nearing end of life. |
| New ECK version | Release notes: deprecated fields that our template uses; supported Elasticsearch and OpenShift versions. | Edit the template if needed. Rehearse the upgrade: sandbox → dev-se smoke namespace → teams. |
| OpenShift upgrade on a cluster | Does the running ECK version support the new OpenShift version? | If not, upgrade ECK first. |
| Now and then | Do the Quay mirror's sync logs still succeed? Any GitHub Actions deprecation warnings in CI (repo-wide)? | Fix the mirror sync; act on the warnings. |

These checks are part of Platta's monthly upgrade/update evaluation (see the Elasticsearch support standard in Confluence).

## Changelog

### 0.4.0

Optional backups (PLATTA-7743):

* **Values:** `backup.enabled` (default `false`), `backup.secretName` and `backup.container`;
  both names are required when enabled. Schedule and retention are fixed.
* **Credentials:** the admins' Secret (keys `account` and `sas_token`, created via ExternalSecret)
  goes into the keystore as `azure.client.default.*` with ECK `spec.secureSettings`.
* **Technical user `platta-backup`** (only with backups), generated like `platta-defaults`;
  role `manage_slm`, `create_snapshot` and `cluster:admin/repository/put`, no index privileges.
* **Job `<fullname>-backup`** (Helm hook) registers the Azure repository `platta-backup`
  (`base_path: <fullname>`) and the SLM policy `platta-nightly`: 00:00 UTC, without global
  state, deleted after 30 days, 5 to 40 kept.
* **Restarts:** enabling or disabling backups, and every SAS token renewal, restart the
  Elasticsearch nodes one by one (ECK 3.1). Without backups nothing changes for existing
  instances.
* README: [Backups](#backups) with the admins' prerequisites, status requests and a restore
  runbook.
* Not yet tested on the clusters (waits for the container and SAS token), see
  [Still to test](#still-to-test).

### 0.3.1

Java4Shell fix (PLATTA-8673):

* **JVM:** the `elasticsearch` container sets `ES_JAVA_OPTS="-XX:-UseBASE64Intrinsics"`, which
  turns off the Base64 fast path of the JDK bundled with Elasticsearch (CVE-2026-114938, on
  CPUs with AVX-512 VBMI, which the Sweden clusters have). It is fixed in the template, not a
  value.
* **Upgrade:** the pod template changes, so ECK restarts the Elasticsearch pods one at a time.
  A 1-node instance is unavailable while its pod restarts.

### 0.3.0

Default index replicas (PLATTA-8657):

* **Default:** new indices get `index.auto_expand_replicas: "0-1"` (0 replicas on 1 node, 1 on
  3 nodes) from the component template `platta-defaults`, applied to the index patterns
  declared for the chart's users (`users[].indices`, deduplicated and sorted) by the index
  template `platta-default-replicas` (priority 0). Indices created outside these patterns do
  not get it. Without users there is no index template, and the Job deletes a stale one.
* **Job:** `<fullname>-index-defaults` stores both templates after every install and upgrade
  (Helm hook), on the chart's Elasticsearch image, trusting `platta-service-ca`. A priority
  conflict fails it and prints the conflicting template names from Elasticsearch's response.
* **Technical user:** `platta-defaults` (Secret `<fullname>-platta-defaults`, generated like the
  application users), role with only `manage_index_templates`. `spec.auth` and the roles Secret
  are now always rendered; upgrading from 0.2.0 adds the technical user to `spec.auth`.
* **Values schema:** user names starting with `platta-` are reserved.
* **Breaking for pipelines:** Helm waits for the Job, so installs need `--timeout 15m`; team
  index templates need `"priority": 1` or higher (and should add `"composed_of":
  ["platta-defaults"]`). `platta-service-ca` and the External Secrets Operator are now always
  required.
* Tested on dev-se (17 Nov 2026): upgrade from 0.2.0 and a fresh install, see
  [Tested](#tested); the rest is in [Still to test](#still-to-test).

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
