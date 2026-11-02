# Pacote zip só com dados

Status: accepted.

O formato do pacote precisava ser definido antes de instalar zip
(`docs/Especificação do Player de Mídia.md`). Esta nota registra o
formato e as regras de validação; o código que as aplica é
`lib/services/addon_package.dart`.

## Decisões assentadas

- Conteúdo do pacote só dados: `addon.json` (obrigatório, mesmo
  manifesto e validação de hoje), `catalog.json` (opcional, envelope
  `{"items": [...]}` com a mesma validação do feed), `icon.png`
  (opcional, PNG ou JPEG até 1 MB) e `fanart.jpg` (opcional, PNG ou
  JPEG até 5 MB). Lista fechada: qualquer outro nome recusa o pacote.
- Arquivos na raiz; aceita também uma única pasta raiz contendo tudo
  (como muitos compactadores geram o zip).
- O pacote precisa ter `catalog.json` ou `catalogUrl` no manifesto:
  sem isso, um pacote mostraria o catálogo de demonstração como se
  fosse dele.
- Limites: 10 MB compactado, 30 MB descompactado (contado durante a
  extração, sem guardar os bytes e sem confiar no tamanho declarado) e
  16 entradas.
  `addon.json` e `catalog.json` seguem os limites atuais de 256 KB e
  500 itens.
- Recusa caminho absoluto, `..`, barra invertida, link simbólico,
  entrada criptografada e zip dentro de zip, tudo falhando fechado.
- Ícone e fanart têm a assinatura de bytes conferida, sem confiar na
  extensão.
- A descompactação roda fora da thread da interface.
- Add-on do Kodi (`addon.xml` na raiz) é recusado com mensagem própria,
  sem ler nem executar nada dele: o Olympus não executa código de
  terceiros.
- Armazenamento em `<suporte do app>/addons/<id>/<versão>/`, gravado
  em pasta temporária e renomeado no fim. O add-on só é registrado
  depois que os arquivos estão no lugar; falha limpa a temporária.
- O registro ganha origem (`manifest`, `file`, `link` ou
  `repository`), `packageSha256` e `packageDir`. Documentos antigos
  carregam sem perda.
- Catálogo de pacote vem do `catalog.json` guardado; com `catalogUrl`,
  o remoto tem prioridade e o guardado vira reserva em falha de rede.

## Considered Options

- Assinatura de pacotes (U25): fora deste ciclo; checksum cobre a
  integridade contra a listagem publicada.
- Ler `addons.xml` e `repository.*.zip` do Kodi: rejeitado; só o
  `addon.xml` é reconhecido, para a mensagem de incompatibilidade.

## Consequences

- Instalar de zip e de repositório (com `packageUrl` + `sha256`)
  compartilham o mesmo módulo de leitura e o mesmo armazenamento.
- Atualização e rollback de pacote (T5) reutilizam as pastas por
  versão guardadas aqui.
