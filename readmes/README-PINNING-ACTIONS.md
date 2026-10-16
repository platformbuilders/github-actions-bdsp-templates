# 📌 Fixação de Actions por SHA

Este documento explica por que as actions de terceiros usadas nos templates são referenciadas pelo **SHA do commit** e mostra o passo a passo para atualizar essas referências.

---

## 🎯 Por que fixar por SHA

Uma referência como `@v4` ou `@master` é **móvel**:

- **Branch** (`@main`, `@master`): cada commit novo no repositório da action entra direto nas nossas pipelines, sem revisão.
- **Tag** (`@v4`, `@v0.36.0`): pode ser apagada e recriada apontando para outro commit. Em ataques de supply chain (como o do `tj-actions/changed-files`, em 2025), o atacante reescreve as tags para apontar para código malicioso.

As actions rodam com acesso ao `GITHUB_TOKEN` e aos secrets do job, que incluem credenciais de GCP, AWS, Sonar e Slack. Um **SHA de commit não muda**: o código executado é sempre exatamente o que foi revisado.

O CodeQL do repositório aponta referências sem SHA com o alerta *"Unpinned tag for a non-immutable Action or reusable workflow"*.

---

## 📏 Regra

1. Toda action de **terceiros** usa o SHA completo de 40 caracteres.
2. A linha **sempre** termina com um comentário da versão que o SHA representa:

   ```yaml
   uses: aquasecurity/trivy-action@ed142fd0673e97e23eac54620cfb913e5ce36c25 # v0.36.0
   ```

   O comentário mostra qual versão está em uso, facilita a revisão de PRs e permite que o Dependabot atualize o pin automaticamente.
3. Ficam de fora da regra:
   - `actions/*` e `github/*`: mantidas pelo próprio GitHub (o CodeQL não alerta sobre elas);
   - `platformbuilders/*`: actions deste próprio repositório.

---

## 🔄 Passo a passo para atualizar uma action

O exemplo abaixo usa `aquasecurity/trivy-action`. O processo é o mesmo para qualquer action.

### 1. Descobrir a versão desejada

```bash
gh api repos/aquasecurity/trivy-action/releases/latest --jq '.tag_name'
# v0.36.0
```

Também dá para consultar na página de releases do projeto, em `https://github.com/<owner>/<repo>/releases`.

> Use sempre uma **release/tag publicada**, nunca o último commit de `main`/`master`.

### 2. Ler as release notes

Antes de trocar de versão, leia o que mudou entre a versão atual (o comentário da linha) e a nova:

```bash
gh release view v0.36.0 --repo aquasecurity/trivy-action
# ou, para ver todos os commits entre as duas versões:
gh api repos/aquasecurity/trivy-action/compare/v0.35.0...v0.36.0 \
  --jq '.commits[].commit.message | split("\n")[0]'
```

Atenção a mudanças de **major** (`v1` → `v2`). Elas costumam trazer *breaking changes*, como inputs renomeados, nova versão de Node ou exigência de versão mínima do runner.

### 3. Obter o SHA do commit da tag

```bash
gh api repos/aquasecurity/trivy-action/commits/v0.36.0 --jq '.sha'
# ed142fd0673e97e23eac54620cfb913e5ce36c25
```

> ⚠️ **Não use** `gh api repos/<owner>/<repo>/git/ref/tags/<tag>`. Em tags *anotadas*, esse endpoint devolve o SHA do **objeto da tag**, e não o do commit. Por exemplo, no `trivy-action` v0.36.0 ele retorna `a9c7b0f…`, mas o commit é `ed142fd…`. O endpoint `commits/<tag>` sempre devolve o SHA do commit, que é o que o `uses:` espera.

Sem o `gh`, dá para usar só o `git`:

```bash
git ls-remote https://github.com/aquasecurity/trivy-action 'refs/tags/v0.36.0^{}' 'refs/tags/v0.36.0'
# Se aparecer a linha com ^{}, use o SHA dela (tag anotada); senão, use o da outra linha.
```

### 4. Atualizar todas as ocorrências

A mesma action aparece em vários templates. Liste todas:

```bash
grep -rn "aquasecurity/trivy-action@" .github/workflows */action.yaml
```

Troque o SHA **e** o comentário em cada uma delas:

```yaml
uses: aquasecurity/trivy-action@<novo-sha> # <nova-versão>
```

