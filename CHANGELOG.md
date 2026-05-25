### What's changed in v0.1.0

* feat: initial release — EmailMarketingStack v3 (by @patrickleet)

  EmailMarketingStack scaffold + v3 chart-bootstrap composition wiring.
  Composes a Listmonk install with embedded CNPG Postgres, optional
  SMTP / OIDC / public exposure, and (v3+) a chart-side post-install
  hook that mints a `crossplane-provider` type=api Listmonk user for
  declarative provider-listmonk usage downstream.

  v1 surface (already verified on pat-local in earlier sessions):
  - Namespace + embedded PSQLCluster (via psql-stack)
  - ExternalSecret-projected SMTP credentials (gated on observed
    SMTPStack.status.smtp.awsSecretsManagerPath per the
    composition-gates pattern)
  - Helm Release of hops-ops/listmonk-chart with chart-pinned defaults

  v2 surface (already verified on pat-local):
  - Native OIDC SSO via provider-upjet-zitadel-published iam-admin PAT
  - Path-scoped HTTPRoute + cert-manager Certificate composition
  - App-level auth (Listmonk's own OIDC on /admin + /api), no
    oauth2-proxy / AuthorizationPolicy.CUSTOM

  v3 surface (this commit):
  - spec.adminAuth.{createApiUser, apiUserName, pushSecret.{enabled,
    secretStoreName, path}}; defaults: createApiUser=true,
    apiUserName=crossplane-provider, pushSecret.enabled=false
  - Chart pin default bumped 0.1.1 → 0.2.0 (the chart version that
    ships the post-install api-user-bootstrap hook)
  - New 300-admin-credentials-pushsecret render — composes an ESO
    PushSecret of the chart-managed `<release>-provider-creds` Secret
    to AWS SM at `push/<cluster>/<stack>-listmonk-credentials` when
    spec.adminAuth.pushSecret.enabled=true
  - KCL composition tests: 8/8 passing, including the chart-version-pin
    assertion updated to 0.2.0

  The api-user-bootstrap hook in listmonk-chart v0.2.0 is itself
  verified end-to-end on pat-local with a vanilla postgres harness
  (cold install, idempotent re-run, token rotation, type-collision
  fail-fast — see hops-ops/listmonk-chart PR #2).

  The ProviderConfig MR that consumes the chart-managed Secret is
  deferred until provider-listmonk (upjet-generated Crossplane provider)
  ships; see hops-ops/terraform-provider-listmonk for the underlying
  TF provider work and tasks/provider-listmonk in the KB for the
  upjet roadmap.

  CI: mirrors hops-ops/security-stack workflows (validate / test / e2e
  via unbounded-tech/workflows-crossplane reusable workflows; vnext
  auto-tag on push to main; publish on version tag).

* ci: disable error_on_missing_schemas (PSQLCluster cross-stack XRD unavailable in validate env) (by @patrickleet)


