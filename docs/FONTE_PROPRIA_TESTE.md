# Fonte própria de teste (Fase 2)

Feed JSON sob controle do dono do app. Nenhum terceiro, nenhuma
extração, nenhum contorno: o adaptador
(`lib/services/sources/owned_test_source.dart`) lê este formato e
só este formato.

## Schema (contrato)

```text
GET {base}.json?page=N&q=texto
{
  "feed": "player-teste/1",
  "catalog": [
    {
      "id": "t1",                    obrigatório, não vazio
      "title": "Tears of Steel",      obrigatório, não vazio
      "stream": "https://...m3u8",   obrigatório, http/https
      "subtitle": "texto",            opcional
      "poster": "https://...jpg",    opcional, http/https
      "duration": 734,               opcional, segundos >= 0
      "streams": [                   opcional, qualidades explícitas
        {"quality": "rótulo", "url": "https://..."}
      ]
    }
  ],
  "page": 1,   opcional (padrão 1)
  "pages": 3   opcional (padrão 1; page < pages = há mais)
}
```

Regras: envelope fora do formato rejeita com motivo legível;
entradas inválidas são puladas (nunca viram item parcial);
máximo 500 itens por página; `page`/`pages` ausentes = página
única; `q` vazio = sem busca (o app filtra local); tudo que o
feed envia é **dado**, nunca lógica.

## Exemplo hospedável

```json
{
  "feed": "player-teste/1",
  "catalog": [
    {
      "id": "tos",
      "title": "Tears of Steel",
      "subtitle": "Blender Foundation (CC-BY 3.0)",
      "stream": "https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.m3u8",
      "poster": "https://picsum.photos/seed/tos/640/360",
      "duration": 734,
      "streams": [
        {"quality": "HLS adaptativo", "url": "https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.m3u8"}
      ]
    },
    {
      "id": "sintel",
      "title": "Sintel",
      "subtitle": "Blender Foundation (CC-BY 3.0)",
      "stream": "https://bitdash-a.akamaihd.net/content/sintel/hls/playlist.m3u8",
      "poster": "https://picsum.photos/seed/sintel/640/360",
      "duration": 888
    },
    {
      "id": "bbb",
      "title": "Big Buck Bunny",
      "subtitle": "Blender Foundation (CC-BY 3.0)",
      "stream": "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
      "poster": "https://picsum.photos/seed/bbb/640/360",
      "duration": 596,
      "streams": [
        {"quality": "MP4 direto", "url": "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"}
      ]
    },
    {
      "id": "mux-smoke",
      "title": "Smoke test HLS (temporário)",
      "subtitle": "Demonstração oficial da Mux — substituir por mídia própria",
      "stream": "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8",
      "streams": [
        {"quality": "HLS adaptativo", "url": "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"}
      ]
    }
  ],
  "page": 1,
  "pages": 1
}
```

O exemplo exercita o que a Fase 2 precisa validar: catálogo,
miniaturas, durações, qualidades explícitas, HLS multivariante
(comutação e retomada pelo motor, sem mudar nada nele) e MP4
progressivo.

## Item de smoke test (temporário)

O item `mux-smoke` usa o stream oficial de demonstração da Mux
apenas como **dado** dentro do feed próprio: nenhuma integração
com o Mux, nenhum provider terceiro no app e nenhuma alteração
no adaptador (ele valida qualquer URL http/https, sem reconhecer
hosts de mídia). Serve para validar abertura HLS, variantes,
qualidade automática/manual, retomada, seek, rede fria e
histórico no Windows e na TCL. Depois do smoke test, substituir
por mídia hospedada ou autorizada pelo dono da fonte.

## Licenças dos vídeos

- `Tears of Steel`, `Sintel`, `Big Buck Bunny`: Blender
  Foundation, CC-BY 3.0 (atribuição no `subtitle`).
- `x36xhzz.m3u8`: ativo de teste público da Mux, uso para teste.
- `gtv-videos-bucket`: amostras públicas do Google para teste.
- `picsum.photos`: miniaturas de placeholder.

Nenhum item é de provedor terceiro não autorizado; a lista
acima é o catálogo fechado da fonte de teste.

## Formato publicado v1 (smoke)

O feed publicado usa o envelope `{"items": [...], "page", "pages"}`
com o item `{"id","title","url","description"?,"thumbnail"?,
"duration"?,"qualities"?}`. O adaptador aceita os dois envelopes
(documentado e publicado) com a mesma validacao estrita — a
conversao e so renomeacao de chaves, sem logica nova. Qualidades
publicadas seguem `[{"quality","url"}]`; outro formato e pulado
como item invalido, nunca meio item.

## Ativacao de smoke (removida na 0.2.1)

O host temporario do Manus (`*.us4.manus.computer`) deixou de ser
reconhecido pelo app na 0.2.1. O feed de smoke agora e so
`https://conde86projects.github.io/olympus-catalog/feed-smoke.json`,
casado pelo mesmo prefixo do feed definitivo. `test-streams.mux.dev`
continua sendo so um dado (URL de midia) dentro dele.

