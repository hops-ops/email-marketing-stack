### What's changed in v0.1.1

* fix(ci): depend on hops-ops/psql-stack Configuration so PSQLCluster schema resolves at validate time (by @patrickleet)

  Reverts the workaround in 1d2dac0 — instead of disabling
  error_on_missing_schemas globally, pull psql-stack in as a sibling
  Configuration dependency. crossplane beta validate then has access
  to PSQLCluster's OpenAPI schema and can enforce shape correctness
  on the rendered embedded-psql-cluster MR.

  Pinned to >=v0.9.1 (psql-stack's current latest tagged release).


See full diff: [v0.1.0...v0.1.1](https://github.com/hops-ops/email-marketing-stack/compare/v0.1.0...v0.1.1)