Um `sed` resolve de uma vez, mas confira o `git diff` em seguida:

```bash
OLD_SHA=ed142fd0673e97e23eac54620cfb913e5ce36c25; OLD_VER=v0.36.0
NEW_SHA=<novo-sha>; NEW_VER=<nova-versão>
grep -rl "$OLD_SHA" .github/workflows */action.yaml \
  | xargs sed -i '' "s|@$OLD_SHA # $OLD_VER|@$NEW_SHA # $NEW_VER|g"   # no Linux: sed -i (sem '')
git diff
```

### 5. Verificar os casos especiais (abaixo)

Algumas actions baixam um binário ou uma imagem separadamente. Nesses casos, fixar o SHA da action não basta.

### 6. Abrir o PR

- No título e na descrição, informe a versão antiga, a nova e os pontos relevantes das release notes.
- Os templates são consumidos com `@main` por todos os serviços, então **o merge vale imediatamente para todas as pipelines**. Valide rodando a pipeline de pelo menos um serviço Maven e um front.

---

## ⚠️ Casos especiais

### `aquasecurity/trivy-action`: versão do Trivy

A action instala o binário do Trivy numa versão definida pelo input `version`. O valor padrão desse input muda a cada release da action. Por isso, os templates fixam a versão explicitamente:

```yaml
uses: aquasecurity/trivy-action@ed142fd0673e97e23eac54620cfb913e5ce36c25 # v0.36.0
with:
  version: "v0.76.0"
```

Para atualizar o scanner, troque o `version`. As versões disponíveis estão em https://github.com/aquasecurity/trivy/releases.

### `trufflesecurity/trufflehog`: imagem Docker e script de instalação

A action executa a imagem `ghcr.io/trufflesecurity/trufflehog:<version>`. O padrão é `latest`, que muda a cada release. Os templates fixam essa versão:

```yaml
uses: trufflesecurity/trufflehog@e76dff8a7e57d6df0c60ad8cbf5d5cba505a8fc9 # v3.99.2
with:
  version: "3.99.2"   # sem o "v": é a tag da imagem Docker
```

Alguns templates também instalam a CLI com um script baixado do GitHub. A URL do script usa o SHA (em vez de `main`), e a versão do binário vem no fim do comando:

```bash
curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/e76dff8a7e57d6df0c60ad8cbf5d5cba505a8fc9/scripts/install.sh \
  | sh -s -- -b /usr/local/bin v3.90.11
```

Ao atualizar o Trufflehog, atualize os três pontos: o SHA do `uses:`, o input `version` e a URL do `install.sh`.

---

## 📋 Versões fixadas atualmente

| Action | Versão | SHA |
|---|---|---|
| `aquasecurity/trivy-action` | v0.36.0 (Trivy v0.76.0) | `ed142fd0673e97e23eac54620cfb913e5ce36c25` |
| `trufflesecurity/trufflehog` | v3.99.2 | `e76dff8a7e57d6df0c60ad8cbf5d5cba505a8fc9` |
| `sonarsource/sonarqube-scan-action` | v8.3.0 | `d209202bc7d53ff1cc128f7f907dac145c9d6ae9` |
| `sonarsource/sonarqube-quality-gate-action` | v1.2.1 | `7a5fffe8e523c40e0c740b6bc2712ab503e52efa` |
| `google-github-actions/auth` | v2.1.13 | `c200f3691d83b41bf9bbd8638997a462592937ed` |
| `docker/login-action` | v4.6.0 | `dbcb813823bdd20940b903addbd779551569679f` |

> Ao atualizar uma action, atualize também esta tabela.

---

## 🤖 Automação (opcional)

O Dependabot entende o formato `@<sha> # <versão>`. Ele abre PRs atualizando o SHA e o comentário juntos sempre que sai uma release nova. Para ativar, crie o arquivo `.github/dependabot.yml`:

```yaml
version: 2
updates:
  - package-ecosystem: "github-actions"
    directories:
      - "/"
      - "/build-push-image"
      - "/build-push-image-no-cache"
    schedule:
      interval: "weekly"
```

Os PRs do Dependabot passam pela mesma revisão (passos 2, 5 e 6). Ele não atualiza os inputs `version` nem a URL do `install.sh` descritos nos casos especiais.
