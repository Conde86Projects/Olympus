# Olympus

> Player de mídia minimalista, bonito e eficiente, inspirado na simplicidade do Showtime e na flexibilidade dos players com extensões.

**Versão publicada:** `0.3.5` (ver `pubspec.yaml`; última tag e release: `v0.3.5`, 01/11/2026). O ciclo de acabamento da spec #16 está na branch `integracao/acabamento-16`, no PR #29, não publicado.  
**Codinome do projeto:** `Olympus`  
**Tecnologia principal:** Flutter / Dart  
**Interface inicial:** Português do Brasil  
**Status:** versão 0.3.5 publicada; marco 0.2.0 validado em Windows, TV (TCL) e celular físico. Estado detalhado em `docs/SITUACAO_ATUAL.md`.

---

## Sobre o projeto

Olympus é um player de mídia multiplataforma criado para oferecer uma experiência mais simples, organizada e agradável do que soluções tradicionais de media center.

O objetivo é preservar a flexibilidade de reprodução, biblioteca e extensões, mas reduzir a complexidade de menus, configurações e instalação de fontes.

O projeto prioriza:

- interface minimalista;
- inicialização rápida;
- reprodução estável;
- funcionamento em computadores e Smart TVs;
- suporte a arquivos locais e fontes compatíveis;
- add-ons organizados;
- recuperação segura contra falhas;
- navegação por mouse, teclado e controle remoto;
- arquitetura extensível sem executar código remoto arbitrário.

> **Princípio do produto:** ter a flexibilidade de um media center completo com a simplicidade de um player moderno.

---

## Estado atual

Versões publicadas depois do marco 0.2.0: 0.3.0 (volume por plataforma,
seletor de qualidade HLS, legendas com estilo), 0.3.1 (nome Olympus e
pacote `com.conde86.olympus`), 0.3.2 (legenda externa pelo painel), 0.3.3
(legenda ao lado), 0.3.4 (busca e ordem na Biblioteca) e 0.3.5 (miniatura
de vídeo local no Windows). Detalhes no `CHANGELOG.md`.

Ciclo de acabamento da spec #16 (na branch, PR #29, não publicado):
tamanho do texto, data do último acesso nos cartões, erros com
informações técnicas e escolha de outra fonte, erro de permissão
separado de arquivo ausente, fim do vídeo com Biblioteca e Início, menu
principal escolhido pelo usuário, atalhos configuráveis, foco do painel
de opções na TV, celular que retoma o play depois de um seletor,
legendas homônimas e aviso de legenda ao lado no celular. Decisões em
`docs/adr/0003-acabamento-spec-16.md`.

Spec #30 (na branch `integracao/addons-zip`, não publicada): instalar add-on por zip e
por repositório, botão de fontes desconhecidas, tela Add-ons com as entradas à vista e
tela principal em fileiras no computador, na TV e no celular. Estado em
`docs/RELEASE_v0.4.0_CHECKLIST.md`.

Marco 0.2.0 (19/10/2026): composição mobile, janela pequena no
Windows, catálogo da fonte própria, saída direta do vídeo no
Android/TV, menus compactos da TV e padrão visual único. Detalhes em
`docs/RELEASE_v0.2.0_CHECKLIST.md`; visual em
`docs/PADROES_VISUAIS.md`.

```text
Scaffold Flutter                         concluído
Interface principal                      concluída
Player e controles                       concluídos
Feed remoto e catálogo                   concluídos
Adicionar e gerenciar fontes             concluído
Proteção SSRF e limites                  concluída
Adaptadores de fontes                    concluídos
Fonte demo                               concluída
Credenciais seguras                      preparadas
Miniaturas e pôsteres                    concluídos
Qualidades dinâmicas                     concluídas
Refinamento de UX                        concluído
Composição mobile (celular)              concluída
Saída direta de vídeo (Android/TV)       concluída
Padrão visual único (TV/desktop/celular) concluído
Testes automatizados                     verdes (942 na execução do ciclo #16)
flutter analyze                          limpo
Estilo das legendas (0.3.0)              concluído
Legenda externa e ao lado (0.3.2/0.3.3)  concluídas
Busca e ordem da Biblioteca (0.3.4)      concluídas
Miniatura no Windows (0.3.5)             concluída
Provider real                            não conectado
Validação Windows                        concluída (0.2.0)
Validação em TV física (TCL)             concluída (0.2.0)
Validação em celular físico              concluída (0.2.0)
```

