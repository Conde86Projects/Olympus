# Olympus

> Player de mídia minimalista, bonito e eficiente, inspirado na simplicidade do Showtime e na flexibilidade dos players com extensões.

**Versão atual:** `0.2.0`  
**Codinome do projeto:** `Olympus`  
**Tecnologia principal:** Flutter / Dart  
**Interface inicial:** Português do Brasil  
**Status:** marco 0.2.0 validado em Windows, TV (TCL) e celular físico

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
Testes automatizados                     verdes (ver checklist 0.2.0)
flutter analyze                          limpo
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
- controle de volume dentro do app no desktop (trilho independente, lembrado entre aberturas); no celular e na TV, só o mudo (ver "Volume" abaixo);
- seleção de áudio;
- seleção de legendas;
- velocidade de reprodução;
- repetição;
- tela cheia;
- modo cinema;
- modo compacto;
- modo sempre no topo no desktop, quando suportado;
- retomada da última posição.

### Volume

Decisão de produto (20/10/2026): volume simples no celular e na TV,
completo só no desktop. Sem barra, sem botões de + e − e sem gesto
vertical nessas plataformas.

- Celular: o volume sai nos botões físicos do aparelho (volume do
  sistema). O app mostra só o botão de mudo.
- TV: o volume sai nos botões físicos VOL+/VOL− do controle remoto
  (volume da TV, fora do app). O app mostra só o botão de mudo. O
  D-pad não altera o volume: fica reservado para navegação, foco e
  progresso.
- Desktop (Windows): trilho de volume dentro do app, independente do
  volume do sistema, com mudo e persistência, como no YouTube.
- Só o ajuste do trilho no desktop é salvo como o volume inicial
  (`initialVolume`) e restaurado na próxima abertura. No celular e na
  TV, o app respeita o volume do sistema/aparelho: não aplica nem
  salva volume interno.
- Mudo preserva o volume anterior; desmutar restaura o mesmo nível.
  O mudo é o único controle de áudio dentro do app no celular e na TV.
- Passo do trilho no desktop: 0,05, entre 0,0 e 1,0.

### Biblioteca

- continuar assistindo;
- histórico;
- favoritos;
- itens locais;
- progresso de reprodução;
- miniaturas locais;
- pôster remoto quando disponível;
- placeholder quando a imagem não existe ou falha.

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
- adaptadores independentes por fonte.

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
│   ├── source_credential_store.dart
│   └── sources/
│       ├── source_adapter.dart
│       └── demo_source_adapter.dart
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

A suíte atual possui **394 testes aprovados**.

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

## Release Candidate 1

A versão atual é:

```text
Versão: 0.1.0-rc.1+1
Codinome: Olympus
Tag planejada: v0.1.0-rc.1
```

A RC1 deve ser congelada como baseline quando o build Windows estiver disponível. Depois disso, alterações devem preservar os gates:

```text
flutter analyze → limpo
flutter test    → todos os testes aprovados
```

Sugestão de versionamento:

```bash
git add .
git commit -m "chore: congelar release candidate 1"
git tag -a v0.1.0-rc.1 -m "Olympus v0.1.0-rc.1"
```

Configure a identidade Git antes do commit:

```bash
git config user.name "Seu Nome"
git config user.email "seu-email@example.com"
```

Não coloque tokens, senhas ou chaves no repositório.

---

## Roadmap

### Fase atual — RC1

- [x] Interface principal;
- [x] player e controles;
- [x] histórico, favoritos e retomada;
- [x] feed remoto e catálogo;
- [x] fontes desconhecidas por feed;
- [x] validação e aprovação de fonte;
- [x] proteção SSRF;
- [x] adaptadores de fonte;
- [x] miniaturas, pôsteres e placeholders;
- [x] qualidades dinâmicas;
- [x] refinamento de UX;
- [ ] build e teste visual no Windows;
- [ ] validação em hardware de TV.

### Próxima etapa

1. concluir o ambiente Windows;
2. abrir o app e fazer teste visual real;
3. validar janela normal, tela cheia e modo compacto;
4. testar monitor ultrawide;
5. validar arquivo local, seek, áudio e legenda;
6. validar fonte demo e fonte desconhecida;
7. corrigir somente problemas observados;
8. validar Android TV ou TV Box.

### Futuro

- estilo visual de legendas;
- miniaturas mais avançadas;
- qualidade dinâmica em fontes reais;
- modo seguro;
- diagnóstico e exportação de logs sem credenciais;
- atualizações controladas de add-ons;
- fontes autorizadas reais;
- catálogo e autenticação quando necessários;
- validação física em Smart TV;
- assinatura de pacotes;
- suporte adicional a plataformas de TV.

---

## Política de fontes reais

Uma fonte real só deve ser integrada quando existirem:

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
