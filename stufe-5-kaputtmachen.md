# Stufe 5 – Kaputtmachen: der eigentliche Test

**Zeit:** ein Abend, gerne auch zwei
**Ziel:** Du erzeugst gezielt Störungen und findest die Ursache **ohne** in deine eigene Änderung zu schauen.

---

## Spielregeln

1. Fehler einbauen, Terminal-Historie wegscrollen, **kurz Pause machen**.
2. Nur über Symptome arbeiten: Grafana, `kubectl get/describe/logs`, Argo-UI.
3. Erst wenn du eine Hypothese *und* den Beleg dafür hast, darfst du nachsehen, ob sie stimmt.
4. Nach jedem Fall zwei Sätze notieren: **Woran habe ich es erkannt?**

Diese Notizen sind am Ende deine ehrlichste Antwort auf die Frage, ob dir der Job liegt.

---

## Fall 1 – Image-Tag existiert nicht

```bash
# in Git: image.tag auf "6.7.1-gibtsnicht" ändern, push
```

**Symptom:** Argo bleibt Progressing, alte Pods laufen weiter.
**Der Weg:** `kubectl get pods` zeigt `ImagePullBackOff` oder `ErrImagePull`. `kubectl describe pod` → Events unten.
**Lernpunkt:** Das Rolling Update *schützt* dich hier – die alte Version bleibt online. Guter Moment, um `maxUnavailable` und `maxSurge` nachzulesen.

## Fall 2 – Speicherlimit zu niedrig

```yaml
resources:
  limits:
    memory: 16Mi
```

**Symptom:** Pods starten und sterben in Schleife, `CrashLoopBackOff`.
**Der Weg:** `kubectl describe pod` → `Last State: Terminated, Reason: OOMKilled, Exit Code: 137`. In Grafana der Memory-Graph, der gegen die Limit-Linie läuft.
**Lernpunkt:** **137 = 128 + 9**, also SIGKILL – der Prozess wurde hart abgeschossen, nicht sauber beendet. Diese Zahl erkennst du ab jetzt sofort wieder. Und: `kubectl logs` zeigt nichts Hilfreiches, weil die App gar nicht weiß, dass sie stirbt. Nutz `kubectl logs --previous`.

## Fall 3 – Liveness-Probe auf falschem Pfad

```yaml
livenessProbe:
  httpGet:
    path: /gibtsnicht
    port: http
```

**Symptom:** Pods starten, laufen kurz, werden neu gestartet. Restart-Count steigt.
**Der Weg:** Events zeigen `Liveness probe failed: HTTP probe failed with statuscode: 404`. Die App-Logs sind völlig unauffällig – das ist der verwirrende Teil.
**Lernpunkt:** Die App ist gesund, das *Monitoring der App* ist kaputt. Diese Sorte Fehler kostet in echt am meisten Zeit, weil man instinktiv die Anwendung verdächtigt.

## Fall 4 – Readiness aus

```bash
kubectl exec -n dev deploy/podinfo-dev -- curl -s -X POST localhost:9898/readyz/disable
```

**Symptom:** Der Ingress liefert 503, die Pods laufen aber, keine Restarts.
**Der Weg:** `kubectl get pods` zeigt `0/1 Ready`. `kubectl get endpoints` ist leer.
**Lernpunkt:** Der Unterschied zwischen Liveness und Readiness in einem Bild: Liveness tötet den Pod, Readiness nimmt ihn nur aus dem Loadbalancing. Rückgängig mit `/readyz/enable`.

## Fall 5 – Service-Selector passt nicht

Änder im Service-Template den Selector auf ein Label, das kein Pod trägt.

**Symptom:** 503 vom Ingress. Pods sind `1/1 Running` und kerngesund.
**Der Weg:** `kubectl get endpoints podinfo-dev -n dev` → `<none>`.
**Lernpunkt:** Leere Endpoints sind der schnellste Test bei "Service antwortet nicht". Merk dir diesen Befehl besser als jeden anderen aus diesem Handout.

## Fall 6 – Echte Fehler und Latenz

