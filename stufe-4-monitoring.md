# Stufe 4 – Monitoring: sehen, was los ist

**Zeit:** ein Abend (2–3 h)
**Ziel:** Prometheus scrapt deine App, du baust ein eigenes Grafana-Panel und eine Alert-Regel.

> Ohne diese Stufe ist Stufe 5 blindes Raten. Und im Job ist Observability der Unterschied zwischen "irgendwas ist langsam" und einer belastbaren Aussage, *was* langsam ist.

---

## 1. Stack installieren

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace
```

Das dauert ein paar Minuten und bringt ein ganzes Paket mit: Prometheus Operator, Prometheus selbst, Alertmanager, Grafana, node-exporter und kube-state-metrics.

```bash
kubectl get pods -n monitoring -w
```

Zugriff:

```bash
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
# → http://localhost:3000   User: admin   Passwort: prom-operator

kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090
# → http://localhost:9090
```

Schau dir in Grafana zuerst die mitgelieferten Dashboards an (*Dashboards → Browse*), etwa "Kubernetes / Compute Resources / Namespace (Pods)". Das ist schon mehr, als viele Teams selbst bauen.

## 2. Der Operator-Gedanke

Du konfigurierst Prometheus **nicht** über eine `prometheus.yml`. Stattdessen legst du Kubernetes-Objekte an, und der Operator generiert daraus die Konfiguration:

- **ServiceMonitor** – "scrape diesen Service"
- **PodMonitor** – dasselbe auf Pod-Ebene
- **PrometheusRule** – Alert- und Recording-Regeln

Das ist genau die deklarative Denkweise aus Stufe 3, nochmal angewandt.

## 3. ServiceMonitor für podinfo

Leg das im Repo unter `charts/podinfo-chart/templates/servicemonitor.yaml` an – dann rollt Argo es mit aus:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: {{ include "podinfo-chart.fullname" . }}
  labels:
    release: monitoring        # ← entscheidend, siehe unten
spec:
  selector:
    matchLabels:
      {{- include "podinfo-chart.selectorLabels" . | nindent 6 }}
  endpoints:
    - port: http
      path: /metrics
      interval: 15s
```

> **Der Fallstrick, der alle trifft:** kube-prometheus-stack sammelt standardmäßig nur ServiceMonitors ein, die das Label `release: <helm-release-name>` tragen – hier `release: monitoring`. Ohne dieses Label passiert schlicht nichts, ohne Fehlermeldung. Wenn dein Target nicht auftaucht, ist das die erste Stelle zum Nachschauen.
>
> Zweiter Fallstrick: `port: http` meint den **Namen** des Service-Ports, nicht die Nummer. Dein Service aus Stufe 2 muss den Port also benannt haben.

Prüfen unter **http://localhost:9090/targets** – dein podinfo-Target muss dort als `UP` erscheinen.

## 4. PromQL – das Minimum

In der Prometheus-UI unter *Graph* ausprobieren:

```promql
# Requests pro Sekunde, nach Status-Code
sum(rate(http_requests_total{namespace="dev"}[5m])) by (status)

# Fehlerrate in Prozent
100 * sum(rate(http_requests_total{namespace="dev", status=~"5.."}[5m]))
    / sum(rate(http_requests_total{namespace="dev"}[5m]))

# Latenz, 95. Perzentil
histogram_quantile(0.95,
  sum(rate(http_request_duration_seconds_bucket{namespace="dev"}[5m])) by (le))

# Speicherverbrauch pro Pod
sum(container_memory_working_set_bytes{namespace="dev"}) by (pod)

# Container-Neustarts
sum(increase(kube_pod_container_status_restarts_total{namespace="dev"}[1h])) by (pod)
```

Vier Konzepte reichen für den Anfang:

| Konzept | Wofür |
|---|---|
| `rate(counter[5m])` | Counter sind monoton steigend – erst `rate` macht sie lesbar |
| `sum(...) by (label)` | Aggregieren und nach Dimension aufteilen |
| `histogram_quantile` | Latenz-Perzentile aus Buckets |
| Label-Matcher `{a="b", c=~"re.*"}` | Filtern |

**Die RED-Methode** als Denkraster für Services: **R**ate (Anfragen/s), **E**rrors (Fehlerquote), **D**uration (Latenz). Wenn du diese drei für einen Service siehst, weißt du 80 % von dem, was du wissen musst.

## 5. Eigenes Dashboard

In Grafana: *New → Dashboard → Add visualization → Prometheus*. Bau vier Panels aus den Queries oben: Request-Rate, Fehlerrate, p95-Latenz, Memory pro Pod.

Dann *Dashboard settings → JSON Model* → JSON kopieren und im Repo ablegen. Grund: Ein Dashboard, das nur in der Grafana-Datenbank existiert, ist beim nächsten Neuaufsetzen weg. Dashboards gehören nach Git wie alles andere.

## 6. Alert-Regel

`charts/podinfo-chart/templates/prometheusrule.yaml`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: {{ include "podinfo-chart.fullname" . }}
  labels:
    release: monitoring
spec:
  groups:
    - name: podinfo
      rules:
        - alert: PodinfoHighErrorRate
          expr: |
            100 * sum(rate(http_requests_total{namespace="dev", status=~"5.."}[5m]))
                / sum(rate(http_requests_total{namespace="dev"}[5m])) > 5
          for: 2m
          labels:
            severity: warning
          annotations:
            summary: "podinfo Fehlerrate über 5 %"
            description: "Seit 2 Minuten liefern über 5 % der Requests einen 5xx."
```

Das `for: 2m` ist der wichtigste Teil: Der Alert feuert erst, wenn die Bedingung zwei Minuten *durchgehend* wahr ist. Ohne das bekommst du bei jedem kurzen Ausschlag eine Benachrichtigung – und genau so entsteht Alert-Müdigkeit, das häufigste Problem echter Monitoring-Setups.

Status prüfen unter **http://localhost:9090/alerts**: `Inactive` → `Pending` (Bedingung wahr, `for` läuft) → `Firing`.

Zum Testen in Stufe 5 erzeugst du gleich echte Fehler.

---

## Geschafft, wenn…

- [ ] podinfo taucht in Prometheus unter */targets* als UP auf
- [ ] Du hast ein eigenes Dashboard mit mindestens vier Panels
- [ ] Du kannst `rate()` und `sum() by ()` erklären
- [ ] Eine eigene Alert-Regel existiert und du weißt, wo du ihren Zustand siehst
