# 🛡️ Scan de vulnerabilidades da imagem (Trivy)

Este documento explica como os templates usam o [Trivy](https://github.com/aquasecurity/trivy) para escanear a imagem Docker gerada na pipeline. Cobre o gate de vulnerabilidades CRITICAL, os avisos no Slack e como registrar exceções.

Templates que usam o Trivy: `maven-ci-cd`, `maven-ci-cd-package`, `maven-ci-cd-package-non-kustomize`, `maven-ci-cd-bypass-sonar`, `maven-ci-cd-package-bypass-sonar`, `front-ci-cd`, `front-ci-cd-v2`, `front-ci-cd-no-cache` e `front-ci-cd-no-cache-no-sonar`.

> Bibliotecas (`maven-ci-cd-library`) não geram imagem: o Trivy analisa os `pom.xml`, com o mesmo gate de CRITICAL, o mesmo input `trivy_block_critical` e a mesma variável `TRIVY_BLOCK_CRITICAL` descritos abaixo. Ver [README-CI-CD-LIBRARY](README-CI-CD-LIBRARY.md#-varredura-de-dependências-trivy).

---

## 🔎 O que roda no job de CI

Depois do build e push da imagem, estes steps rodam em sequência:

| Step | O que faz | Bloqueia? |
|---|---|---|
| **Run Image Vulnerability Scanner** | escaneia tudo que é `CRITICAL` e `HIGH` e gera `trivy-report.json` | não |
| **Convert Image Vulnerability Report to table** | converte esse JSON na tabela legível, sem escanear a imagem de novo | — |
| **Upload Image Vulnerability Scanner Report** | publica a tabela e o JSON como artifact `<repo>-<tag>-image-scanner-report` | — |
| **Image Vulnerability Gate (CRITICAL)** | procura vulnerabilidades `CRITICAL` **que já têm correção** (`ignore-unfixed`) | só em modo bloqueio |
| **Image Vulnerability Gate Summary** | escreve no resumo do run a tabela de CVEs (pacote, versão instalada e versão corrigida) | — |
| **Upload Image Vulnerability Gate Report** | publica o JSON do gate como artifact `<repo>-<tag>-image-vulnerability-gate`, com **90 dias** de retenção | — |
| **Notify Slack: Image Vulnerability Report** | envia o resumo do relatório para o Slack a cada execução, inclusive sem achados (ver [Aviso no Slack](#-aviso-no-slack)) | — |

O gate considera apenas o que é **CRITICAL e tem versão corrigida disponível**. CVEs sem correção não bloqueiam, porque o time não teria como resolver. Elas continuam aparecendo no relatório em tabela.

---

## 🚦 Modo aviso × modo bloqueio

| Modo | Comportamento | Como ativar |
|---|---|---|
| **Aviso** (padrão) | o job passa; aparece um *warning* "Trivy gate (modo aviso)", a tabela de CVEs no resumo do run e um aviso **laranja** no Slack | nada a fazer |
| **Bloqueio** | o job de CI falha e o deploy (job CD) não roda; aparece um *error* "Trivy gate", a tabela no resumo e um aviso **vermelho** no Slack, além da notificação de falha de sempre | input `trivy_block_critical: true` **ou** variável `TRIVY_BLOCK_CRITICAL=true` |

### Ativar o bloqueio em um serviço específico

No workflow do serviço:

```yaml
jobs:
  pipeline:
    uses: platformbuilders/github-actions-bdsp-templates/.github/workflows/maven-ci-cd-package.yaml@main
    with:
      # ...
      trivy_block_critical: true
```

### Ativar o bloqueio para toda a organização

Crie a variável **`TRIVY_BLOCK_CRITICAL`** com o valor `true` em *Organization settings → Secrets and variables → Actions → Variables*. Todos os serviços passam a bloquear, sem mudar nenhum workflow.

Para manter um serviço específico em modo aviso, crie a mesma variável **no repositório** com o valor `false`. A variável do repositório tem precedência sobre a da organização.

> O input `trivy_block_critical: true` sempre ativa o bloqueio, mesmo que a variável esteja `false`.

### Plano de adoção sugerido

1. **Semanas 1 a 4 (modo aviso):** acompanhar quantos serviços receberiam o aviso (ver [Medir o impacto](#-medir-o-impacto-do-modo-aviso)) e corrigir as CVEs mais comuns. Em geral, a correção é atualizar a imagem base do Dockerfile ou uma dependência do `pom.xml`/`package.json`.
2. **Piloto:** ativar `trivy_block_critical: true` em alguns serviços que já estejam limpos.
3. **Geral:** criar a variável `TRIVY_BLOCK_CRITICAL=true` na organização.

---

## 📝 Exceções: `.trivyignore`

Quando uma CVE não se aplica ao serviço ou a correção precisa de mais tempo, registre uma exceção no arquivo **`.trivyignore` na raiz do repositório do serviço**. O Trivy carrega esse arquivo automaticamente, e não é preciso mudar o workflow.

**Toda exceção precisa de justificativa, responsável e data de expiração:**

```
# CVE-2024-12345 (libfoo): a função vulnerável não é usada; a lib só faz parsing de config local.
# Responsável: @fulano. Revisar quando sair a versão 2.x da imagem base.
CVE-2024-12345 exp:2026-12-31

# CVE-2025-67890 (spring-web): correção exige subir o Spring Boot 3; planejado na sprint 42.
# Responsável: @time-pix
CVE-2025-67890 exp:2026-11-30
```

- `exp:AAAA-MM-DD`: a partir dessa data, a exceção deixa de valer e a CVE volta a ser reportada e a bloquear. Isso evita exceções esquecidas para sempre.
- Use prazos curtos (30 a 90 dias). Se o prazo vencer, renove com nova justificativa em um PR.
- A exceção vale para o relatório em tabela e para o gate.
- Alterações no `.trivyignore` devem passar por code review como qualquer outro código.

---

## 🔔 Aviso no Slack

A cada execução, a action [`scan-report-notify`](../scan-report-notify/action.yaml) envia um resumo do relatório `CRITICAL,HIGH` para o mesmo webhook das outras notificações da pipeline (`SLACK_WEBHOOK_URL`). A mensagem é enviada **sempre**, inclusive sem achados, para que fique claro que a imagem foi verificada. Detalhes em [README-SCAN-REPORT-NOTIFY](README-SCAN-REPORT-NOTIFY.md).

Quando há achados, a mensagem traz:

- repositório, branch e tag da imagem;
- a contagem de críticas e altas e quantas já têm correção;
- **onde corrigir:** imagem base (pacotes do sistema, resolvidos no `Dockerfile`) × dependências da aplicação (`pom.xml`/`package.json`);
- até 8 CVEs com correção, críticas primeiro, no formato `CVE` · pacote · versão instalada → versão corrigida;
- se houver crítica com correção: o aviso do gate ("com o bloqueio ativo, esta pipeline falharia" ou "pipeline bloqueada");
- um botão para abrir o run.

A cor é **vermelha** quando há crítica com correção, **laranja** quando há só altas ou críticas sem correção, e **verde** quando nada foi encontrado. Se o scan não terminar, a mensagem avisa que a varredura não foi concluída, em vez de afirmar que está tudo limpo. Se o envio falhar, o job **não** falha; aparece apenas um *warning* no log.

## 🗂️ Histórico e relatórios

O repositório não usa a aba *Security → Code scanning* do GitHub, porque em repositórios privados ela exige a licença **GitHub Code Security**. O histórico fica assim:

| Onde | O que tem | Retenção |
|---|---|---|
| Resumo do run (aba *Summary*) | tabela de CVEs do gate | a mesma dos logs de Actions |
| Artifact `*-image-vulnerability-gate` | JSON completo do gate (CVEs CRITICAL com correção) | 90 dias |
| Artifact `*-image-scanner-report` | relatório `CRITICAL,HIGH` em tabela e em JSON | 3 ou 7 dias, conforme o template |
| Slack | resumo de cada build | a do canal |

> Para uma visão consolidada de todos os serviços, com histórico e monitoramento contínuo do que está em produção, a próxima etapa avaliada é uma ferramenta self-hosted como o **OWASP Dependency-Track** (alimentado pelo SBOM gerado pelo Trivy) ou o **DefectDojo**.

---

## 📈 Medir o impacto do modo aviso

O gate deixa uma anotação com o título **"Trivy gate (modo aviso)"** em todo run que seria bloqueado. O script abaixo olha o run mais recente de cada repositório da organização e lista os que receberam o aviso:

```bash
ORG=platformbuilders
gh repo list "$ORG" --limit 500 --no-archived --json name --jq '.[].name' |
while read -r repo; do
  run=$(gh api "repos/$ORG/$repo/actions/runs?per_page=1" --jq '.workflow_runs[0].id // empty' 2>/dev/null)
  [ -z "$run" ] && continue
  gh api "repos/$ORG/$repo/actions/runs/$run/jobs" --jq '.jobs[].id' |
  while read -r job; do
    gh api "repos/$ORG/$repo/check-runs/$job/annotations" \
      --jq '.[] | select(.title == "Trivy gate (modo aviso)") | .message'
  done | head -1 | sed "s|^|$repo: |"
done
```

A tabela com as CVEs de cada caso fica no **resumo do run** (aba *Summary*), e o JSON fica no artifact `*-image-vulnerability-gate` (ou `*-dependency-vulnerability-gate`, nas bibliotecas).

---

## 🔧 Manutenção

- A versão do Trivy é fixada pelo input `version` (hoje `v0.76.0`) em todos os steps do Trivy. Ao atualizar, troque em todos os templates. Veja também [README-PINNING-ACTIONS.md](README-PINNING-ACTIONS.md).
- O step do gate usa `skip-setup-trivy: true` para reaproveitar o binário instalado pelo primeiro step.
- Se o Trivy falhar por um problema de infraestrutura (por exemplo, falha ao baixar a base de CVEs), o gate também falha. Em modo aviso, o resumo mostra *"Relatório do gate não foi gerado"*. Em modo bloqueio, o job falha e basta rodar de novo.