```bash
kubectl port-forward -n dev svc/podinfo-dev 8088:80

# 500er erzeugen
for i in $(seq 1 300); do curl -s -o /dev/null localhost:8088/status/500; done

# Latenz erzeugen
for i in $(seq 1 50); do curl -s -o /dev/null localhost:8088/delay/2 & done
```

**Symptom:** Nichts in `kubectl` – Pods laufen normal.
**Der Weg:** Nur über Grafana sichtbar. Fehlerrate steigt, dein Alert aus Stufe 4 geht auf `Pending` und dann `Firing`. Beim Delay bleibt die Fehlerrate flach, aber p95 steigt.
**Lernpunkt:** Das ist die wichtigste Übung des Abends. Manche Störungen sind auf Infrastrukturebene komplett unsichtbar. Genau dafür existiert Observability – und genau das meint "professionelles Monitoring" in der Stellenanzeige.

## Fall 7 – Falsch benannter Config-Key

Änder im ServiceMonitor `port: http` auf `port: 9898`.

**Symptom:** Metriken hören auf. Kein Fehler, keine Warnung, nirgends.
**Der Weg:** Prometheus */targets* → Target ist verschwunden.
**Lernpunkt:** Deklarative Systeme scheitern oft **still**. Nichts ist rot, es passiert nur nichts mehr. Das ist eine der unangenehmeren Eigenschaften dieser Arbeit.

## Fall 8 – Drift

```bash
kubectl set image deployment/podinfo-dev podinfo=ghcr.io/stefanprodan/podinfo:6.6.0 -n dev
```

**Symptom:** Kurz sichtbar, dann von selbst zurück.
**Lernpunkt:** Das ist selfHeal aus Stufe 3. Bei `selfHeal: false` bliebe die Abweichung stehen und Argo zeigte dauerhaft `OutOfSync` – der Zustand, den du bei Kunden regelmäßig vorfinden wirst.

---

## Die Debugging-Reihenfolge

Wenn dich im Job jemand mit "die Seite geht nicht" anspricht, arbeitest du dich von außen nach innen:

```
1. Ingress da?          kubectl get ingress
2. Endpoints gefüllt?   kubectl get endpoints <svc>     ← häufigste Fundstelle
3. Pods Ready?          kubectl get pods
4. Warum nicht?         kubectl describe pod   (Events!)
5. Was sagt die App?    kubectl logs / --previous
6. Unsichtbar?          Grafana: Rate, Errors, Duration
```

Vier Befehle decken den Großteil ab: `get pods`, `get endpoints`, `describe pod`, `logs --previous`.

---

## Und jetzt die eigentliche Frage

Nach diesen Fällen hast du eine belastbare Antwort. Achte auf deine Reaktion in dem Moment, in dem etwas kaputt ist und du **nicht** weißt, warum:

- **Gute Vorzeichen:** Du willst der Sache auf den Grund gehen. Der Moment, in dem die Ursache klickt, fühlt sich gut an. Du fängst an, Sachen zu automatisieren, die dich genervt haben.
- **Ehrliche Gegenanzeichen:** Du willst eigentlich zurück ins Feature-Bauen. YAML fühlt sich nach Verwaltung statt nach Bauen an. Das Fehlen von sichtbarem Fortschritt frustriert dich.

Das zweite Ergebnis ist kein Scheitern. Es ist eine sehr günstige Erkenntnis – ein paar Abende statt einer Probezeit.

---

## Wenn es dir Spaß gemacht hat

Die nächsten Schritte, in dieser Reihenfolge:

1. **Eigene App statt podinfo.** Ein kleiner Ktor- oder Spring-Boot-Service mit Micrometer, damit die Metriken von dir kommen.
2. **GitLab CI.** Repo auf gitlab.com, Pipeline baut das Image, schreibt den neuen Tag ins GitOps-Repo, Argo zieht nach. Genau der Stack aus der Anzeige.
3. **Terraform gegen GCP.** Free Tier, ein kleines GKE-Cluster deklarativ erzeugen.
4. **Terragrunt.** Erst wenn du den Copy-Paste-Schmerz bei mehreren Umgebungen selbst gespürt hast.
5. **Istio.** Ganz zum Schluss, mit Absicht.
