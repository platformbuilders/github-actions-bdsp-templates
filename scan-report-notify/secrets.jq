# Monta a mensagem do Slack a partir do relatório do TruffleHog (uma linha JSON por achado).
# Uso: jq -n -R -f secrets.jq --arg ... < relatorio.json
# Variáveis: $repo, $branch, $run_url.
# Saída: o payload do Slack. Sem credenciais verificadas, a mensagem é verde ("nenhuma encontrada").
#
# SEGURANÇA: o relatório traz o valor da credencial (Raw, RawV2) e às vezes um trecho dele
# (Redacted). Esses campos são usados apenas para agrupar ocorrências da mesma credencial e
# NUNCA entram na mensagem. Só saem o tipo da credencial, o arquivo, a linha e o commit.

[ inputs | fromjson? | select(type == "object" and .Verified == true) ]
| group_by(.DetectorName + "|" + ((.RawV2 // .Raw // "") | @base64))
| map({
    detector: .[0].DetectorName,
    file:     (.[0].SourceMetadata.Data.Git.file // "?"),
    line:     (.[0].SourceMetadata.Data.Git.line // null),
    commit:   ((.[0].SourceMetadata.Data.Git.commit // "") | .[0:7]),
    count:    length
  })
| . as $creds
| if ($creds | length) == 0 then
  {
    attachments: [{
      color: "#2EB67D",
      blocks: [
        { type: "section",
          text: { type: "mrkdwn", text: "🔑 *Credenciais expostas no repositório*\n✅ Nenhuma credencial válida encontrada no histórico do Git." },
          fields: [
            { type: "mrkdwn", text: "*Repositório:*\n\($repo)" },
            { type: "mrkdwn", text: "*Branch:*\n\($branch)" }
          ] }
      ]
    }]
  }
else

  ($creds[:8] | map(
      "• *\(.detector)*  `\(.file)\(if .line then ":\(.line)" else "" end)`"
      + (if .commit != "" then " · commit `\(.commit)`" else "" end)
      + (if .count > 1 then " _(+\(.count - 1) ocorrência\(if .count > 2 then "s" else "" end))_" else "" end)
    ) | join("\n")) as $lista
  | (if ($creds | length) > 8 then "\n_… e mais \(($creds | length) - 8)_" else "" end) as $mais
  | ($creds | length) as $n

  | {
      attachments: [{
        color: "#FF0000",
        blocks: [
          { type: "section",
            text: { type: "mrkdwn", text: "🔑 *Credenciais expostas no repositório*" },
            fields: [
              { type: "mrkdwn", text: "*Repositório:*\n\($repo)" },
              { type: "mrkdwn", text: "*Branch:*\n\($branch)" }
            ] },
          { type: "section",
            text: { type: "mrkdwn", text: (
              "⚠️ *\($n) credencia\(if $n == 1 then "l VÁLIDA encontrada" else "is VÁLIDAS encontradas" end)* no histórico do Git.\n"
              + "\(if $n == 1 then "Ela ainda funciona e precisa" else "Elas ainda funcionam e precisam" end) ser trocada\(if $n == 1 then "" else "s" end) (rotacionada\(if $n == 1 then "" else "s" end))."
            ) } },
          { type: "section", text: { type: "mrkdwn", text: "\($lista)\($mais)" } },
          { type: "context", elements: [{ type: "mrkdwn",
              text: "Remover do código não basta: a credencial continua no histórico do Git. Troque-a no sistema de origem." }] },
          { type: "actions", elements: [
              { type: "button", text: { type: "plain_text", text: "Ver detalhes" }, url: $run_url } ] }
        ]
      }]
    }
  end
