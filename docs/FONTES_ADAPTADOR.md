# Adaptador de fonte (5C)

Como uma fonte autorizada real entra no app: um arquivo por fonte,
sem tocar no contrato geral.

## Onde mora

```text
lib/services/sources/
  source_adapter.dart       contrato + registro (NÃO muda por fonte)
  source_credentials.dart   segredos: contrato + memória + keychain
  demo_source_adapter.dart  fonte demo realista (só testes)
  <fonte>_source.dart       UMA fonte real (futuro, um arquivo cada)
```

## Contrato `SourceAdapter`

| Membro | Papel |
|---|---|
| `id` | Identificador estável (`demo.source`) |
| `canHandle(uri)` | Diz se entende a URL (host/padrão) |
| `headersFor(uri, creds)` | Cabeçalhos + auth do cofre; nunca loga |
| `parseCatalog(body)` | Formato da fonte → itens; estrito, pula inválidos |
| `manifestFor(url, n)` | Manifesto da revisão humana |
| `pageUrl` / `searchUrl` | Nulo = não suporta (app fatia/filtra local) |

Registro puro: o primeiro que casa a URL vence; nenhum = formato
genérico `{"items": [...]}`. Fontes locais e catálogo embutido nunca
passam por adaptador.

## Regra de segurança (não negociável)

Fonte desconhecida fornece **dados compatíveis**, nunca código: o
adaptador é código revisado que vem no app; tudo que a fonte envia é
validado na borda como dado. Nada do feed vira lógica, path, SQL ou
markup executável.

## Pipeline de rede (toda fonte passa por ele)

```text
URL http/https → SSRF (literal/DNS, falha fechado) → fetch (timeout,
256 KB, redirects manuais revalidados, max 3, auth só na origem)
→ parse estrito (500 itens, inválidos pulados) → isolamento por fonte
```

DNS-rebinding completo (pinar IP + Host/SNI) entra no adaptador real
se a fonte exigir; o bloqueio direto já está fechado.

## Credenciais

`SourceCredentialStore`: uma chave opaca por fonte. Produção usa
`SecureCredentialStore` (Keystore/Keychain/Credential Manager via
`flutter_secure_storage`); testes usam memória. Segredos nunca vão
para URL, log, manifesto ou JSON. A UI de cadastro da chave entra
junto da primeira fonte com auth (5C-real).

## Capacidades opcionais (implementadas, dirigidas pela fonte)

Miniatura (`thumbnailUrl`) e qualidades (`qualities`) só existem no
item quando a fonte informa. O cartão mostra pôster remoto com
placeholder de fallback (miniatura local ganha); o painel lista as
qualidades em "Da fonte" acima das faixas do motor, com "Padrão da
fonte" voltando à URL original. Sem elas: placeholder e URL padrão,
comportamento anterior intacto. A troca reabre preservando posição
e id (histórico único).

## Checklist da fonte real (quando os dados chegarem)

URL/endpoint, formato da resposta, exemplo JSON, autenticação,
cabeçalhos, paginação, tipos de conteúdo, confirmação de autorização.
Integração = novo adaptador + testes, sem quebrar a suíte.
