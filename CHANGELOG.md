# Changelog

Histórico de versões do player, escrito para humanos (o que mudou e
se importa). Detalhes de implementação ficam nos documentos em
`docs/`.

## [Não lançado]

Ciclo de acabamento da spec #16, no PR #29. Ainda não foi publicado. Na execução de
01/11/2026, a suíte passou com 942 testes e a análise estática ficou limpa. Conferido
na TCL: data do cartão, fim do vídeo com Biblioteca e Início, menu principal e foco do
painel de opções. Conferido no emulador: tamanho do texto, erro de permissão,
informações técnicas e aviso de legenda ao lado. Falta conferir no Windows: atalhos e
o restante.

### Adicionado

- Configurações: "Tamanho do texto" (Normal, Grande ou Maior) para todo o app. A
  legenda continua com o ajuste dela, em Legendas.
- Os cartões mostram "Visto hoje", "Visto ontem" ou a data da última vez que o vídeo
  foi visto. Vídeo que nunca tocou fica sem a linha.
- Erro ao tocar: "Ver informações técnicas" (sem caminho de pastas, endereço completo
  nem senha), "Escolher outro vídeo" para arquivo local e "Abrir arquivo local" quando
  o link falha por falta de conexão.
- Fim do vídeo: botões "Biblioteca" e "Início".
- Configurações: "Menu principal", para esconder Biblioteca, Favoritos, Add-ons ou
  Histórico. Início e Configurações nunca saem, e esconder não desliga os add-ons.
- Configurações: "Atalhos" para trocar a tecla de Mudo, Tela cheia, Informações,
  Legendas, Áudio, Modo cinema e Fechar player. O app recusa tecla já usada ou
  reservada (espaço, Enter, Esc, setas e Tab) e tem "Restaurar padrão".
- Celular: em vídeo local sem legenda ao lado encontrada, o painel de legendas avisa
  que ela pode ser aberta à mão por "Abrir arquivo de legenda…".

### Alterado

- Na TV, o painel de opções do player segura o foco: as setas no primeiro e no último
  item não saem dele.
- Duas legendas com o mesmo nome em pastas diferentes aparecem como `pasta/nome` na
  lista, e a marcada é exatamente a que está ligada.

### Corrigido

- Quando faltava acesso aos arquivos, o erro dizia que o arquivo sumiu ou que não havia
  conexão. Agora diz que falta acesso aos arquivos e como liberar.
- Celular: depois de escolher um arquivo no seletor do sistema (por exemplo, a legenda),
  o vídeo volta a tocar se estava tocando. Vídeo pausado continua pausado.

## [0.3.5] - 2026-11-01

### Adicionado

- Windows: miniatura nos cartões de vídeo local. O próprio app tira o quadro, sem
  precisar instalar nada, para mp4, mkv, webm, avi e 4K. Só áudio ou arquivo
  ilegível continuam com o ícone de play. Vídeos que já estavam na biblioteca
  ganham a miniatura na próxima vez que são abertos.

## [0.3.4] - 2026-11-01

### Adicionado

- Biblioteca: busca pelo título, sem diferenciar maiúsculas nem acentos, e ordem
  por recentes, título ou duração. A ordem escolhida fica lembrada.
- Na TV, o campo de busca só abre o teclado ao apertar OK, e as setas saem dele
  para a lista e para o seletor de ordem.

## [0.3.3] - 2026-10-31

### Adicionado

- Legenda ao lado: em vídeo local, a legenda de mesmo nome na mesma pasta entra na
  lista sozinha e só liga conforme "Ativar por padrão". No celular, isso depende de
  o Android dar acesso à pasta: escolhendo o vídeo pelo seletor do sistema, a
  legenda deve ser aberta pelo painel.

### Corrigido

- Celular: `.vtt` e `.ass` agora podem ser escolhidos no seletor do sistema.
- O painel de legendas mostra a faixa ligada de fato. Com "Ativar por padrão"
  ligado, ele dizia "Desativadas" com a legenda na tela.

## [0.3.2] - 2026-10-31

### Adicionado

- Legendas: abrir um arquivo `.srt`, `.vtt` ou `.ass` pelo painel do player, nas
  três plataformas. Arquivo inválido mostra um aviso, mantém a legenda que estava
  ativa e não interrompe o vídeo.
- Logo do Olympus na barra superior e nas boas-vindas.

### Alterado

- A tela Sobre não mostra mais "protótipo" ao lado da versão.

### Corrigido

- Depois de "Reproduzir novamente", o painel não some mais com as faixas de áudio
  e legenda do vídeo.

## [0.3.1] - 2026-10-31

### Alterado

- O app passa a se chamar Olympus e ganha logo própria no ícone do Android, no
  banner da TV e no ícone do Windows.
