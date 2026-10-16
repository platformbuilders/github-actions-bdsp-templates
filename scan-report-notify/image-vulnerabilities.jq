# Monta a mensagem do Slack a partir do relatório JSON do Trivy (CRITICAL e HIGH).
# Entrada: o JSON do `trivy image --format json`.
# Variáveis: $repo, $branch, $tag, $run_url, $block ("true"/"false").
# Saída: o payload do Slack. Sem vulnerabilidades, a mensagem é verde ("nenhuma encontrada").

def plural($n; $um; $varios): if $n == 1 then "\($n) \($um)" else "\($n) \($varios)" end;

# Uma linha por CVE + pacote; a mesma CVE pode aparecer em mais de um alvo da imagem.
[ .Results[]? as $r | $r.Vulnerabilities[]? | . + {Class: $r.Class} ]
| unique_by(.VulnerabilityID + "|" + .PkgName)
| map(select(.Severity == "CRITICAL" or .Severity == "HIGH"))
| . as $v
| if ($v | length) == 0 then
  {
    attachments: [{
      color: "#2EB67D",
      blocks: [
        { type: "section",
          text: { type: "mrkdwn", text: "🛡️ *Vulnerabilidades na imagem*\n✅ Nenhuma vulnerabilidade crítica ou alta encontrada." },
          fields: [
            { type: "mrkdwn", text: "*Repositório:*\n\($repo)" },
            { type: "mrkdwn", text: "*Branch:*\n\($branch)" },
            { type: "mrkdwn", text: "*Imagem:*\n\($tag)" }
          ] }
      ]
    }]
  }
else

  ($v | map(select(.Severity == "CRITICAL"))) as $crit
  | ($v | map(select(.Severity == "HIGH"))) as $high
  | ($v | map(select((.FixedVersion // "") != ""))) as $fixable
  | ($crit | map(select((.FixedVersion // "") != ""))) as $crit_fix

  # Onde corrigir: pacotes do sistema operacional vêm da imagem base; o resto, da aplicação.
  | ($v | map(select(.Class == "os-pkgs"))) as $os
  | ($v | map(select(.Class != "os-pkgs"))) as $app
  | def onde($lista; $rotulo):
      if ($lista | length) == 0 then empty else
        "• \($rotulo): " + ([
          (($lista | map(select(.Severity == "CRITICAL")) | length) as $n | select($n > 0) | plural($n; "crítica"; "críticas")),
          (($lista | map(select(.Severity == "HIGH")) | length) as $n | select($n > 0) | plural($n; "alta"; "altas"))
        ] | join(", "))
      end;
    ([ onde($os; "Imagem base (Dockerfile)"), onde($app; "Dependências da aplicação") ] | join("\n")) as $onde

  # Principais: críticas com correção primeiro, depois altas com correção.
  | ($fixable | sort_by(if .Severity == "CRITICAL" then 0 else 1 end, .VulnerabilityID)) as $top
  | ($top[:8] | map(
      (if .Severity == "CRITICAL" then "🔴" else "🟠" end)
      + " `\(.VulnerabilityID)` \(.PkgName) \(.InstalledVersion) → \(.FixedVersion)"
    ) | join("\n")) as $lista
  | (if ($top | length) > 8 then "\n_… e mais \(($top | length) - 8) com correção_" else "" end) as $mais

  | (if $block == "true" and ($crit_fix | length) > 0
       then "❌ *Pipeline bloqueada:* há vulnerabilidade crítica com correção disponível."
     elif ($crit_fix | length) > 0
       then "⚠️ Há vulnerabilidade crítica com correção disponível. Com o bloqueio do gate ativo, esta pipeline falharia."
     else null end) as $aviso

  | {
      attachments: [{
        color: (if ($crit_fix | length) > 0 then "#FF0000" else "#FFA500" end),
        blocks: ([
          { type: "section",
            text: { type: "mrkdwn", text: "🛡️ *Vulnerabilidades na imagem*" },
            fields: [
              { type: "mrkdwn", text: "*Repositório:*\n\($repo)" },
              { type: "mrkdwn", text: "*Branch:*\n\($branch)" },
              { type: "mrkdwn", text: "*Imagem:*\n\($tag)" }
            ] },
          { type: "section",
            text: { type: "mrkdwn", text: (
              "🔴 *\(plural($crit | length; "crítica"; "críticas"))*    🟠 *\(plural($high | length; "alta"; "altas"))*\n"
              + "✅ \($fixable | length) já \(if ($fixable | length) == 1 then "tem" else "têm" end) correção disponível"
            ) } },
          { type: "section", text: { type: "mrkdwn", text: "*Onde corrigir:*\n\($onde)" } }
        ]
        + (if ($top | length) > 0
             then [{ type: "section", text: { type: "mrkdwn", text: "*Principais (com correção):*\n\($lista)\($mais)" } }]
             else [] end)
        + ([$aviso | select(. != null)] | map({ type: "context", elements: [{ type: "mrkdwn", text: . }] }))
        + [{ type: "actions", elements: [
              { type: "button", text: { type: "plain_text", text: "Ver relatório completo" }, url: $run_url } ] }])
      }]
    }
  end
