# AmniX Finance — Port Registry
> Auto-generated from repo. Single source of truth.
> تحديث إلزامي قبل أي service جديدة.

## محجوز — مستخدم فعلاً
| Port | Service | المصدر |
|------|---------|--------|
| 3306 | platform | `platform/config/processing/risingwave-values.yaml` |
| 4195 | analytics | `services/analytics/k8s/templates/deployment.yaml` |
| 4433 | auth | `services/auth/k8s/values.yaml` |
| 4434 | auth | `services/auth/k8s/values.yaml` |
| 4455 | platform | `platform/config/auth/oathkeeper-values.yaml` |
| 4456 | platform | `platform/config/auth/oathkeeper-values.yaml` |
| 4567 | platform | `platform/config/processing/risingwave-values.yaml` |
| 5432 | platform | `platform/config/processing/risingwave-values.yaml` |
| 5555 | ingestion | `services/ingestion/k8s/tests/deployment_test.yaml` |
| 8000 | platform | `platform/config/realtime/centrifugo-values.yaml` |
| 8080 | ingestion | `services/ingestion/k8s/tests/service_test.yaml` |
| 8092 | search | `services/search/k8s/values.yaml` |
| 8093 | billing | `services/billing/k8s/values.yaml` |
| 8428 | analytics | `services/analytics/k8s/values.yaml` |
| 9000 | platform | `platform/config/auth/oathkeeper-values.yaml` |
| 9010 | realtime | `services/realtime/k8s/values.yaml` |
| 9090 | notifications | `services/notifications/k8s/templates/deployment.yaml` |
| 9095 | notifications | `services/notifications/k8s/templates/deployment.yaml` |
| 9292 | notifications | `services/notifications/k8s/templates/deployment.yaml` |
| 9440 | notifications | `services/notifications/k8s/templates/deployment.yaml` |
| 9999 | ingestion | `services/ingestion/k8s/tests/service_test.yaml` |
| 10000 | platform | `platform/config/realtime/centrifugo-values.yaml` |
| 11000 | platform | `platform/config/realtime/centrifugo-values.yaml` |

## محجوز — Services القادمة
| Port | Service |
|------|---------|
| 8094 | feature-flags |
| 8095 | control-plane |
| 8096 | developer-portal |
| 8097 | tenant-operator |
| 8098 | hydration |
| 8099 | jobs |
| 8100 | ml-engine |
