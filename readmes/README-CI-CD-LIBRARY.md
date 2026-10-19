# 🛠️ Documentação da Esteira de CI/CD (`maven-ci-cd-library.yaml`)

Este documento detalha o funcionamento, as responsabilidades e a configuração técnica do pipeline reutilizável de Integração Contínua (CI) e Entrega Contínua (CD) focado no ciclo de vida de **Bibliotecas/Libraries Java (Maven)**.

---

## 🎯 Objetivo da Esteira

Ao contrário de aplicações convencionais (APIs), esta esteira **não** gera imagens Docker e **não** realiza deploys em ambientes de infraestrutura (como Kubernetes/ArgoCD). Seu propósito exclusivo é:
1. **Garantir a Qualidade:** Validar código através de testes e análise estática rigorosa no SonarQube.
2. **Segurança:** Apontar vulnerabilidades conhecidas (CVEs) nas dependências declaradas nos `pom.xml`, que os projetos consumidores herdam ao usar a biblioteca.
3. **Distribuição:** Publicar o artefato compilado (`.jar`) de forma automatizada no gerenciador de pacotes corporativo.

---

## 🏗️ Fluxo de Execução (Jobs)

O pipeline é composto por dois blocos principais executados em sequência:

### 1. Governança e Validação (CI)
* **Notify_Start:** Dispara um alerta no canal do Slack configurado informando que o processo de build foi iniciado.
* **Build & Test (`Maven`):** Configura o ambiente Java na versão parametrizada e executa o comando `mvn clean package dependency:copy-dependencies`. Garante que o código compila e que 100% dos testes unitários/integração passam.
* **Dependency Vulnerability Scanner (`Trivy`):** Lê os `pom.xml` do repositório (`trivy fs`) e procura vulnerabilidades `CRITICAL` e `HIGH` nas dependências, inclusive as transitivas. **Se o scanner falhar, a esteira é interrompida** e nada é publicado sem análise. Em seguida, o **gate de CRITICAL** funciona como nos serviços: em modo aviso (padrão) só alerta; em modo bloqueio, interrompe a esteira antes da publicação. O relatório (tabela e JSON) fica no artifact `<repo>-<versão>-dependency-scanner-report` e um resumo vai para o Slack **a cada execução**, verde quando nada é encontrado (ver [Varredura de dependências](#-varredura-de-dependências-trivy)).
* **Provisionamento SonarQube:** Verifica via API se o projeto já existe no SonarQube. Caso não exista, a esteira cria o projeto automaticamente e injeta as regras de governança (`Quality Gate`, `Quality Profile`, `Permission Template` e `New Code Definition`).
* **SonarQube Scan & Quality Gate:** Executa a análise estática e valida se as métricas atendem ao Quality Gate corporativo (`QG_PNB_BACKEND`). Se falhar no Quality Gate, a esteira é interrompida.

### 2. Distribuição do Artefato (CD)
* **Publish Package:** Condicionado ao input `is_production_branch: true`. Executa o comando `mvn deploy`, utilizando o arquivo `settings.xml` gerado dinamicamente para autenticar e publicar a biblioteca no repositório Maven.
* **Notificações Finais:** Envia o status de conclusão (Sucesso ou Falha) detalhado no Slack.

---

## 📦 Varredura de dependências (Trivy)

A biblioteca não gera imagem Docker, então o Trivy analisa os `pom.xml` em vez da imagem. O scan roda depois do build para que as dependências transitivas sejam resolvidas pelo `~/.m2` que o Maven acabou de preencher.

O resumo no Slack traz a contagem de críticas e altas, **em qual `pom.xml` corrigir** e até 8 CVEs com correção disponível. Se o scanner falhar (por exemplo, sem acesso ao banco de vulnerabilidades ou ao Maven Central), **a esteira falha antes do SonarQube e da publicação**: a mensagem avisa que a varredura não foi concluída, em vez de afirmar que nada foi encontrado, e a notificação de falha de sempre também é enviada. Basta reexecutar o job quando o problema passar. Detalhes da mensagem em [README-SCAN-REPORT-NOTIFY](README-SCAN-REPORT-NOTIFY.md).

| Input | Uso |
|---|---|
| `trivy_block_critical` | Liga o modo bloqueio do gate de CRITICAL com correção disponível. Padrão `false` (modo aviso). A variável `TRIVY_BLOCK_CRITICAL=true` na organização ou no repositório tem o mesmo efeito, igual aos serviços. |
| `trivy_skip_dirs` | Diretórios fora do scan, separados por vírgula, por exemplo módulos de exemplo ou benchmark que não são publicados. `target` e `lib` já ficam de fora. |
| `trivy_skip_files` | Arquivos fora do scan. **Em projeto multimódulo, use `pom.xml`**: o alvo do pom raiz soma as dependências de todos os módulos listados em `<modules>`, inclusive os de `trivy_skip_dirs`, e cada módulo já é analisado no próprio `pom.xml`. Em biblioteca de um módulo só, deixe vazio: o pom raiz é a própria biblioteca. |

Exemplo para um projeto multimódulo com um módulo `examples` que não é publicado:

```yaml
    with:
      # ...
      trivy_skip_dirs: examples
      trivy_skip_files: pom.xml
```

### Gate de CRITICAL: modo aviso × modo bloqueio

| Situação | Modo aviso (padrão) | Modo bloqueio |
|---|---|---|
| O scanner falhou | ❌ esteira interrompida | ❌ esteira interrompida |
| Dependência com CRITICAL **com correção** | ⚠️ anotação "Trivy gate (modo aviso)", tabela no resumo do run e aviso no Slack; a esteira segue e publica | ❌ esteira interrompida antes do SonarQube e da publicação; aviso vermelho no Slack |
| Só altas, ou críticas sem correção | aparecem no resumo do Slack e no relatório; não bloqueiam | idem |

A anotação usa o mesmo título dos serviços, então o script de [medição do modo aviso](README-TRIVY.md#-medir-o-impacto-do-modo-aviso) conta as bibliotecas junto. O JSON do gate fica no artifact `<repo>-<versão>-dependency-vulnerability-gate` por 90 dias.

Exceções justificadas ficam no `.trivyignore` da raiz do repositório, como nos serviços (ver [README-TRIVY](README-TRIVY.md#-exceções-trivyignore)).

---

## 📋 Requisitos no projeto que consome a esteira
Para o passo de publicação (Publish Package) funcionar, o arquivo pom.xml da biblioteca deve conter obrigatoriamente a tag <distributionManagement> apontando para o mesmo ID especificado na esteira (github):

```xml
<distributionManagement>
    <repository>
        <id>github</id>
        <name>GitHub Packages ARTIFACT-ID Snapshots</name>
        <url>https://maven.pkg.github.com/platformbuilders/ARTIFACT-ID</url>
    </repository>
</distributionManagement>
```

---

## ⚙️ Interface do Reusable Workflow

Para consumir esta esteira em qualquer repositório de biblioteca Java da organização, utilize a sintaxe abaixo no workflow local:

```yaml
name: Execute CI/CD

on:
  push:
    branches: [ master, main ]
  pull_request:
    branches: [ master, main ]

jobs:
  run-pipeline:
    uses: platformbuilders/github-actions-bdsp-templates/.github/workflows/maven-ci-cd-library.yaml@main
    with:
      java_version: "JAVA-VERSION"                   # Altere para a versão do seu projeto
      git_ref: ${{ github.ref }}
      is_production_branch: ${{ github.ref == 'refs/heads/master' || github.ref == 'refs/heads/main' }}
      SONAR_BDSP_HOST_URL: ${{ vars.SONAR_BDSP_HOST_URL }}
    secrets:
      SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
      SONAR_BDSP_TOKEN: ${{ secrets.SONAR_BDSP_TOKEN }}
      TOKEN_GITHUB: ${{ secrets.TOKEN_GITHUB }}      # Token com escopo 'write:packages'