# Stufe 3 – Argo CD: du deployst nicht mehr, du pushst

**Zeit:** ein Abend (2–3 h)
**Ziel:** Git ist die einzige Wahrheit. Änderungen am Cluster macht nur noch Argo CD.

> **Der Denkwechsel dieser Stufe:** Bisher hast du Zustand *hergestellt* (`helm install`). Ab jetzt *beschreibst* du einen Zielzustand in Git, und ein Controller im Cluster sorgt dauerhaft dafür, dass die Realität dem entspricht. Das ist der Kern von GitOps – und der Grund, warum Argo CD in der Stellenanzeige steht.

---

## 1. Chart nach Git

Leg ein Repo an (GitLab oder GitHub, öffentlich reicht fürs Erste) und pack dein Chart aus Stufe 2 rein:

```
gitops-lab/
└── charts/
    └── podinfo-chart/
        ├── Chart.yaml
        ├── values.yaml
        └── templates/
```

Pushen. Merk dir die Clone-URL.

## 2. Argo CD installieren

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd rollout status deploy/argocd-server
```

UI aufmachen:

```bash
kubectl port-forward svc/argocd-server -n argocd 8081:443
```

→ **https://localhost:8081** (Zertifikatswarnung wegklicken)

Login ist `admin`, das Passwort steht in einem Secret:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
```

## 3. Die Application

Das ist das zentrale Objekt. Leg es im Repo unter `apps/dev.yaml` ab:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: podinfo-dev
  namespace: argocd
spec:
  project: default

  source:
    repoURL: https://github.com/<dein-user>/gitops-lab.git
    targetRevision: main
    path: charts/podinfo-chart
    helm:
      values: |
        replicaCount: 2
        ui:
          color: "#34577c"
          message: "hello from dev"
        ingress:
          host: dev.localhost

  destination:
    server: https://kubernetes.default.svc
    namespace: dev

  syncPolicy:
    automated:
      prune: true        # löscht, was aus Git verschwindet
      selfHeal: true     # dreht manuelle Änderungen am Cluster zurück
    syncOptions:
      - CreateNamespace=true
```

Vorher die alten Helm-Releases aus Stufe 2 entfernen, sonst streiten sich zwei Besitzer um dieselben Objekte:

```bash
helm uninstall dev -n dev
helm uninstall stage -n stage
```

Dann:

```bash
kubectl apply -f apps/dev.yaml
```

Im UI erscheint die App, zieht sich das Repo und deployt. Der Objektbaum zeigt dir Deployment → ReplicaSet → Pods.

## 4. Der Aha-Moment

**Mach das wirklich, das ist der Kern des Abends:**

```bash
kubectl scale deployment podinfo-dev -n dev --replicas=7
kubectl get pods -n dev -w
```

Schau zu. Argo CD merkt die Abweichung und dreht sie innerhalb von Sekunden zurück auf 2. Dasselbe mit `kubectl edit deployment` oder `kubectl delete pod`.

Und jetzt der andere Weg: Änder `replicaCount` in `apps/dev.yaml`, commit, push. Im UI auf **Refresh** – die App wird `OutOfSync`, dann synct sie automatisch.

> Wenn dich das begeistert statt zu nerven, ist das ein starkes Signal für diese Art von Arbeit. Wenn es dich nervt, weil du "einfach mal schnell" etwas ändern willst: auch ein Ergebnis, und zwar ein ehrliches.

## 5. Zweite Umgebung

Kopier `apps/dev.yaml` nach `apps/stage.yaml`, änder Name, Namespace, Werte. Push, apply. Jetzt hast du zwei Apps aus einem Chart – das App-pro-Umgebung-Muster, das du in der Praxis überall sehen wirst.

Wenn du Lust auf mehr hast: das **App-of-Apps-Muster**. Eine Argo-Application zeigt auf ein Verzeichnis, das nur andere Applications enthält. Dann verwaltet Argo CD seine eigenen Apps über Git.

## 6. Status-Vokabular

Diese vier Begriffe wirst du im Job täglich benutzen:

| Status | Bedeutung |
|---|---|
| `Synced` | Cluster entspricht Git |
| `OutOfSync` | Git und Cluster weichen ab |
| `Healthy` | Die Ressourcen laufen wie erwartet |
| `Degraded` | Deployt, aber kaputt (z. B. Pods crashen) |

Wichtig: **Synced und Degraded gleichzeitig ist möglich** und der häufigste Praxisfall. Argo hat genau das ausgerollt, was in Git steht – und das, was in Git steht, funktioniert nicht.

## 7. CLI

```bash
brew install argocd
argocd login localhost:8081 --username admin --insecure
argocd app list
argocd app get podinfo-dev
argocd app diff podinfo-dev      # Git vs. Cluster
argocd app sync podinfo-dev
argocd app history podinfo-dev
argocd app rollback podinfo-dev <revision>
```

`argocd app diff` ist das Werkzeug für die Frage "warum ist das OutOfSync?".

---

## Fallstricke

- **Zwei Besitzer.** Helm-Release *und* Argo auf denselben Objekten → Endlosschleife. Immer nur einer.
- **`prune: true`** löscht echte Ressourcen, wenn sie aus Git verschwinden. Genau so gewollt, aber beim ersten Mal überraschend.
- **`selfHeal: true`** heißt: Manuelles `kubectl edit` ist ab jetzt sinnlos. Das ist der Punkt.
- **Privates Repo** braucht Credentials in Argo (`argocd repo add ... --username ... --password ...`). Fürs Lab ein öffentliches Repo nehmen.

---

## Geschafft, wenn…

- [ ] Ein `git push` verändert deinen Cluster, ohne dass du `kubectl` anfasst
- [ ] Du hast per Hand skaliert und zugesehen, wie selfHeal es zurückdreht
- [ ] Zwei Umgebungen aus einem Chart laufen
- [ ] Du kannst den Unterschied zwischen `OutOfSync` und `Degraded` erklären