- Android: o pacote passa a ser `com.conde86.olympus`. O app instala separado do
  antigo `com.example.player` e começa sem biblioteca, histórico nem ajustes. O app
  antigo pode ser removido; remover apaga os dados dele. Windows mantém os dados.

### Corrigido

- Modo TV em tela estreita: os botões da barra não se sobrepõem mais.

## [0.3.0] - 2026-10-31

### Adicionado

- Celular e TV usam o volume do aparelho e mostram só o mudo; Windows tem volume
  interno lembrado. Volume do sistema em zero muta o app, e subir tira o mudo.
- Seletor de qualidade no Big Buck Bunny em HLS, nas três plataformas.
- Navegador de vídeos próprio na TV, para Procurar arquivo e Localizar.
- Legendas com tamanho, cor, posição e fundo em Ajustes, desenhadas acima da
  barra de controles.
- Seletor de qualidade aparece sozinho quando o master volta depois de uma rede
  fria.

### Corrigido

- TV: o foco agora aparece em Ajustes, no painel do player e nos menus, e os
  botões dos diálogos respondem ao controle.
- Retomada: o vídeo fica coberto até o ponto salvo, sem mostrar o início.
- Sem internet: erro de conexão com "Tentar novamente", em vez de tela preta ou
  "Ajustando a posição…" preso.
- Arranque no Android sem flash branco.
- Celular: "Iniciar em tela cheia" passa a valer.

### Limites conhecidos

- Fonte muito lenta pode cair no limite de 15 s de rede ou de 30 s do início.
- 4K testado só com clipe sintético de 30 s, no PC do dono e na TCL, sem medir
  quadros perdidos.
- Modo TV ligado à mão em tela de celular: a engrenagem encosta no botão +10.

## Itens de 0.1.x e 0.2.x sem seção própria

### Adicionado

- Item concluído (Fase 0.2.0, item 1): fração assistida >= 97%
  marca o histórico como concluído; concluídos saem do "Continuar
  assistindo" mas permanecem em biblioteca e histórico; reabrir
  começa em 0:00 com a ação "Ver de novo"; sair sem assistir
  preserva o concluído. Retomada de não concluídos intacta.
  Validado na TCL com suíte 548/548 e `dart analyze` limpo.

### Corrigido

- Preservação de posição na troca de qualidade HLS (TV): a
  reabertura em outra variante reutiliza o gate de prontidão da
  retomada (primeiro avanço real, fora de buffering), valida o
  pouso e tenta no máximo uma correção validada; se o pouso
  continuar incorreto, retorna de forma controlada à qualidade
  anterior, e se o retorno também falhar, pausa e protege o
  histórico sem salvar o ponto errado. Validado na TCL (troca
  para 720p, retorno à Automática, retomada fria e fallback
  master) com suíte 512/512 e `dart analyze` limpo. Prepara a
  próxima RC; a tag `v0.1.0-rc.2` permanece imutável.

## [0.1.0] - 2026-10-14

Versão final: player local completo, validado em hardware real
(TCL BeyondTV, Android 9). Inclui tudo das RCs (retomada HLS
precisa, seleção manual de qualidade, política automática,
detecção fria de variantes, seletor de idioma navegável por
D-pad, diagnóstico e modo seguro). Gates: suíte completa verde
e `dart analyze` limpo; APK da RC8 validado na TCL. Tag `v0.1.0`
ainda não criada.

## [0.1.0-rc.8] - 2026-10-14

Release candidate com detecção fria de variantes HLS +
navegação do seletor de idioma por D-pad, aprovados em hardware
real (TCL). Gates preservados: suíte completa verde e
`dart analyze` limpo. Tags anteriores intactas.

### Adicionado

- Detecção fria de variantes HLS: com a rede ainda fria, o player
  abre de imediato no master e faz no máximo uma sonda posterior
  limitada (3 s), que só aquece a lista do seletor de qualidade —
  sem trocar qualidade em silêncio, sem reabrir, sem novo seek e
  sem alterar histórico ou ID. Validado na TCL (rede fria com
  recuperação, rede pronta e rede permanentemente indisponível).
- Idioma preferido de legendas vira seletor navegável na TV:
  lista dedicada de 26 idiomas (+ Padrão do sistema), com
  navegação por setas, OK para confirmar e voltar para preservar.
  Remove os campos de texto do caminho do D-pad em Configurações.

### Corrigido

- D-pad preso no campo "Idioma preferido" em Configurações (TCL):
  com o IME fechado o foco ficava retido no campo de texto e as
  setas não saíam dele. Sem mexer em DropdownButton, fontes,
  reprodução, retomada HLS, seletor manual, política automática,
  modo seguro ou diagnóstico.

## [0.1.0-rc.2] - 2026-10-13

Segundo release candidate: qualidade dinâmica e retomada HLS na
TV, aprovadas em hardware real (TCL). Gates preservados: suíte
completa verde e `dart analyze` limpo.