O adaptador demo é usado para validar o fluxo de fontes sem depender de um serviço externo. Nenhum provider real deve ser inventado ou conectado sem URL, formato, autorização e testes específicos.

---

## Funcionalidades

### Player

- abrir arquivos locais;
- abrir links HTTP/HTTPS compatíveis;
- reproduzir e pausar;
- avançar e retroceder;
- seek na timeline;
- só o botão de mudo dentro do app, em todas as plataformas; volume no sistema/aparelho (ver "Volume" abaixo);
- seleção de áudio;
- seleção de legendas;
- velocidade de reprodução;
- repetição;
- tela cheia;
- modo cinema;
- modo compacto;
- modo sempre no topo no desktop, quando suportado;
- retomada da última posição;
- legenda externa (`.srt`, `.vtt`, `.ass`) pelo painel e legenda ao lado de mesmo nome (celular: depende do acesso do Android à pasta);
- atalhos de teclado configuráveis (Mudo, Tela cheia, Informações, Legendas, Áudio, Modo cinema e Fechar player); espaço, Enter, Esc, setas e Tab ficam fixos, e F11 sempre entra e sai da tela cheia;
- erro de reprodução com informações técnicas e escolha de outro vídeo; fim do vídeo com saídas para Biblioteca e Início.

### Volume

Fonte única da regra: `docs/adr/0001-volume-por-plataforma.md`. Resumo:

Decisão de produto (20/10/2026, ajuste 21/10/2026): só o mudo
dentro do app, em todas as plataformas. Sem barra, sem botões de
+ e − e sem gesto vertical em nenhuma delas. O trilho saiu até do
Windows: ele empurrava os botões de pausar/play/voltar.

- Celular: o volume sai nos botões físicos do aparelho (volume do
  sistema). O app mostra só o botão de mudo.
- TV: o volume sai nos botões físicos VOL+/VOL− do controle remoto
  (volume da TV, fora do app). O app mostra só o botão de mudo. O
  D-pad não altera o volume: fica reservado para navegação, foco e
  progresso.
- Desktop (Windows): o volume sai no sistema; o app mostra só o
  botão de mudo. O volume interno (`initialVolume`) segue aplicado
  na abertura e ajustável nas setas com controles ocultos (passo
  0,05, entre 0,0 e 1,0), salvo como inicial — ajuste fino sem
  ocupar a fileira.
- No celular e na TV, o app respeita o volume do sistema/aparelho:
  não aplica nem salva volume interno.
- Mudo preserva o volume anterior; desmutar restaura o mesmo nível.
- Tecla física de volume (VOL+/VOL−, botões do celular) com o app
  mudado despluga o mudo em qualquer estado da barra — e o sistema
  ajusta o próprio volume normalmente, pois o app nunca consome a
  tecla.
- Sistema zerado/mudo no Android reflete no ícone do app (mostra
  mudo sem tocar no volume interno); aumentar no aparelho despluga
  o mudo do app.

### Biblioteca

