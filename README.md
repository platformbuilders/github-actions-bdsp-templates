![GitHub Actions](https://avatars.githubusercontent.com/u/44036562?s=200&v=4)

 

Este repositório contém GitHub Actions customizadas para automação de CI/CD com foco em construção de imagens Docker, deploy com Argo CD e notificações via Slack.

## 🤖 Pipeline de CI/CD

### Publicação de bibliotecas

📦 [Informações técnicas sobre o pipeline de build e publicação](readmes/README-CI-CD-LIBRARY.md)

### Versão do Maven

🧱 [Maven fixado em 3.9.16 por compatibilidade com Quarkus 2.x](readmes/README-MAVEN-VERSION.md)

### Segurança das actions

📌 [Fixação de actions por SHA e passo a passo de atualização](readmes/README-PINNING-ACTIONS.md)

🛡️ [Scan de vulnerabilidades da imagem (Trivy): gate, exceções e avisos no Slack](readmes/README-TRIVY.md)