# Stufe 2 – Helm: dasselbe, aber mehrfach

**Zeit:** ein Abend (2 h)
**Ziel:** Deine drei Manifeste werden zu einem eigenen Chart, das du zweimal mit unterschiedlichen Werten installierst.

> Das Problem, das Helm löst: Du hast dieselbe App in dev, staging und prod – und bei drei Kunden. Copy-Paste von YAML skaliert nicht. **Merk dir dieses Problem**, denn Terragrunt löst später exakt dasselbe eine Ebene höher, für Terraform.

---

## 1. Installation

```bash
brew install helm        # oder: https://helm.sh/docs/intro/install/
helm version
```

## 2. Chart-Gerüst

```bash
helm create podinfo-chart
```

Helm legt ein vollständiges Beispiel-Chart an. **Lösch den Beispielkram raus**, sonst verstehst du nie, was wirklich nötig ist:

```bash
cd podinfo-chart
rm -rf templates/tests templates/hpa.yaml templates/serviceaccount.yaml templates/NOTES.txt
rm charts/.gitkeep 2>/dev/null
```

Übrig bleiben soll:

```
podinfo-chart/
├── Chart.yaml
├── values.yaml
└── templates/
    ├── _helpers.tpl
    ├── deployment.yaml
    ├── service.yaml
    └── ingress.yaml
```

## 3. `values.yaml`

Ersetz den Inhalt durch etwas Schlankes:

```yaml
replicaCount: 2

image:
  repository: ghcr.io/stefanprodan/podinfo
  tag: "6.7.1"
  pullPolicy: IfNotPresent

ui:
  color: "#34577c"
  message: "hello from dev"

service:
  port: 80

ingress:
  enabled: true
  host: podinfo.localhost

resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 500m
    memory: 128Mi
```

## 4. Templates

Nimm deine Manifeste aus Stufe 1 und ersetz die festen Werte. `templates/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "podinfo-chart.fullname" . }}
  labels:
    {{- include "podinfo-chart.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- include "podinfo-chart.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "podinfo-chart.selectorLabels" . | nindent 8 }}
    spec:
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - name: http
              containerPort: 9898
          env:
            - name: PODINFO_UI_COLOR
              value: {{ .Values.ui.color | quote }}
            - name: PODINFO_UI_MESSAGE
              value: {{ .Values.ui.message | quote }}
          livenessProbe:
            httpGet: { path: /healthz, port: http }
            initialDelaySeconds: 5
          readinessProbe:
            httpGet: { path: /readyz, port: http }
            initialDelaySeconds: 5
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
```

`templates/ingress.yaml` bekommt eine Bedingung:

```yaml
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "podinfo-chart.fullname" . }}
spec:
  rules:
    - host: {{ .Values.ingress.host }}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: {{ include "podinfo-chart.fullname" . }}
                port:
                  number: {{ .Values.service.port }}
{{- end }}
```

Service analog.

## 5. Erst rendern, dann installieren

**Gewöhn dir das sofort an** – das ist der Befehl, den du später bei jedem Debugging brauchst:

```bash
helm template dev ./podinfo-chart
```

Das rendert die Templates, ohne irgendwas am Cluster zu tun. Fehler in der Einrückung siehst du hier, nicht erst beim Deployen. Für Live-Prüfung gegen den Cluster:

```bash
helm install dev ./podinfo-chart -n demo --dry-run --debug
```

## 6. Der eigentliche Punkt: zweimal installieren

```bash
helm install dev ./podinfo-chart -n dev --create-namespace \
  --set ui.color="#34577c" \
  --set ui.message="hello from dev" \
  --set ingress.host=dev.localhost

helm install stage ./podinfo-chart -n stage --create-namespace \
  --set replicaCount=3 \
  --set ui.color="#8c3b3b" \
  --set ui.message="hello from stage" \
  --set ingress.host=stage.localhost
```

Jetzt: **http://dev.localhost:8080** und **http://stage.localhost:8080** – dasselbe Chart, zwei Umgebungen, unterschiedliche Farbe und Replica-Zahl.

Sauberer als `--set` sind eigene Wertedateien:

```bash
helm upgrade stage ./podinfo-chart -n stage -f values-stage.yaml
```

Genau so wirst du es im Job sehen: ein Chart, viele `values-<umgebung>.yaml`.

## 7. Lifecycle-Kommandos

```bash
helm list -A
helm upgrade dev ./podinfo-chart -n dev --set replicaCount=4
helm history dev -n dev
helm rollback dev 1 -n dev
helm uninstall stage -n stage
helm get manifest dev -n dev    # was ist real im Cluster gelandet?
```

`helm rollback` ist der Moment, in dem klar wird, warum man das überhaupt macht.

---

## Fallstricke, die dich garantiert treffen

- **Einrückung.** `nindent` statt `indent` bei eingerückten Blöcken – der Unterschied ist ein führender Zeilenumbruch.
- **`{{-` vs `{{`.** Der Bindestrich frisst Whitespace davor. Falsch gesetzt, und dein YAML rutscht zusammen.
- **Selector-Labels sind unveränderlich.** Änderst du `selectorLabels` in einem bestehenden Release, schlägt das Upgrade fehl. Dann hilft nur uninstall/install.
- **Zahlen und Strings.** `tag: 6.7.1` ohne Quotes kann als Zahl interpretiert werden. Immer `| quote` oder Anführungszeichen.

---

## Geschafft, wenn…

- [ ] Ein Chart, zwei Namespaces, sichtbar unterschiedliche Konfiguration
- [ ] `helm template` ist dein Reflex vor jedem Install
- [ ] Du hast einmal `helm upgrade` gemacht und mit `helm rollback` zurückgedreht
- [ ] Du kannst in einem Satz sagen, welches Problem Helm löst
