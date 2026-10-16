# 🔔 Resumo dos scanners no Slack

A action [`scan-report-notify`](../scan-report-notify/action.yaml) transforma os relatórios dos scanners da pipeline em uma mensagem curta no Slack, no mesmo canal das demais notificações do serviço (`SLACK_WEBHOOK_URL`).

| Relatório | Scanner | Templates |
|---|---|---|
| Vulnerabilidades da imagem (`CRITICAL` e `HIGH`) | Trivy | `maven-ci-cd`, `maven-ci-cd-package`, `maven-ci-cd-package-non-kustomize`, `maven-ci-cd-bypass-sonar`, `maven-ci-cd-package-bypass-sonar`, `front-ci-cd`, `front-ci-cd-v2`, `front-ci-cd-no-cache`, `front-ci-cd-no-cache-no-sonar` |
| Credenciais válidas no histórico do Git | TruffleHog | `maven-ci-cd`, `maven-ci-cd-package`, `maven-ci-cd-bypass-sonar` |

---

## 📨 Quando a mensagem é enviada

**Sempre**, a cada execução do job de CI, para que quem lê o canal saiba que a verificação aconteceu:

| Situação | Cor | Mensagem |
|---|---|---|
| Há achados | 🔴 vermelha ou 🟠 laranja | contagem, principais itens e botão para a execução |
| Varredura concluída, nada encontrado | 🟢 verde | "Nenhuma vulnerabilidade crítica ou alta encontrada" / "Nenhuma credencial válida encontrada" |
| O scanner não terminou | 🟠 laranja | "A varredura não foi concluída", **nunca** "nada encontrado" |

A notificação é informativa: se o envio falhar, a pipeline **não** falha; aparece só um *warning* no log.

---

## 🛡️ Vulnerabilidades da imagem (Trivy)

- contagem de críticas e altas e quantas já têm correção;
- **onde corrigir:** imagem base (pacotes do sistema, resolvidos no `Dockerfile`) × dependências da aplicação (`pom.xml`/`package.json`);
- até 8 CVEs com correção, críticas primeiro: `CVE` · pacote · versão instalada → versão corrigida;
- o aviso do gate de CRITICAL (modo aviso ou bloqueio), quando se aplica. Ver [README-TRIVY](README-TRIVY.md).

Vermelha quando há crítica com correção; laranja quando há só altas ou críticas sem correção.

## 🔑 Credenciais expostas (TruffleHog)

O passo **Save Secret Scanner Report** varre o **histórico inteiro** do repositório e considera apenas credenciais **verificadas**, ou seja, que ainda funcionam. A mensagem traz, para cada credencial, o tipo (AWS, Postgres…), o arquivo, a linha e o commit onde ela aparece pela primeira vez, mais o número de outras ocorrências.

> 🔒 **A mensagem nunca contém o valor da credencial.** O relatório do TruffleHog traz o valor (`Raw`, `RawV2`) e às vezes um trecho dele (`Redacted`); esses campos são usados só para agrupar ocorrências da mesma credencial e não entram na mensagem.

Remover a credencial do código não basta: ela continua no histórico do Git. A correção é **trocar (rotacionar)** a credencial no sistema de origem.

Credenciais novas trazidas pelo próprio PR já são barradas antes, pelo passo **Run Secret Scanner**, que falha a pipeline e dispara a notificação de falha de sempre.

---

## 🧪 Testar a montagem da mensagem localmente

Os scripts `jq` ficam na pasta da action e podem ser testados com um relatório real (o artifact `*-image-scanner-report` traz o `trivy-report.json`):

```bash
jq -f scan-report-notify/image-vulnerabilities.jq \
  --arg repo meu-servico --arg branch release/1.0.0 --arg tag abc1234 \
  --arg run_url https://exemplo --arg block false \
  trivy-report.json

jq -n -R -f scan-report-notify/secrets.jq \
  --arg repo meu-servico --arg branch release/1.0.0 --arg run_url https://exemplo \
  < meu-servico-secret-scanner-report.json
```
