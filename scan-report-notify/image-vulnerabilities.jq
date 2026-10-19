# Monta a mensagem do Slack a partir do relatório JSON do Trivy (CRITICAL e HIGH).
# Entrada: o JSON do `trivy image --format json` ou do `trivy fs --format json`.
# Variáveis: $repo, $branch, $tag, $run_url, $block ("true"/"false").
# Opcional: --arg kind dependencies para o relatório do `trivy fs` (bibliotecas): muda o título,
# troca "Imagem" por "Versão" e mostra "onde corrigir" por pom.xml. Sem o argumento, vale "image".
# Saída: o payload do Slack. Sem vulnerabilidades, a mensagem é verde ("nenhuma encontrada").

def plural($n; $um; $varios): if $n == 1 then "\($n) \($um)" else "\($n) \($varios)" end;

($ARGS.named.kind // "image") as $kind
| (if $kind == "dependencies" then "📦 *Vulnerabilidades nas dependências*" else "🛡️ *Vulnerabilidades na imagem*" end) as $title
| (if $kind == "dependencies" then "Versão" else "Imagem" end) as $ref_label
| . as $report

# Uma linha por CVE + pacote; a mesma CVE pode aparecer em mais de um alvo da imagem.
| [ .Results[]? as $r | $r.Vulnerabilities[]? | . + {Class: $r.Class} ]
| unique_by(.VulnerabilityID + "|" + .PkgName)
| map(select(.Severity == "CRITICAL" or .Severity == "HIGH"))
| . as $v
| if ($v | length) == 0 then
  {
    attachments: [{
      color: "#2EB67D",
      blocks: [
        { type: "section",
          text: { type: "mrkdwn", text: "\($title)\n✅ Nenhuma vulnerabilidade crítica ou alta encontrada." },
          fields: [
            { type: "mrkdwn", text: "*Repositório:*\n\($repo)" },
            { type: "mrkdwn", text: "*Branch:*\n\($branch)" },
            { type: "mrkdwn", text: "*\($ref_label):*\n\($tag)" }
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
    (if $kind == "dependencies" then
       # Em projeto multimódulo, cada pom.xml é um alvo do Trivy: aponta em qual módulo corrigir.
       [ $report.Results[]?
         | { alvo: .Target,
             v: ([.Vulnerabilities[]? | select(.Severity == "CRITICAL" or .Severity == "HIGH")]
                 | unique_by(.VulnerabilityID + "|" + .PkgName)) }
         | select((.v | length) > 0) ] as $alvos
       | ($alvos | sort_by(-(.v | map(select(.Severity == "CRITICAL")) | length), -(.v | length), .alvo)) as $alvos
       | ($alvos[:6] | map(onde(.v; "`\(.alvo)`")))
         + (if ($alvos | length) > 6 then ["_… e mais \(($alvos | length) - 6) arquivos_"] else [] end)
       | join("\n")
     else
       [ onde($os; "Imagem base (Dockerfile)"), onde($app; "Dependências da aplicação") ] | join("\n")
     end) as $onde

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
            text: { type: "mrkdwn", text: $title },
            fields: [
              { type: "mrkdwn", text: "*Repositório:*\n\($repo)" },
              { type: "mrkdwn", text: "*Branch:*\n\($branch)" },
              { type: "mrkdwn", text: "*\($ref_label):*\n\($tag)" }
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
