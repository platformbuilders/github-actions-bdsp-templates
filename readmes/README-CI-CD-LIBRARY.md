# 🛠️ Documentação da Esteira de CI/CD (`maven-ci-cd-library.yaml`)

Este documento detalha o funcionamento, as responsabilidades e a configuração técnica do pipeline reutilizável de Integração Contínua (CI) e Entrega Contínua (CD) focado no ciclo de vida de **Bibliotecas/Libraries Java (Maven)**.

---

## 🎯 Objetivo da Esteira

Ao contrário de aplicações convencionais (APIs), esta esteira **não** gera imagens Docker e **não** realiza deploys em ambientes de infraestrutura (como Kubernetes/ArgoCD). Seu propósito exclusivo é:
1. **Garantir a Qualidade:** Validar código através de testes e análise estática rigorosa no SonarQube.
2. **Segurança:** Bloquear vazamentos de credenciais com varredura de segredos.
3. **Distribuição:** Publicar o artefato compilado (`.jar`) de forma automatizada no gerenciador de pacotes corporativo.

---

## 🏗️ Fluxo de Execução (Jobs)

O pipeline é composto por dois blocos principais executados em sequência:

### 1. Governança e Validação (CI)
* **Notify_Start:** Dispara um alerta no canal do Slack configurado informando que o processo de build foi iniciado.
* **Secret Scanner (`Trufflehog`):** Escaneia o histórico de commits em busca de chaves privadas, senhas ou tokens expostos. Caso encontre, o build é abortado imediatamente e um relatório em `.json` é gerado como artefato do GitHub.
* **Build & Test (`Maven`):** Configura o ambiente Java na versão parametrizada e executa o comando `mvn clean package dependency:copy-dependencies`. Garante que o código compila e que 100% dos testes unitários/integração passam.
* **Provisionamento SonarQube:** Verifica via API se o projeto já existe no SonarQube. Caso não exista, a esteira cria o projeto automaticamente e injeta as regras de governança (`Quality Gate`, `Quality Profile`, `Permission Template` e `New Code Definition`).
* **SonarQube Scan & Quality Gate:** Executa a análise estática e valida se as métricas atendem ao Quality Gate corporativo (`QG_PNB_BACKEND`). Se falhar no Quality Gate, a esteira é interrompida.

### 2. Distribuição do Artefato (CD)
* **Publish Package:** Condicionado ao input `is_production_branch: true`. Executa o comando `mvn deploy`, utilizando o arquivo `settings.xml` gerado dinamicamente para autenticar e publicar a biblioteca no repositório Maven.
* **Notificações Finais:** Envia o status de conclusão (Sucesso ou Falha) detalhado no Slack.

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