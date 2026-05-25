import models.ai.com.ops.hops.v1alpha1 as stacksv1alpha1
import models.io.upbound.dev.meta.v1alpha1 as metav1alpha1

# ==============================================================================
# Unit tests for EmailMarketingStack XRD (v1).
#
# Philosophy: test YOUR API, not the provider's.
#  - render/validate already exercises provider schema correctness.
#  - These tests assert XRD spec fields produce the expected composed resources.
# ==============================================================================

_items = [
    # ==========================================================================
    # Test 1: minimal claim renders Namespace + PSQLCluster + Helm Release.
    #         No smtpStackRef → no observed-smtp-stack Object MR.
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "minimal-renders-namespace-psql-helm"
        spec = {
            compositionPath = "apis/emailmarketingstacks/composition.yaml"
            xrdPath = "apis/emailmarketingstacks/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = stacksv1alpha1.EmailMarketingStack {
                metadata.name = "marketing"
                spec.clusterName = "my-cluster"
            }
            assertResources = [
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata.name = "marketing-namespace"
                    spec.forProvider.manifest = {
                        apiVersion = "v1"
                        kind = "Namespace"
                        metadata.name = "marketing"
                    }
                }
                {
                    apiVersion = "hops.ops.com.ai/v1alpha1"
                    kind = "PSQLCluster"
                    metadata.name = "marketing-pg"
                    spec = {
                        clusterName = "my-cluster"
                        targetNamespace = "marketing"
                        instances = 1
                        storage.size = "5Gi"
                        storage.class = "psql"
                        app.role = "listmonk"
                        app.database = "listmonk"
                    }
                }
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata.name = "marketing-listmonk"
                    spec.forProvider = {
                        chart = {
                            name = "listmonk"
                            repository = "https://hops-ops.github.io/listmonk-chart"
                            version = "0.2.0"
                        }
                        namespace = "marketing"
                        values.resources = {
                            requests = {cpu = "15m", memory = "100Mi"}
                            limits = {cpu = "500m", memory = "512Mi"}
                        }
                    }
                }
            ]
        }
    }

    # ==========================================================================
    # Test 2: chart wires the CNPG app Secret via existingSecret keys
    #         (username/password) and points hostname at the rw Service.
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "chart-wires-cnpg-app-secret"
        spec = {
            compositionPath = "apis/emailmarketingstacks/composition.yaml"
            xrdPath = "apis/emailmarketingstacks/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = stacksv1alpha1.EmailMarketingStack {
                metadata.name = "marketing"
                metadata.namespace = "default"
                spec.clusterName = "my-cluster"
            }
            assertResources = [
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata.name = "marketing-listmonk"
                    spec.forProvider.values = {
                        postgres.enabled = False
                        database = {
                            host = "marketing-pg-rw.marketing.svc.cluster.local"
                            port = 5432
                            name = "listmonk"
                            user = "listmonk"
                            sslMode = "disable"
                            existingSecret = "marketing-pg-app"
                            passwordKey = "password"
                        }
                    }
                }
            ]
        }
    }

    # ==========================================================================
    # Test 3: with smtpStackRef set, an Observe-only Object MR is rendered
    #         to watch the upstream SMTPStack's status.
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "smtp-stack-ref-renders-observe-object"
        spec = {
            compositionPath = "apis/emailmarketingstacks/composition.yaml"
            xrdPath = "apis/emailmarketingstacks/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = stacksv1alpha1.EmailMarketingStack {
                metadata.name = "marketing"
                metadata.namespace = "default"
                spec = {
                    clusterName = "my-cluster"
                    smtp.smtpStackRef = {
                        name = "smtp"
                        namespace = "default"
                    }
                }
            }
            assertResources = [
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata.name = "marketing-observed-smtp-stack"
                    spec = {
                        managementPolicies = ["Observe"]
                        forProvider.manifest = {
                            apiVersion = "hops.ops.com.ai/v1alpha1"
                            kind = "SMTPStack"
                            metadata = {
                                name = "smtp"
                                namespace = "default"
                            }
                        }
                    }
                }
            ]
        }
    }

    # ==========================================================================
    # Test 4: smtp.enabled = False skips the observation entirely.
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "smtp-disabled-skips-observation"
        spec = {
            compositionPath = "apis/emailmarketingstacks/composition.yaml"
            xrdPath = "apis/emailmarketingstacks/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = stacksv1alpha1.EmailMarketingStack {
                metadata.name = "marketing"
                spec = {
                    clusterName = "my-cluster"
                    smtp.enabled = False
                    smtp.smtpStackRef = {
                        name = "smtp"
                        namespace = "default"
                    }
                }
            }
            # We assert the Release exists (no observed-smtp-stack
            # Object MR should render — absence is implicit).
            assertResources = [
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata.name = "marketing-listmonk"
                }
            ]
        }
    }

    # ==========================================================================
    # Test 5: custom storage size + instances propagate to PSQLCluster +
    #         listmonk replicas.
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "custom-storage-and-replicas"
        spec = {
            compositionPath = "apis/emailmarketingstacks/composition.yaml"
            xrdPath = "apis/emailmarketingstacks/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = stacksv1alpha1.EmailMarketingStack {
                metadata.name = "marketing"
                spec = {
                    clusterName = "my-cluster"
                    database.embedded = {
                        instances = 2
                        storage.size = "20Gi"
                    }
                }
            }
            assertResources = [
                {
                    apiVersion = "hops.ops.com.ai/v1alpha1"
                    kind = "PSQLCluster"
                    metadata.name = "marketing-pg"
                    spec = {
                        instances = 2
                        storage.size = "20Gi"
                    }
                }
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata.name = "marketing-listmonk"
                    spec.forProvider.values.replicaCount = 2
                }
            ]
        }
    }

    # ==========================================================================
    # Test 6: custom chart version pin propagates.
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "chart-version-pin"
        spec = {
            compositionPath = "apis/emailmarketingstacks/composition.yaml"
            xrdPath = "apis/emailmarketingstacks/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = stacksv1alpha1.EmailMarketingStack {
                metadata.name = "marketing"
                spec = {
                    clusterName = "my-cluster"
                    version = "2.0.0"
                }
            }
            assertResources = [
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata.name = "marketing-listmonk"
                    spec.forProvider.chart.version = "2.0.0"
                }
            ]
        }
    }

    # ==========================================================================
    # Test 7: provider config refs default to clusterName.
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "provider-config-refs-default-to-cluster-name"
        spec = {
            compositionPath = "apis/emailmarketingstacks/composition.yaml"
            xrdPath = "apis/emailmarketingstacks/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = stacksv1alpha1.EmailMarketingStack {
                metadata.name = "marketing"
                spec.clusterName = "prod-cluster"
            }
            assertResources = [
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata.name = "marketing-listmonk"
                    spec.providerConfigRef = {
                        name = "prod-cluster"
                        kind = "ProviderConfig"
                    }
                }
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata.name = "marketing-namespace"
                    spec.providerConfigRef = {
                        name = "prod-cluster"
                        kind = "ProviderConfig"
                    }
                }
            ]
        }
    }

    # ==========================================================================
    # Test 8: Usage MRs gate deletion order — Helm before namespace,
    #         Helm before PSQLCluster.
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "deletion-order-usage-mrs-rendered"
        spec = {
            compositionPath = "apis/emailmarketingstacks/composition.yaml"
            xrdPath = "apis/emailmarketingstacks/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = stacksv1alpha1.EmailMarketingStack {
                metadata.name = "marketing"
                spec.clusterName = "my-cluster"
            }
            assertResources = [
                {
                    apiVersion = "protection.crossplane.io/v1beta1"
                    kind = "Usage"
                    metadata.name = "marketing-delete-listmonk-before-namespace"
                    spec = {
                        of = {
                            apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                            kind = "Object"
                            resourceRef.name = "marketing-namespace"
                        }
                        by = {
                            apiVersion = "helm.m.crossplane.io/v1beta1"
                            kind = "Release"
                            resourceRef.name = "marketing-listmonk"
                        }
                    }
                }
                {
                    apiVersion = "protection.crossplane.io/v1beta1"
                    kind = "Usage"
                    metadata.name = "marketing-delete-listmonk-before-embedded-psql-cluster"
                    spec = {
                        of = {
                            apiVersion = "hops.ops.com.ai/v1alpha1"
                            kind = "PSQLCluster"
                            resourceRef.name = "marketing-pg"
                        }
                        by = {
                            apiVersion = "helm.m.crossplane.io/v1beta1"
                            kind = "Release"
                            resourceRef.name = "marketing-listmonk"
                        }
                    }
                }
            ]
        }
    }
    # ==========================================================================
    # Test 9 (v3.1): adminAuth.createApiUser=true (default) renders the
    #                listmonk ProviderConfig + AppSettings MR (when there
    #                are app fields to declare) — declarative settings
    #                composition.
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "v3-1-renders-listmonk-providerconfig-and-app-settings"
        spec = {
            compositionPath = "apis/emailmarketingstacks/composition.yaml"
            xrdPath = "apis/emailmarketingstacks/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = stacksv1alpha1.EmailMarketingStack {
                metadata.name = "marketing"
                spec = {
                    clusterName = "my-cluster"
                    domain = "ops.com.ai"
                    siteName = "Acme Newsletter"
                    smtp.fromAddress = "newsletter@ops.com.ai"
                    exposure = {
                        enabled = True
                        domain = "ops.com.ai"
                    }
                }
            }
            assertResources = [
                # ProviderConfig wrapped via kubernetes.m Object — points
                # at the chart-bootstrapped <release>-provider-creds Secret
                # in the install namespace.
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata.name = "marketing-listmonk-providerconfig"
                    spec.forProvider.manifest = {
                        apiVersion = "listmonk.m.crossplane.io/v1beta1"
                        kind = "ProviderConfig"
                        metadata.name = "marketing-listmonk"
                        metadata.namespace = "marketing"
                        spec.credentials = {
                            source = "Secret"
                            secretRef = {
                                name = "marketing-listmonk-provider-creds"
                                namespace = "marketing"
                                key = "credentials"
                            }
                        }
                    }
                }
                # AppSettings MR carrying the rootUrl (from exposure),
                # fromEmail (from spec.smtp), and siteName (from
                # spec.siteName when set).
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata.name = "marketing-listmonk-app-settings"
                    spec.forProvider.manifest = {
                        apiVersion = "settings.listmonk.m.crossplane.io/v1alpha1"
                        kind = "AppSettings"
                        metadata.name = "marketing-app-settings"
                        metadata.namespace = "marketing"
                        spec = {
                            forProvider = {
                                rootUrl = "https://marketing.ops.com.ai"
                                fromEmail = "newsletter@ops.com.ai"
                                siteName = "Acme Newsletter"
                            }
                            providerConfigRef.name = "marketing-listmonk"
                        }
                    }
                }
            ]
        }
    }
]

items = _items
