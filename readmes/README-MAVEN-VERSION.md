# 🧱 Versão fixa do Maven

Os workflows `maven-ci-cd*` **não usam o Maven que vem na imagem do runner**. Eles instalam uma versão fixa do Apache Maven com a action [`setup-maven`](../setup-maven/action.yaml), logo depois do `Set up JDK`.

> ⚠️ **A versão está fixada em `3.9.16` por causa das aplicações Quarkus 2.x.**
> Ela deve ser atualizada assim que todas as aplicações Quarkus forem migradas para Quarkus 3.x.

---

## 🎯 Por que a versão é fixada

Em outubro de 2026, a imagem `ubuntu-24.04` dos runners do GitHub (a partir da `ubuntu24/20261004`) atualizou o Maven de **3.9.16** para **3.10.0**.

O Maven 3.10.0 traz o **Maven Resolver 2.x**, que removeu a classe `org.eclipse.aether.spi.locator.ServiceLocator`. O `quarkus-maven-plugin` da linha **2.x** depende dessa classe, e o build falha no goal `generate-code`:

```
Failed to execute goal io.quarkus.platform:quarkus-maven-plugin:2.15.1.Final:generate-code (default) on project wallets:
A required class was missing while executing io.quarkus.platform:quarkus-maven-plugin:2.15.1.Final:generate-code:
org/eclipse/aether/spi/locator/ServiceLocator
```

Exemplo: [wallets-services, run 38937097631](https://github.com/platformbuilders/wallets-services/actions/runs/38937097631).

### Compatibilidade testada

Teste feito com um projeto Quarkus mínimo (`mvn package`), com JDK 17:

| Quarkus | Maven 3.10.0 | Maven 3.9.16 |
|---|---|---|
| 2.6.2, 2.9.2, 2.10.4, 2.13.5, 2.15.1, 2.16.12 | ❌ falha | ✅ |
| 3.2.2, 3.4.1, 3.6.6, 3.8.6, 3.15.7, 3.20.6, 3.27.6, 3.40.1 | ✅ | ✅ |

Aplicações Spring Boot não são afetadas: funcionam nas duas versões.

---

## 🔧 Como sobrescrever a versão em um serviço

Todos os workflows `maven-ci-cd*` (exceto `maven-ci-cd-teste`) aceitam o input opcional `maven_version`:

```yaml
jobs:
  pipeline:
    uses: platformbuilders/github-actions-bdsp-templates/.github/workflows/maven-ci-cd.yaml@main
    with:
      java_version: '17'
      maven_version: '3.10.0'   # opcional; o padrão é 3.9.16
```

Use isso apenas em serviços que **não** sejam Quarkus 2.x.

---

## 🔄 Quando e como atualizar

**Quando:** depois que **todas** as aplicações Quarkus 2.x que usam estes templates forem migradas para Quarkus 3.x.

**Como:**

1. Confirme que não há mais nenhuma aplicação com `quarkus.platform.version` 2.x usando os templates.
2. Atualize o `default` em:
   - `setup-maven/action.yaml` (input `version`);
   - o input `maven_version` de cada workflow `.github/workflows/maven-ci-cd*.yaml`.
3. Atualize este documento (a versão no aviso do topo e na tabela de compatibilidade).
4. Rode a pipeline de pelo menos um serviço Quarkus e um Spring Boot antes do merge, apontando temporariamente o template para a branch do PR.

> 💡 Se no futuro a fixação deixar de ser necessária, a alternativa é remover o passo `Set up Maven` dos workflows e voltar a usar o Maven da imagem do runner.
