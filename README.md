# email-marketing-stack

Installs [Listmonk](https://listmonk.app) into a Kubernetes cluster as the
platform's self-hosted newsletter + marketing-campaign engine. Wraps the
[`redzumi/listmonk-chart`](https://redzumi.github.io/listmonk-chart) chart
with a typed `EmailMarketingStack` XRD that handles:

- **Database**: embedded `PSQLCluster` (CNPG) by default — Listmonk reads
  its `db__user` / `db__password` directly from the CNPG-generated app
  Secret via the chart's `existingSecret` field.
- **SMTP**: an `ExternalSecret` that pulls SES SMTP credentials from
  AWS Secrets Manager. The remote path is observed from the referenced
  `SMTPStack.status.smtp.awsSecretsManagerPath` — composition gates on
  the observed status, so the ES renders only after `SMTPStack` reports
  the path.

See the spec at `specs/email-marketing-stack` in the GitKB for the full
design (per-tenant model, OIDC, exposure, observability, analytics bridge,
provider workstream).

## Scope: v1

| Composed | What | Notes |
| --- | --- | --- |
| `Namespace` | The Listmonk install namespace (default `marketing`) | Owned by the stack. |
| `PSQLCluster` | CNPG-backed Postgres for Listmonk | `targetNamespace` = install ns so the app Secret is mounted natively. |
| `Helm Release` | redzumi/listmonk-chart 2.0.1 (Listmonk v6.0.0) | Embedded Postgres subchart **off**; chart wires to CNPG via `database.existingSecret` (`passwordKey: password`). |
| `ExternalSecret` (Object MR) | `smtp-{host,port,username,password,from}` projected into `listmonk-smtp` K8s Secret | Matches the chart's `smtp.existingSecret` contract. Renders only when `spec.smtp.smtpStackRef.name` is set AND the observed SMTPStack reports an AWS SM path. |
| `Object` (Observe) | Reads upstream `SMTPStack` | `managementPolicies: [Observe]` — composition reads `status.smtp.awsSecretsManagerPath`. |
| `Usage` × 2 | Delete-order safeguards | Helm release drains before namespace or PSQLCluster teardown. |

### Deferred (v2+)

- OIDC + Gateway API exposure (`/admin`, `/api` gated; `/subscription/*`,
  `/campaign/*`, `/link/*`, `/uploads/*` anonymous).
- `meysam81/listmonk-exporter` sidecar + the two Grafana dashboards in
  `xrs/stacks/aws/observe/dashboards/email-marketing/`.
- S3 media backend, SES bounce ingestion.
- `tenancy.mode=tenant` integration with TenantStack.
- `provider-listmonk` declarative content management
  (`Template` / `List` / `Campaign` / `Sequence` / `Settings` / `User`).

## Known chart gap (OQ1 follow-up)

The pinned upstream chart (`redzumi/listmonk-chart` 2.0.1) accepts
`smtp.existingSecret` and synthesizes a placeholder Secret when none is
supplied, but the Deployment template does **not** project the SMTP
secret values into env vars. The `listmonk-smtp` K8s Secret we render
materializes correctly, but the running Pod won't consume it
automatically.

**v1 operator path**: configure SMTP via the Listmonk admin UI
(Settings → SMTP) — paste the values from the K8s Secret:

```bash
kubectl -n marketing get secret listmonk-smtp -o json \
  | jq '.data | map_values(@base64d)'
```

**v2 plan**: fork the chart into `hops-ops/helm-charts/listmonk` and add
`envFrom: secretRef` on the SMTP Secret so the existing ExternalSecret
wires the Pod declaratively. The Secret key layout (`smtp-host`,
`smtp-port`, `smtp-username`, `smtp-password`, `smtp-from`) already
matches the chart's `smtp.existingSecret` contract, so the fork only
needs to add the envFrom block — no ExternalSecret changes required.
Tracked in the spec under `OQ1` + `OQ10`.

### Chart selection note

We evaluated `th0th/helm-charts/listmonk` (5.0.3-3, Listmonk v5.0.3) but
its `values.schema.json` carries an external `$ref` to
`raw.githubusercontent.com` that the provider-helm-bundled `helm` CLI
rejects with "invalid file url", failing every install. The redzumi
chart ships no `values.schema.json` and uses Listmonk v6.0.0 — newer
app + works through provider-helm without modification.

## First-run admin

The chart's `initContainer` runs `listmonk --install --idempotent --yes`
which creates the database schema; Listmonk's web UI prompts for the
admin username + password on first HTTP visit. There is no env-var
admin bootstrap — operator sets credentials interactively. v2 can switch
to OIDC (Zitadel) once the AuthStack `listmonk` Application is provisioned.

## Local-dev: pat-local (colima)

Pat-local's `helm`/`kubernetes` ProviderConfigs target the AWS EKS data
plane (see `reference_pat_local_providerconfig_target`). With Crossplane
running on colima:

```bash
# Install the configuration package
hops config install --path xrs/stacks/k8s/email-marketing

# Apply the local example
kubectl --context pat-local apply -f xrs/stacks/k8s/email-marketing/examples/emailmarketingstacks/local-colima.yaml

# Watch the XR
kubectl --context pat-local get emailmarketingstack -A -w

# Port-forward the admin UI once the Helm release is Ready
kubectl --context pat-local -n marketing port-forward svc/marketing-listmonk 9000:9000
# → open http://localhost:9000/admin (default credentials: admin / set at first run)
```

The `local-colima.yaml` example references an `SMTPStack` named `smtp` in
namespace `default`. Until that XR lands on the cluster, the
`marketing-observed-smtp-stack` Object MR will be in a "not found" state
and the SMTP ExternalSecret will not render. Install + admin UI still
work; SMTP wiring catches up automatically once `SMTPStack` reports
`status.smtp.awsSecretsManagerPath`.

## Workflows

| Command | What it does |
| --- | --- |
| `make render:all` | Render every example, parallelized |
| `make validate:all` | Same as render + `crossplane beta validate` |
| `make test` | Run the KCL `CompositionTest` cases under `tests/` |
| `make build` | `up project build` — emits the configuration package |
| `make clean` | Drop `_output/` + `.up/` + `apis/.../configuration.yaml` |
| `make publish tag=vX.Y.Z` | Push the configuration package to the registry |