### Adicionado

- Diagnóstico identifica o tipo do último erro (rede, fonte,
  decodificador, tempo esgotado, desconhecido) na tela e no
  relatório exportado — sem vazar mensagem, caminho, URL ou
  credencial.
- Versão do app no diagnóstico acompanha o pubspec.
- Interface adaptativa para TV (spec 27): composição própria do
  player (largura limitada, chips de áudio/legendas/qualidade com
  rótulo), tokens por classe de largura (720p/1080p/4K), margem
  segura anti-overscan e breakpoints validáveis em hardware real.
  Windows inalterado.
- Seleção manual de qualidade HLS na TV (Opções → Qualidade, por
  D-pad): Automática (padrão, com o teto da classe), Original e
  só as variantes reais do master; a troca preserva item,
  histórico e posição, e a falha de variante volta para a
  Automática sem texto técnico.
- Política automática por desempenho: perfil por
  plataforma/Leanback/viewport (TV compacta/normal com o teto que
  estabilizou a TCL; TV 4K e desktop sem teto) e, na TV em
  Automática, um degrau abaixo uma única vez se a reprodução
  ficar lenta no início. Override manual nunca é rebaixado e a
  qualidade efetiva aparece no painel.
- Retomada HLS precisa: o seek inicial aguarda prontidão real
  (saída de buffering + primeiro avanço de posição, com timeout
  limitado) e o pouso é validado — no máximo uma correção, sem
  loops. Pouso incorreto pausa com segurança e preserva o
  histórico do ponto errado, com o motivo no log técnico.

### Corrigido

- Retomada HLS na TCL caía segundos ou minutos longe do ponto
  salvo (seek em demuxer frio descartado em silêncio + correção
  cega): agora pousa exato no alvo em hardware real, sem mexer
  em MP4, playlists simples, histórico ou IDs.

## [0.1.0-rc.1] - 2026-10-12

Primeiro release candidate: player local completo, desktop, TV e
fontes por dados (sem provider real conectado).

### Adicionado

- Reprodução local (media_kit/libmpv): arquivo, link autorizado,
  pausa/retomada, busca, volume, velocidade, faixas de áudio e
  legendas, tela cheia e modo compacto.
- Card de controles flutuante fosco (Showtime): tempo/título/
  duração, progresso total e fileira de botões; tela cheia no
  canto superior esquerdo e ações+fechar à direita.
- Biblioteca, histórico e favoritos persistentes, com ponto de
  retomada exato e "parou em" nos cartões.
- Desktop Windows/Linux: janela redimensionável, ultrawide, modo
  escuro Adwaita minimalista, atalhos de teclado (I/S/A, C, ESC).
- TV/Android: Leanback com banner, navegação por D-pad, foco
  visível, botão voltar preservando a posição.
- Fontes por dados: catálogo embutido, feed remoto por URL,
  adaptador demo realista, pôster e qualidades dinâmicas quando a
  fonte informa.
- Gerência de fontes: adicionar por URL com prévia, aviso de fonte
  desconhecida, aprovação explícita, início desativado, ativar,
  editar (nova aprovação se a origem mudar), atualizar e remover.
- Diagnóstico e modo seguro: inicia sem fontes externas, exporta
  logs sem credenciais, identifica o último erro.

### Segurança

- Fontes desconhecidas: somente dados compatíveis, nenhum código
  executável ("dados sim, código nunca").
- HTTP/HTTPS apenas, timeout, 256 KB por resposta, 500 itens por
  feed, isolamento de falhas por fonte.
- Barreira SSRF: bloqueia localhost, loopback, redes privadas,
  link-local, multicast, ULA e IPv4 mapeado; revalida todos os
  endereços do DNS e cada redirect (máx. 3); autenticação só na
  origem.
- Credenciais em armazenamento seguro do SO
  (`flutter_secure_storage`), nunca no código ou nos logs.

### Corrigido

- Retomada a frio caindo no início (leitura de duração do motor com
  retentativas espaçadas).
- Slider capturando o OK no D-pad (ação dedicada de saída).
- Links sempre offline no Android (faltava permissão INTERNET).
- Amostra de teste com 403 trocada por HLS público estável.
- Rótulo "Qualidade" atualiza ao vivo no diálogo aberto.

### Limitações conhecidas

- Estilo visual das legendas (tamanho/cor/fundo/posição): o
  media_kit não expõe as propriedades do mpv pela API Dart.
- Pixel-perfeito em TV antiga (Mali-470 não renderiza
  Vulkan/GLES3); validação visual vale para TVs atuais.
- Nenhum provider real conectado: a primeira fonte autorizada
  entrará como adaptador isolado em `lib/services/sources/`.

Verificação: 396/396 testes passando, `flutter analyze` limpo.