- continuar assistindo;
- histórico;
- favoritos;
- itens locais;
- progresso de reprodução;
- miniaturas locais;
- pôster remoto quando disponível;
- placeholder quando a imagem não existe ou falha;
- busca pelo título e ordem por recentes, título ou duração (0.3.4);
- data do último acesso no cartão: "Visto hoje", "Visto ontem" ou dia e mês (ciclo #16, não publicado);
- miniatura de vídeo local no Windows, tirada pelo próprio motor do app (0.3.5).

### Personalização (ciclo #16, não publicado)

- Tamanho do texto: Normal, Grande e Maior (1,0, 1,15 e 1,3 vezes o texto do sistema), em Configurações > Aparência. A legenda desenhada pelo app tem ajuste próprio.
- Menu principal: Biblioteca, Favoritos, Add-ons e Histórico podem ser escondidos; Início e Configurações nunca saem. Esconder não desliga add-ons instalados.

### Fontes e add-ons

- feed remoto em formato compatível;
- catálogo embutido como fallback;
- fontes adicionadas pelo usuário;
- fonte desconhecida marcada como não verificada;
- aprovação explícita;
- ativar e desativar;
- editar endereço;
- atualizar catálogo;
- remover fonte sem apagar mídia local;
- paginação e busca quando suportadas;
- itens inválidos ignorados individualmente;
- isolamento de falhas por fonte;
- miniaturas e qualidades opcionais;
- adaptadores independentes por fonte;
- botão "Permitir fontes desconhecidas", desligado por padrão (spec #30, não publicada);
- instalar por zip, do aparelho ou por link, e por repositório com checksum conferido (spec #30, não publicada);
- fileira por add-on ativo na tela principal, com falha isolada (spec #30, não publicada).

### Segurança

- somente HTTP/HTTPS na camada de fontes;
- bloqueio de loopback e redes privadas;
- bloqueio de endereços link-local, multicast, ULA e IPv4 mapeado;
- validação de todos os resultados DNS;
- redirects manuais com revalidação por salto;
- limite de redirects;
- timeout configurável;
- limite de 256 KB por resposta;
- máximo de 500 itens por feed;
- credenciais fora do código;
- headers de autenticação limitados à própria origem;
- nenhum código executável vindo de feed ou fonte desconhecida.

> **Regra de segurança:** dados podem ser consumidos dentro do contrato; código remoto não pode ser executado automaticamente.

---

## Arquitetura

```text
lib/
├── app/
│   ├── app.dart
│   ├── router.dart
│   └── theme.dart
├── core/
│   ├── constants/
│   ├── errors/
│   ├── storage/
│   └── utils/
├── models/
├── services/
│   ├── media_player_service.dart
│   ├── addon_service.dart
│   ├── addon_fetcher.dart
│   └── sources/
│       ├── source_adapter.dart
│       ├── source_credentials.dart
│       ├── demo_source_adapter.dart
│       └── owned_test_source.dart
├── features/
│   ├── home/
│   ├── player/
│   ├── library/
│   ├── favorites/
│   ├── history/
│   ├── settings/
│   └── sources/
└── widgets/
```

A interface não deve depender diretamente de uma fonte ou de uma biblioteca específica de reprodução. Fontes reais devem entrar por adaptadores independentes.

### Contrato de adaptador

Um adaptador de fonte pode implementar:

```text
canHandle(url)
headersFor(url)
parseCatalog(response)
manifestFor(url)
pageUrl(url, page)
searchUrl(url, query)
```

O adaptador deve converter o conteúdo externo para os modelos internos do Olympus. Ele não deve alterar o contrato principal do aplicativo nem acessar código não declarado.

### Fluxo de uma fonte

```text
URL da fonte
→ validação HTTP/HTTPS
→ validação DNS e SSRF
→ conexão segura
→ redirects revalidados
→ adaptador correspondente
→ parse e validação
→ catálogo
→ biblioteca/player
```

---

## Fontes desconhecidas

O Olympus permite fontes adicionadas pelo usuário, mas não trata todas as fontes como confiáveis automaticamente.

Estados possíveis:

```text
Desconhecida
→ endereço ainda não cadastrado ou verificado

Aprovada pelo usuário
→ usuário confirmou explicitamente a origem

Verificada
→ fonte distribuída por repositório ou assinatura reconhecida
```

O fluxo de cadastro é:

```text
Adicionar fonte
→ informar URL
→ validar endereço
→ carregar manifesto/feed
→ mostrar origem e aviso
→ usuário aprovar
→ salvar desativada
→ usuário ativar quando desejar
```

Antes desse fluxo vale o botão "Permitir fontes desconhecidas", em Configurações, desligado por padrão. Desligado, ele bloqueia instalar por arquivo, texto, link ou zip, usar repositório não confiável, cadastrar repositório e trocar uma fonte para outro host. O que já está instalado segue funcionando, e repositório já marcado como confiável continua instalando.

O zip passa pelas mesmas etapas: entra revisão, aprovação e instalação desativada. O pacote traz só dados, conforme `docs/adr/0004-pacote-zip-so-dados.md`. Zip com código é recusado, inclusive add-on do Kodi em Python, que o Olympus não executa.

Fontes desconhecidas podem fornecer dados compatíveis, mas não podem executar código arbitrário. Pacotes executáveis exigirão uma política própria de permissões, assinatura, checksum, sandbox e isolamento antes de serem suportados.

---

## Requisitos

### Ambiente geral

- Flutter SDK `3.47.7` ou compatível;
- Dart `3.13.5` ou compatível;
- Git;
- Windows Build Tools 2022 para build Windows;
- componente ATL do C++ para as ferramentas v143 no Windows;
- SDK da plataforma desejada.

### Verificar Flutter

```bash
flutter --version
flutter doctor -v
```

---

## Instalação e execução

Clone o repositório e entre na pasta do projeto:

```bash
git clone <URL_DO_REPOSITORIO>
cd <PASTA_DO_PROJETO>
```

Instale as dependências:

```bash
flutter pub get
```

Execute as verificações:

```bash
flutter analyze
flutter test
```

Execute em um dispositivo disponível:

```bash
flutter devices
flutter run -d windows
```

Para gerar as plataformas, se necessário:

```bash
flutter create --platforms=windows,linux,android .
```

Não execute esse comando sobre um projeto com alterações locais sem revisar o diff, pois ele pode gerar arquivos de plataforma adicionais.

---

## Windows

O build Windows depende dos componentes oficiais do Visual Studio Build Tools 2022.

No Visual Studio Installer, em **Build Tools 2022 → Modificar → Componentes individuais**, verifique:

- ferramentas de CMake do C++ para Windows;
- Windows 10 ou Windows 11 SDK;
- MSVC v143;
- **C++ ATL for latest v143 build tools**.

Comandos de validação:

```powershell
flutter clean
flutter pub get
flutter analyze
flutter test
flutter build windows
flutter run -d windows
```

Se ocorrer erro relacionado a `atlstr.h`, o componente ATL do MSVC não está instalado. Esse erro pertence ao ambiente de build, não ao código do aplicativo.

---

## Testes

A suíte atual possui **942 testes aprovados** (`flutter test` em `integracao/acabamento-16`, 01/11/2026; registrar o número real antes de cada release). `flutter analyze` sem avisos.

Execute:

```bash
flutter test
```

Execute uma área específica:

```bash
flutter test test/addon_catalog_source_test.dart
flutter test test/addon_source_manage_test.dart
flutter test test/source_quality_live_test.dart
flutter test test/source_poster_quality_test.dart
```

Antes de qualquer commit:

```bash
flutter analyze
flutter test
```

Toda nova fonte, alteração de player ou alteração de fluxo de instalação deve incluir testes para sucesso, erro, cancelamento e recuperação.

---

## Versões e releases

```text
Versão publicada: 0.3.5+1011
Tag e release:    v0.3.5 (01/11/2026)
Pacote Android:   com.conde86.olympus
Codinome:         Olympus
```

As tags e releases estão no GitHub (`gh release list`). Cada versão publicada
tem seu checklist em `docs/RELEASE_v*_CHECKLIST.md`, que não é editado depois
da publicação. Os gates de cada entrega:

```text
flutter analyze → limpo
flutter test    → todos os testes aprovados
```

Só o dono autoriza push, tag e release. Não coloque tokens, senhas ou chaves no repositório.

---

## Roadmap

### Concluído

- [x] Interface principal, player e controles, histórico, favoritos e retomada;
- [x] feed remoto, catálogo, fontes desconhecidas, validação, aprovação e proteção SSRF;
- [x] adaptadores de fonte, miniaturas, pôsteres, placeholders e qualidades dinâmicas;
- [x] refinamento de UX;
- [x] build e teste visual no Windows (checklist RC1, 31/10);
- [x] validação em hardware de TV (TCL, 31/10; ver `docs/SITUACAO_ATUAL.md`);
- [x] volume por plataforma, estilo das legendas, legenda externa e ao lado, busca e ordem da Biblioteca, miniatura no Windows (0.3.0 a 0.3.5);
- [x] modo seguro, diagnóstico com exportação sem credenciais e atualizações controladas de add-ons.

### No PR #29 (spec #16), não publicado

- [x] tamanho do texto, data do último acesso, erros com informações técnicas e escolha de outra fonte, permissão de arquivos separada, fim do vídeo com Biblioteca e Início, menu principal, atalhos configuráveis, foco do painel na TV, retomada do play no celular, legendas homônimas e aviso de legenda ao lado;
- [ ] conferir em aparelho o que a suíte não cobre (foco na TCL, seletor e permissão no emulador, atalhos e texto no Windows) e registrar no checklist da próxima versão.

### Na branch `integracao/addons-zip` (spec #30), não publicado

- [x] fontes desconhecidas, instalar por zip e por repositório, atualizar e voltar versão de pacote, tela Add-ons e tela principal em fileiras (T1 a T10);
- [ ] conferir o que falta em `docs/RELEASE_v0.4.0_CHECKLIST.md` (Windows com zip real e monitor de 34", add-on real na TV, celular físico).

### Próxima etapa

Ver `docs/PLANO_PROXIMAS_ATUALIZACOES.md` e `docs/BACKLOG.md`. Em aberto, sem
dependência de código novo: validar em Google TV, Fire TV ou Mi Box e em celular
físico adicional, medir 4K no PC e rede lenta no aparelho.

### Futuro

- miniaturas mais avançadas;
- qualidade dinâmica em fontes reais;
- fontes autorizadas reais;
- catálogo e autenticação quando necessários;
- validação física em Smart TV;
- assinatura de pacotes;
- suporte adicional a plataformas de TV.

Já feitos e antes listados aqui: estilo visual de legendas, modo seguro, diagnóstico e exportação de logs, atualizações controladas de add-ons.

---

## Política de fontes reais

O Olympus é um player descentralizado: reproduz o que o próprio usuário
informa (link, endereço de manifesto ou arquivo local). O app não
hospeda, não indexa e não recomenda catálogos de terceiros, e a
responsabilidade pelo conteúdo é do usuário. Fontes integradas pelo
projeto (adaptadores em `lib/services/sources/`) seguem os critérios
abaixo.

Uma fonte integrada pelo projeto só deve ser integrada quando existirem:

```text
URL ou endpoint
Formato da resposta
Exemplo JSON
Autenticação, se houver
Cabeçalhos necessários
Paginação, se houver
Tipos de conteúdo
Confirmação de autorização
```

A fonte será implementada como adaptador independente em:

```text
lib/services/sources/<nome>_source.dart
```

Não enviar chaves ou tokens em mensagens, commits ou arquivos públicos. Credenciais devem ser configuradas por mecanismo seguro e nunca gravadas diretamente no código.

Integrações com serviços de terceiros devem usar API, SDK ou método permitido pelo próprio serviço. O Olympus não deve contornar autenticação, proteção técnica ou restrições de distribuição.

---

## Codinomes das versões

O nome do projeto é **Olympus** e o codinome da primeira linha de desenvolvimento é inspirado na mitologia.

Sugestão de organização:

```text
0.x   Olympus        desenvolvimento e release candidates
1.0   Zeus           primeira versão estável pública
2.0   Athena         grande evolução de interface e biblioteca
3.0   Hermes         expansão de integrações e sincronização
4.0   Hephaestus     desempenho, reprodução e plataforma
5.0   Apollo         experiência multimídia e Smart TV
```

Os codinomes são apenas nomes de versão. Eles não alteram o contrato técnico, a licença ou os requisitos de segurança.

---

## Princípios de desenvolvimento

- Não quebrar funcionalidades estáveis sem necessidade.
- Não inventar endpoints ou providers.
- Não executar código remoto vindo de fontes.
- Não armazenar segredos no código.
- Não apagar arquivos do usuário durante a remoção de fontes.
- Não travar o aplicativo por falha de uma integração.
- Testar fluxos de erro e cancelamento.
- Manter fontes locais e catálogo demo funcionando sem rede.
- Preferir mudanças pequenas, isoladas e reversíveis.
- Documentar limitações honestamente.

---

## Licença

A licença ainda deve ser definida pelo responsável pelo projeto antes da publicação pública.

---

## Contribuição

Antes de abrir uma alteração:

1. descreva o problema;
2. explique a solução;
3. mantenha a mudança isolada;
4. adicione ou atualize testes;
5. execute `flutter analyze`;
6. execute `flutter test`;
7. documente limitações e decisões importantes.

Uma alteração só deve ser considerada pronta quando o comportamento, os testes e a documentação estiverem alinhados.
