# Stufe 1 – Cluster und erstes Deployment von Hand

**Zeit:** ein Abend (2–3 h)
**Ziel:** Du hast einen laufenden Kubernetes-Cluster und eine App im Browser – und hast jedes YAML selbst getippt.

> Die Regel für diesen Abend: **kein Helm, kein `kubectl create deployment`.** Alles von Hand. Das ist unbequem und genau deshalb lernst du hier die Objekte, auf denen alles andere aufbaut.

---

## 1. Vorbereitung

Du brauchst Docker (Desktop oder Colima) und zwei CLI-Tools:

```bash
# macOS
brew install k3d kubectl

# Linux
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
# kubectl: siehe https://kubernetes.io/docs/tasks/tools/
```

## 2. Cluster starten

```bash
k3d cluster create lab -p "8080:80@loadbalancer" --agents 2
```

Was hier passiert: k3d startet einen k3s-Cluster in Docker-Containern – ein Server-Node plus zwei Agents. Der Port-Mapping-Teil leitet `localhost:8080` auf den Loadbalancer des Clusters, damit du später über den Browser reinkommst. k3s bringt Traefik als Ingress-Controller schon mit.

Prüfen:

```bash
kubectl get nodes
kubectl get pods -A
```

Du solltest drei Nodes sehen und im Namespace `kube-system` unter anderem Traefik und CoreDNS.

## 3. Namespace

```bash
kubectl create namespace demo
kubectl config set-context --current --namespace=demo
```

Die zweite Zeile spart dir ab jetzt das ständige `-n demo`.

## 4. Die drei Objekte

Leg einen Ordner `stufe1/` an und schreib die folgenden drei Dateien.

### `deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: podinfo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: podinfo
  template:
    metadata:
      labels:
        app: podinfo
    spec:
      containers:
        - name: podinfo
          image: ghcr.io/stefanprodan/podinfo:6.7.1
          ports:
            - name: http
              containerPort: 9898
          env:
            - name: PODINFO_UI_COLOR
              value: "#34577c"
          livenessProbe:
            httpGet:
              path: /healthz
              port: http
            initialDelaySeconds: 5
          readinessProbe:
            httpGet:
              path: /readyz
              port: http
            initialDelaySeconds: 5
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 500m
              memory: 128Mi
```

### `service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: podinfo
spec:
  selector:
    app: podinfo
  ports:
    - name: http
      port: 80
      targetPort: http
```

### `ingress.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: podinfo
spec:
  rules:
    - host: podinfo.localhost
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: podinfo
                port:
                  number: 80
```

Anwenden:

```bash
kubectl apply -f stufe1/
kubectl get pods -w      # warten bis 2/2 Running
```

Dann im Browser: **http://podinfo.localhost:8080**

Falls dein System `*.localhost` nicht auflöst, trag `127.0.0.1 podinfo.localhost` in `/etc/hosts` ein.

---

## 5. Das Wichtigste: die Kette verstehen

Bevor du weitermachst, beantworte dir diese Fragen selbst – notfalls mit `kubectl describe`:

1. Warum steht im Service `targetPort: http` und nicht `9898`? Was passiert, wenn du im Deployment den Portnamen änderst, im Service aber nicht?
2. Der Service findet die Pods über `selector: app: podinfo`. Was passiert, wenn du im Deployment das Label `app` auf `podinfo-v2` änderst, im Service aber nicht? Probier es aus und schau dir `kubectl get endpoints podinfo` an.
3. Was ist der Unterschied zwischen Liveness und Readiness? Was passiert jeweils, wenn die Probe fehlschlägt?

> **Endpoints sind dein wichtigstes Debugging-Werkzeug.** Wenn `kubectl get endpoints <service>` leer ist, stimmt der Selector nicht – das ist die häufigste Ursache für "Service antwortet nicht", die dir später in echt begegnet.

## 6. Kommandos, die du ab jetzt ständig brauchst

```bash
kubectl get pods -o wide
kubectl describe pod <name>        # Events am Ende sind das Gold
kubectl logs <pod> -f
kubectl logs <pod> --previous      # Logs des abgestürzten Vorgängers
kubectl exec -it <pod> -- sh
kubectl port-forward svc/podinfo 9898:80
kubectl get events --sort-by=.lastTimestamp
```

Im UI von podinfo siehst du die Endpunkte, die die App anbietet – unter anderem `/version`, `/headers`, `/env`, `/delay/{sekunden}`, `/status/{code}` und `/panic`. Die brauchst du in Stufe 5 wieder.

## 7. Aufräumen / Weiterarbeiten

Der Cluster darf gerne stehenbleiben – du baust in Stufe 2 darauf auf. Falls doch:

```bash
k3d cluster stop lab     # pausieren
k3d cluster start lab
k3d cluster delete lab   # weg
```

---

## Geschafft, wenn…

- [ ] podinfo ist im Browser über den Ingress erreichbar
- [ ] Du kannst erklären, wie Ingress → Service → Pod zusammenhängen
- [ ] Du hast den Selector absichtlich kaputtgemacht und mit `get endpoints` gefunden
- [ ] `kubectl describe pod` fühlt sich nicht mehr fremd an
