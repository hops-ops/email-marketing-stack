### What's changed in v0.2.0

* feat(v3.1): compose listmonk ProviderConfig + AppSettings MRs (by @patrickleet)

  Closes the v3.1 chunk of [[tasks/email-marketing-stack]] — the stack
  now composes the upjet-listmonk ProviderConfig + declarative
  AppSettings MR, on top of the v3 chart-bootstrapped api-user.

  What's rendered (when spec.adminAuth.createApiUser is on, default
  true):

    500-listmonk-providerconfig
      apiVersion: kubernetes.m.crossplane.io/v1alpha1 Object
      wrapping listmonk.m.crossplane.io/v1beta1 ProviderConfig in the
      install namespace, sourcing credentials from the chart-
      bootstrapped <release>-provider-creds Secret. Namespaced PC so
      downstream MRs resolve same-namespace per
      reference_v2_providerconfig_same_namespace_lookup.

    510-listmonk-app-settings
      apiVersion: kubernetes.m.crossplane.io/v1alpha1 Object
      wrapping settings.listmonk.m.crossplane.io/v1alpha1 AppSettings
      with rootUrl (derived from spec.exposure.hostname when exposure
      is enabled), fromEmail (from spec.smtp.fromAddress when SMTP is
      wired), siteName (from spec.siteName, falling back to
      `<spec.domain> Newsletter` when only domain is set). Fields the
      consumer doesn't supply are not touched on the server — the
      upstream listmonk_app_settings resource preserves operator UI
      edits to unmanaged keys.

    Empty AppSettings render is skipped — no point creating an MR
    that no-ops every reconcile when there's nothing useful to write.

  Why declarative when the chart already writes [app] in config.toml:
  the chart's config.toml only seeds INITIAL values at first install.
  Listmonk's koanf loader merges env > config.toml > DB at startup;
  post-install the DB row wins (reference_listmonk_db_overrides_koanf).
  Without these MRs, post-install operator edits to app.root_url etc.
  via the admin UI drift the runtime away from the GitOps spec — and
  subsequent helm upgrades don't fix it because the DB row already
  exists.

  Deferred to v3.2:

  - SecuritySettings MR (declarative OIDC). Blocked on
    listmonk_security_settings gaining clientSecretRef support — today
    it takes the OIDC client secret as a plaintext string, but the
    marketing-oidc-raw Secret value (Zitadel-managed) can't be inlined
    into composition-rendered YAML. Provider v0.3 work.
  - UserRole + User MRs (declarative role/user pre-provisioning).
    Mostly useful for `auto_create_users: false` workflows; out of
    scope for the v3.1 cut.

  XRD: adds `spec.siteName` (string, optional). State-init plumbs it
  through to the render template. 9/9 KCL composition tests pass
  (including a new test locking in the v3.1 render shape).


See full diff: [v0.1.1...v0.2.0](https://github.com/hops-ops/email-marketing-stack/compare/v0.1.1...v0.2.0)