## Hospedagem (quando quiser validar no aparelho)

1. Publique o JSON em um endereço público `https` sob seu
   controle (hospedagem estática basta).
2. Suporte a `?page=` e `?q=` no servidor, ou deixe o app
   fatiar/filtrar local (o adaptador já tolera ausência).
3. Autenticação é opcional: com segredo guardado no cofre sob o
   id `owned.test`, o app envia `Authorization: Bearer ...`
   restrito à origem; sem segredo, o feed é público.

## Para ativar no app (2 linhas, só com a URL definitiva)

1. Trocar `OwnedTestSourceAdapter.testHost` pelo host real.
2. Registrar o adaptador na construção do serviço em
   `lib/main.dart`: `adapters: const [OwnedTestSourceAdapter()]`.

Sem isso, o adaptador é inerte: só atua nas URLs que casa.
Nada de player, histórico, retomada, TV, Windows, fontes
locais, catálogo demo, modo seguro ou diagnóstico muda.

## Feed definitivo (mídia autorizada)

Primeiro conteúdo: **Big Buck Bunny** (Blender Foundation,
CC-BY 3.0), depois **Sintel** (~15 min) e **Tears of Steel**
(~12 min). Baixar da fonte oficial, hospedar sob controle
próprio com miniatura própria — sem links antigos de terceiros.

Dois feeds separados, sem misturar:

- `feed.json` — catálogo autorizado definitivo (sem mux-smoke).
- `feed-smoke.json` — só testes técnicos (HLS, variantes,
  qualidade). Nunca é o catálogo público.

Exemplo de `feed.json`:

```json
{
  "page": 1,
  "pages": 1,
  "items": [
    {
      "id": "big-buck-bunny",
      "title": "Big Buck Bunny",
      "description": "Open Movie da Blender Foundation (CC-BY 3.0).",
      "url": "https://seu-dominio/media/big-buck-bunny.mp4",
      "thumbnail": "https://seu-dominio/images/big-buck-bunny.jpg",
      "duration": 596,
      "qualities": []
    },
    {
      "id": "sintel",
      "title": "Sintel",
      "description": "Open Movie da Blender Foundation (CC-BY 3.0).",
      "url": "https://seu-dominio/media/sintel.mp4",
      "thumbnail": "https://seu-dominio/images/sintel.jpg",
      "duration": 888,
      "qualities": []
    }
  ]
}
```

Modelo de `ATTRIBUTIONS.md` (publicar junto):

```text
# Atribuições — fonte própria Olympus

- Big Buck Bunny © Blender Foundation, licenciado em CC-BY 3.0
  (https://creativecommons.org/licenses/by/3.0).
  Site oficial: https://www.bigbuckbunny.org.
  Mídia e miniatura hospedadas sob controle próprio.
- Sintel © Blender Foundation, CC-BY 3.0.
  Site oficial: https://www.sintel.org.
- Tears of Steel © Blender Foundation, CC-BY 3.0.
  Site oficial: https://www.tearsofsteel.org.
```

Validação do feed definitivo (Windows e TCL): catálogo com
múltiplos itens, miniaturas, MP4, duração, seek, retomada,
progresso, conclusão em 97%, "Ver de novo", histórico e erro
de mídia — com o mux-smoke fora do feed público.

## Feed definitivo publicado (Fase 0.3, 19/10/2026)

Retomado o passo adiado em 18/10, só com Big Buck Bunny (Sintel e
Tears of Steel continuam fora por tamanho).

- Repositório: `Conde86Projects/olympus-catalog` (GitHub Pages).
- Catálogo: `https://conde86projects.github.io/olympus-catalog/feed.json`
  (só Big Buck Bunny, sem mux-smoke).
- Testes HLS: `https://conde86projects.github.io/olympus-catalog/feed-smoke.json`
  (só o mux-smoke, separado do catálogo).
- Mídia: `media/big-buck-bunny.mp4`, recodificado do original
  oficial `big_buck_bunny_720p_h264.mov` (download.blender.org):
  H.264 High 720p ~1 Mbps, keyframe a cada 2 s, AAC estéreo
  128 kbps, `faststart`, 84,5 MB, 596 s. SHA-256
  `f6dc1fc81c59f7a8babe6d9966ae2a89853cc116dc5460514d7be435d953164d`.
  MP4 único = sem seletor de qualidade (correto para ele).
  Decisão de 24/10/2026: ao gerar versões do BBB, preferir HLS
  com variantes (seletor Automática/variantes em toda parte, sem
  código novo) em vez de vários MP4s.
- Miniatura: `images/big-buck-bunny.jpg`, quadro em 1:35, 640x360.
- Créditos: `ATTRIBUTIONS.md` no próprio repositório do catálogo.
- App: `OwnedTestSourceAdapter.feedHost` + `feedPathPrefix` casam
  só `https://conde86projects.github.io/olympus-catalog/...`; outros
  repositórios do mesmo usuário não viram fonte própria. O host de
  smoke antigo (`smokeHost`) fica até a validação no Pages.
