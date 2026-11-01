# Add-ons por zip e repositório, fontes desconhecidas e tela principal

Documento de trabalho para a IA que vai implementar. Escrito em 01/11/2026 sobre o commit `d601b34` da branch `integracao/acabamento-16`.

Leia a Parte 1 e siga os passos em ordem. As outras partes são o conteúdo que os passos usam.

- **Parte 1:** roteiro com as skills do Matt Pocock.
- **Parte 2:** spec, no modelo do `/to-spec`.
- **Parte 3:** tickets, no modelo do `/to-tickets`.
- **Parte 4:** teste no aparelho e correção.
- **Parte 5:** mapa do código neste commit.

---

## Parte 1. Roteiro

As skills abaixo só rodam quando o usuário digita o comando. Cada passo mostra o comando exato.

### Passo 1. Preparar

Leia `GLOSSARY.md`, `docs/adr/`, `docs/FONTES_ADAPTADOR.md`, `docs/PADROES_VISUAIS.md` e este documento inteiro.

Crie a branch `integracao/addons-zip` a partir da ponta de `integracao/acabamento-16`.

**Pronto quando:** a branch existe e `flutter analyze` e `flutter test` rodaram nela. Anote o resultado de base. Falha que já existia não é sua, mas precisa constar no relatório.

### Passo 2. Publicar a spec

```text
/to-spec Use a Parte 2 de docs/SPEC_ADDONS_ZIP_REPOSITORIO_TELA_PRINCIPAL.md como conteúdo. As costuras de teste já estão na seção "Testing Decisions".
```

Publique o texto da Parte 2 como veio, com a label `ready-for-agent`. Só altere o que estiver errado em relação ao código, e diga o que mudou.

**Pronto quando:** a issue existe e o número dela está no relatório.

### Passo 3. Publicar os tickets

```text
/to-tickets <número da issue da spec>. Use a Parte 3 de docs/SPEC_ADDONS_ZIP_REPOSITORIO_TELA_PRINCIPAL.md como quebra.
```

O usuário aprova a quebra quando a skill perguntar. Cada ticket vira sub-issue da spec, com os bloqueios nativos do GitHub.

**Pronto quando:** todos os tickets existem, com bloqueios, e a spec aberta aponta para eles.

### Passo 4. Implementar

Para um ticket por sessão, que é o recomendado aqui:

```text
/implement <número do ticket>
```

Para todos de uma vez, em agentes paralelos:

```text
/implement-spec <número da issue da spec>
```

Em cada ticket, use `/tdd` só nas costuras listadas na Parte 2. Rode `flutter analyze` e o arquivo de teste do ticket com frequência, e a suíte inteira uma vez no fim. Termine com `/code-review`.

**Pronto quando:** cada critério do ticket está marcado, a suíte está verde e a revisão não deixou achado aberto.

### Passo 5. Testar e corrigir

Siga a Parte 4 com o usuário. Todo defeito encontrado passa por `/diagnosing-bugs` antes da correção.

### Regras do projeto

- Faça commit na branch de trabalho. Push, tag, merge em `main` e release só com pedido explícito do usuário.
- Nenhum commit, PR ou nota de release cita o Claude ou qualquer IA como autor.
- Textos da interface em português do Brasil. Responda ao usuário em português simples.
- Layout validado da TV e do Windows, HLS, retomada, qualidade, histórico e volume ficam como estão. Mudança nova entra por caminho próprio, com teste que fixa o comportamento antigo.
- Sem baixar ou converter vídeo grande. Use `test_assets/` e os feeds de teste do projeto.

---

## Parte 2. Spec

### Problem Statement

Quem usa o Kodi instala add-ons por um caminho conhecido: liga "fontes desconhecidas", instala um zip e, a partir dele, navega por um repositório. No Olympus esse caminho não existe. Hoje a instalação aceita só um manifesto JSON, por arquivo, texto colado ou link, e o repositório lista só manifestos. A opção de instalar fica escondida em ícones no topo da tela.

Além disso, o Início é uma lista de "Continuar assistindo" limitada a 1080 de largura. Num monitor de 34 polegadas sobra tela vazia dos dois lados, e os vídeos locais e os catálogos dos add-ons ficam em outras telas.

### Solution

1. **Fontes desconhecidas:** um botão, desligado por padrão, controla a entrada de qualquer origem nova. Com ele desligado, o app explica o motivo e oferece o atalho para ligar.
2. **Instalar de zip:** o usuário escolhe um arquivo do aparelho ou informa um link, revisa e instala. O add-on entra desativado.
3. **Instalar de repositório:** o repositório passa a publicar pacotes zip com checksum, além dos manifestos atuais.
4. **Tela Add-ons:** as três entradas ficam visíveis (Meus add-ons, Instalar de repositório, Instalar de zip).
5. **Tela principal:** fileiras de pôsteres com Continuar assistindo, arquivos locais, favoritos e uma fileira por add-on ativo, usando toda a largura da janela no desktop.

**O pacote do Olympus contém só dados.** Um add-on do Kodi em Python continua sem funcionar, e o app diz isso com uma mensagem clara em vez de um erro genérico. Veja "Out of Scope".

### User Stories

**Fontes desconhecidas**

1. Como usuário, quero um botão "Permitir fontes desconhecidas" nas Configurações, para decidir se o app aceita origens novas.
2. Como usuário, quero esse botão desligado na primeira execução, para que nada entre sem eu escolher.
3. Como usuário, ao ligar o botão, quero um aviso com o risco e a escolha entre Cancelar e Ativar, para entender o que estou liberando.
4. Como usuário, ao desligar o botão, quero que os add-ons instalados continuem como estão, para não perder o que já aprovei.
5. Como usuário com o botão desligado, quero ver na tela de instalação o motivo do bloqueio e um atalho para ligar, para não precisar procurar em Configurações.
6. Como usuário com o botão desligado, quero continuar atualizando, ativando, desativando e removendo o que já está instalado, para que o botão só controle a entrada de origens novas.
7. Como usuário com o botão desligado, quero que trocar o endereço de uma fonte para outro host seja bloqueado, para que uma origem nova não entre por esse caminho.
8. Como usuário, quero continuar instalando de um repositório já marcado como confiável com o botão desligado, para ter um caminho seguro no dia a dia.
9. Como usuário de TV, quero operar o botão e o aviso com o controle remoto, com o foco inicial em Cancelar.

**Instalar de zip**

10. Como usuário, quero escolher um arquivo `.zip` do aparelho, para instalar um add-on sem digitar nada.
11. Como usuário, quero também digitar o caminho do arquivo, para ter saída em aparelhos sem seletor de arquivos.
12. Como usuário, quero informar um link direto para um zip, para instalar sem baixar antes.
13. Como usuário, quero ver o progresso e poder cancelar o download.
14. Como usuário, quero revisar nome, versão, autor, origem, permissões, plataformas, aviso legal e tamanho do catálogo antes de confirmar.
15. Como usuário, quero ver o SHA-256 do pacote na revisão, para poder conferir com quem o publicou.
16. Como usuário, quero que o add-on instalado entre desativado, para ativar só depois de revisar.
17. Como usuário, quero assistir ao catálogo que veio dentro do zip mesmo sem internet para buscar a lista.
18. Como usuário, quero uma mensagem clara quando o zip for de um add-on do Kodi com código, para saber que o problema é a incompatibilidade e não o arquivo estar corrompido.
19. Como usuário, quero uma mensagem clara para zip corrompido, grande demais, sem manifesto ou com arquivos não aceitos.
20. Como usuário, quero que uma instalação falha não deixe nada para trás nem mexa no que já está instalado.
21. Como usuário, ao remover um add-on, quero que os arquivos do pacote sejam apagados, sem tocar nas minhas mídias.

**Instalar de repositório**

22. Como usuário, quero navegar pelos add-ons de um repositório e abrir a mesma revisão antes de instalar.
23. Como usuário, quero ver na lista quais add-ons já estão instalados, quais têm versão nova e quais não são compatíveis com este aparelho.
24. Como usuário, quero que um pacote com checksum diferente do publicado seja recusado.
25. Como usuário, quero que um pacote cujo id ou versão difira da listagem seja recusado.
26. Como dono de um repositório antigo, quero que a listagem só com manifestos continue funcionando.
27. Como usuário, quero um erro com "tentar de novo" quando o repositório estiver fora do ar.

**Atualização**

28. Como usuário, quero atualizar um add-on de pacote pela tela de Atualizações, igual aos outros.
29. Como usuário, quero voltar à versão anterior de um pacote, e o catálogo embutido dessa versão precisa voltar junto.

**Tela Add-ons**

30. Como usuário, quero três entradas visíveis na tela de Add-ons, para achar a instalação sem conhecer os ícones.
31. Como usuário, quero ver meus add-ons com estado em ícone e texto, abaixo das entradas.

**Tela principal**

32. Como usuário de monitor ultrawide, quero que as fileiras usem toda a largura da janela, para aproveitar a tela de 34 polegadas.
33. Como usuário, quero ver mais pôsteres quando a janela cresce, em vez de pôsteres gigantes.
34. Como usuário, quero uma fileira "Continuar assistindo" com o progresso de cada item.
35. Como usuário, quero uma fileira com meus arquivos locais.
36. Como usuário, quero uma fileira de favoritos.
37. Como usuário, quero uma fileira por add-on ativo, com o nome da fonte, para ver os catálogos sem entrar em cada um.
38. Como usuário, quero abrir o catálogo completo a partir da fileira.
39. Como usuário, quero que uma fonte com defeito afete só a fileira dela, com "tentar de novo".
40. Como usuário, quero que a tela abra rápido e as fileiras de rede carreguem depois, sem travar.
41. Como usuário, quero que fileiras vazias sumam.
42. Como usuário sem nada ainda, quero o estado vazio atual com Abrir arquivo, Abrir link e Instalar add-on.
43. Como usuário, quero que destinos escondidos em "Menu principal" escondam também as fileiras correspondentes.
44. Como usuário em modo seguro, quero que as fileiras de add-ons não apareçam e a faixa de aviso continue lá.
45. Como usuário de teclado e de TV, quero mover o foco entre pôsteres e fileiras com as setas, sem perder a posição ao voltar do player.
46. Como usuário, quero que o toque em um pôster local abra o player e o de add-on passe pelo mesmo fluxo do catálogo da fonte.

### Implementation Decisions

**Decisões tomadas (podem ser revistas pelo dono antes do Passo 2):**

| Tema | Decisão | Motivo |
|---|---|---|
| Conteúdo do pacote | Só dados | A spec do produto e `docs/Olympus.md` proíbem código de terceiros sem assinatura, sandbox e isolamento |
| Botão desligado | Bloqueia zip, link, arquivo, texto colado, repositório não confiável, cadastro de repositório e troca para host novo | Fechar um caminho e deixar outro aberto não protege |
| Botão ligado | Mantém o aceite por instalação na revisão | O botão libera o caminho, e a revisão aprova cada item |
| Marcar repositório como confiável | Exige o botão ligado | Senão a marca vira um atalho que contorna o botão |
| Checksum | Obrigatório em repositório; zip local ou por link mostra o valor na revisão | Sem listagem não há valor publicado para comparar |
| Primeira entrega da tela principal | Só desktop; TV e celular em tickets próprios | Protege o layout já validado |

**Formato do pacote** (registrar em `docs/adr/0003-pacote-zip-so-dados.md`)

```text
pacote.zip
  addon.json     obrigatório; mesmo manifesto e validação de hoje
  catalog.json   opcional; envelope {"items": [...]}, mesma validação do feed
  icon.png       opcional; PNG ou JPEG, até 1 MB
  fanart.jpg     opcional; PNG ou JPEG, até 5 MB
```

Regras de validação, todas na borda e todas falhando fechado:

- Os arquivos ficam na raiz. Aceite também uma única pasta raiz contendo tudo, que é como muitos compactadores geram o zip.
- A lista acima é fechada. Qualquer outro nome recusa o pacote.
- O pacote precisa ter `catalog.json` ou `catalogUrl` no manifesto. **Motivo:** hoje um add-on sem `catalogUrl` serve o catálogo de demonstração, e um pacote assim mostraria filmes de demonstração como se fossem dele.
- Limites: 10 MB compactado, 30 MB descompactado e 16 entradas. `addon.json` e `catalog.json` seguem os limites atuais de 256 KB e 500 itens.
- O limite descompactado é verificado durante a extração, sem confiar no tamanho declarado no zip. Isso cobre o ataque de zip bomb.
- Recuse caminho absoluto, `..`, barra invertida, link simbólico, entrada criptografada e zip dentro de zip.
- Ícone e fanart têm a assinatura de bytes conferida, sem confiar na extensão.
- A descompactação roda fora da thread da interface.

**Reconhecer add-on do Kodi:** se a raiz tiver `addon.xml`, recuse com esta mensagem, sem ler nem executar nada dele:

> Este é um add-on do Kodi. Ele traz código que o Olympus não executa, por isso não pode ser instalado.

**Módulo de pacote (novo):** um único módulo profundo recebe os bytes do zip e devolve o pacote validado ou um `AddonError` com o motivo. Não depende de rede nem de tela. A interface pequena é a seguinte; os nomes podem mudar, a forma não:

```dart
// Parse puro. Rede, disco e tela ficam fora.
AddonPackage readAddonPackage(Uint8List zipBytes);

class AddonPackage {
  final AddonManifest manifest;
  final String sha256;
  final String? catalogJson;
  final int? catalogItemCount;
  final List<String> catalogSample; // no máximo 5 títulos
  final Uint8List? icon;
  final Uint8List? fanart;
}
```

**Contrato do gerenciador de add-ons:**

- `previewPackageFile(path)` e `previewPackageUrl(url, {onProgress, cancel})` devolvem uma prévia e não salvam nada.
- `installPackage(prévia, {originTrusted})` instala sempre desativado e registra a alteração para o modo seguro.
- `updateFromRepository(addonId)` e o rollback levam junto os arquivos do pacote.
- O novo erro `AddonError.unknownSourcesDisabled()` cobre todos os caminhos bloqueados.
- O gerenciador recebe uma função `bool Function() allowUnknownSources` no construtor. **O padrão é `() => true`**, para os testes existentes não quebrarem. O `main` liga a função às preferências. A regra fica no serviço, e a tela só apresenta o estado: um bloqueio só na tela seria contornado pelo fluxo de repositórios.

**Download:**

- Crie `fetchBytes` no mesmo contrato do fetcher, passando pela mesma barreira SSRF, redirects revalidados e limite por resposta. O teto é o do pacote, 10 MB. Reaproveite a lógica de `fetchText`, sem copiar.
- Dê a `fetchBytes` uma implementação padrão na classe base, porque os fakes de teste usam `extends` e não podem quebrar.
- O timeout de 15 s vale por tentativa de conexão e por intervalo sem dados, para não derrubar download lento em andamento.
- Redirect entre hosts não leva cabeçalho de autenticação, como já acontece hoje.

**Listagem de repositório:** continua `{"addons": [...]}` e estrita. Cada entrada aceita dois campos novos, que o parser atual ignora:

```json
{
  "id": "exemplo.fonte",
  "version": "1.2.0",
  "packageUrl": "https://exemplo.org/exemplo.fonte-1.2.0.zip",
  "sha256": "64 caracteres hexadecimais"
}
```

Os demais campos do manifesto continuam obrigatórios. `packageUrl` sem `sha256` válido reprova a listagem. Depois do download, confira checksum, id e versão, e qualquer diferença recusa o pacote. Entrada sem `packageUrl` segue o fluxo de manifesto atual.

**Armazenamento:**

- Arquivos ficam em `<suporte do app>/addons/<id>/<versão>/`, com o id já validado pelo padrão do manifesto.
- Grave em pasta temporária e renomeie no final. O add-on só é registrado depois que os arquivos estão no lugar, e falha limpa a pasta temporária.
- O registro de instalado ganha três campos opcionais: origem (`manifest`, `file`, `link` ou `repository`), `packageSha256` e `packageDir`. Documentos antigos continuam carregando, porque o guarda de arranque e o carregamento leem esse mesmo documento.
- O catálogo de um add-on de pacote vem do `catalog.json` guardado. Se houver `catalogUrl`, ele tem prioridade, e o guardado vira a reserva em falha de rede.
- A desinstalação e "limpar dados" apagam as pastas. O rollback de um nível mantém a pasta da versão anterior até a próxima atualização.

**Preferências:** adicione `allowUnknownSources`, padrão `false`, com leitura tolerante como as demais. Configurações ganha a seção "Add-ons" com esse botão. O aviso usa o diálogo de confirmação do projeto com o foco inicial em Cancelar.

Texto do aviso:

> **Permitir fontes desconhecidas?** Add-ons e repositórios de fora podem mostrar conteúdo incorreto ou sem autorização. O Olympus não verifica essas fontes e a responsabilidade pelo que você adicionar é sua. Cada instalação ainda passa pela sua revisão.

**Tela de instalação:**

- O seletor ganha o segmento "Zip", com "Neste aparelho" e "Por link". O filtro do seletor de arquivos aceita `.zip`, e o campo de caminho digitado continua disponível.
- A revisão é a mesma de hoje, com o SHA-256 e a contagem do catálogo. O app não mostra ícone de um pacote antes da instalação confirmada.

**Tela Add-ons:** três entradas no topo, sem copiar o visual do Kodi. Os ícones atuais dão lugar a elas, menos Atualizações. Mantenha uma lista simples no estilo do app: a spec do produto pede uma tela sem parede de ícones.

**Tela principal (desktop):**

- Um modelo puro `homeSections(...)` decide quais fileiras existem e em que ordem: Continuar assistindo, Arquivos locais, Favoritos e add-ons ativos por nome. Ele recebe dados e devolve seções, sem tocar em widgets.
- A regra atual de "Continuar assistindo" sai da tela e entra nesse modelo, sem mudar o comportamento.
- Arquivos locais são os itens da biblioteca com `MediaSourceType.local`.
- Fileira de add-on carrega depois da primeira pintura, até 20 itens, com cache em memória durante a sessão. A falha fica só nessa fileira, com "tentar de novo".
- `getCatalog` hoje marca o add-on como erro quando falha. Mantenha o isolamento e chame o catálogo de novo só no "tentar de novo" ou na ação "Atualizar".
- Largura: o `AppShell` limita o conteúdo a 1080. Adicione um parâmetro opcional para largura livre, usado só por esta tela. O padrão continua 1080 em todas as outras.
- Cartão: pôster 2:3 com largura base de 200 px, entre 160 e 240, título e linha secundária abaixo, borda azul no foco. Mais janela significa mais pôsteres. Referência: `docs/referencias/tela-principal-fileiras.webp`. Use só a organização da imagem, sem copiar marca nem conteúdo. Cores e tokens vêm de `docs/PADROES_VISUAIS.md`.
- A rolagem horizontal segue o foco. Cada fileira guarda a posição, e o foco volta ao mesmo pôster depois do player.
- Pôster de add-on abre pelo fluxo de `SourceCatalogScreen`: `resolvePlayback`, depois `library.upsert`, miniatura e player. Extraia esse fluxo para um ponto único, sem duplicar.
- Mantenha as ações do topo, a faixa de modo seguro e os botões Abrir arquivo e Abrir link.

**Glossário:** adicione ao `GLOSSARY.md`, no formato do arquivo:

- **Pacote de add-on:** zip só com dados.
- **Fonte desconhecida:** origem que o usuário adicionou e o app não verificou.
- **Repositório:** endereço que lista add-ons.
- **Fileira:** faixa horizontal de pôsteres da tela principal.

### Testing Decisions

Um bom teste verifica comportamento pela interface pública e usa valores esperados vindos de um exemplo fixo, nunca recalculados como o código faz. Crie os zips de teste na hora, em memória.

As costuras aprovadas para `/tdd`:

| Costura | O que pega | O que não pega |
|---|---|---|
| Módulo de pacote: `readAddonPackage` | Formato, limites, zip slip, zip bomb, `addon.xml` do Kodi | Disco, rede e tela |
| Gerenciador: `LocalAddonService` com `InMemoryLocalStore` e fetcher falso | Bloqueio do botão, instalação, checksum, repositório, atualização, rollback, compatibilidade com documento antigo | Pixels e foco |
| Fetcher: `HttpAddonFetcher.fetchBytes` com servidor em loopback e `allowPrivate` | Limite, redirect, SSRF, timeout, cancelamento | Interface |
| Modelo: `homeSections` | Ordem, fileiras vazias, destinos escondidos, modo seguro | Layout |
| Telas: `testWidgets` em instalação, Add-ons, Configurações e tela principal | Fluxo pelo usuário, teclado, foco, largura em 3440 × 1440 | Vídeo real |

**Prior art:** `test/addon_install_test.dart`, `test/addon_repos_test.dart`, `test/addon_updates_test.dart`, `test/addon_fetcher_test.dart`, `test/source_catalog_screen_test.dart`, `test/main_menu_test.dart`, `test/small_window_test.dart`, `test/tv_navigation_test.dart`.

**Casos obrigatórios do módulo de pacote:** zip válido nas duas formas de raiz, sem manifesto, manifesto inválido, zip corrompido, arquivo extra, `.py`, `addon.xml`, caminho com `..`, caminho absoluto, zip dentro de zip, sem catálogo nenhum, entrada que passa do limite real durante a extração e acima do total de entradas.

**Testes que fixam o que já foi validado:** em TV e celular a tela inicial segue igual até os tickets próprios. Toda tela que não pede largura livre continua limitada a 1080.

Nenhum teste nem o app usam repositório, add-on ou URL de terceiros. Para o teste manual, a Parte 4 usa pacote próprio criado a partir da fonte de teste do projeto.

### Out of Scope

- **Executar add-ons do Kodi (Python, `xbmc.*`, `plugin://`):** exigiria interpretador embutido e emular a API do Kodi, e contraria a regra atual de não rodar código de terceiros. Qualquer mudança nisso pede ADR próprio aprovado pelo dono.
- Ler `addons.xml` e `repository.*.zip` do Kodi. Só `addon.xml` é reconhecido, para a mensagem de incompatibilidade.
- Repositório, add-on ou catálogo de terceiros já vindo no app. A política em `docs/Olympus.md` diz que o app não hospeda, não indexa nem recomenda.
- Fonte de arquivos salva com navegação em diretório HTTP (a "brazucaplay" da tela do Kodi). O link direto e o repositório cobrem o caso, e ler listagem HTML é frágil.
- Pacote assinado (U25), atualização em segundo plano (U31) e a TV Tizen.
- Ajuste da imagem no player (preencher, esticar, zoom para 21:9). O player não tem isso hoje e merece spec própria.

### Further Notes

- `docs/Especificação do Player de Mídia.md` diz que o formato do pacote precisa ser definido antes de instalar zip. Este documento define, e o ADR registra. Não há conflito com ADR existente.
- `archive` e `crypto` já estão no `pubspec.lock` só como dependências indiretas. Declare-as como diretas com `flutter pub add` e confira se a versão resolvida não muda outras dependências.
- `docs/SITUACAO_ATUAL.md` só muda por ordem direta do usuário. Fica de fora até lá.

---

## Parte 3. Tickets

Ordem pronta para o `/to-tickets`. Cada ticket termina com `flutter analyze` limpo e a suíte verde.

### T1. Botão de fontes desconhecidas

**Entrega:** o usuário liga e desliga o botão nas Configurações, e o app bloqueia toda origem nova enquanto ele está desligado.

**Bloqueado por:** nada.

- [ ] Preferência com padrão desligado, lida de documentos antigos sem erro.
- [ ] Seção "Add-ons" em Configurações, com aviso ao ligar e foco inicial em Cancelar.
- [ ] Serviço recusa manifesto novo, repositório novo, repositório não confiável e troca para host novo.
- [ ] Atualizar, ativar, desativar, remover e instalar de repositório já confiável seguem funcionando.
- [ ] Tela de instalação e tela de repositórios mostram o motivo e o atalho para ligar.
- [ ] Marcar repositório como confiável exige o botão ligado.
- [ ] Testes existentes continuam verdes sem alteração.

### T2. Instalar zip do aparelho

**Entrega:** o usuário escolhe um zip, revisa, instala desativado, ativa e assiste ao catálogo embutido. Inclui o ADR e o módulo de pacote.

**Bloqueado por:** T1.

- [ ] `docs/adr/0003-pacote-zip-so-dados.md` escrito e termos novos no glossário.
- [ ] Todos os casos obrigatórios do módulo de pacote cobertos.
- [ ] Segmento "Zip" com seletor e caminho digitado; a revisão mostra SHA-256 e catálogo.
- [ ] `addon.xml` mostra a mensagem do Kodi.
- [ ] Pacote sem catálogo é recusado, sem nunca cair no catálogo de demonstração.
- [ ] Catálogo embutido abre e toca sem internet.
- [ ] Falha na instalação não deixa pasta nem registro.
- [ ] Remover add-on e "limpar dados" apagam os arquivos e não tocam em mídia.
- [ ] Documento antigo de add-ons carrega sem perda.

### T3. Instalar zip por link

**Entrega:** o usuário cola o link de um zip, acompanha o download, cancela se quiser, e segue para a mesma revisão.

**Bloqueado por:** T2.

- [ ] `fetchBytes` com SSRF, redirects revalidados e teto de 10 MB, sem duplicar `fetchText`.
- [ ] Fakes existentes de `AddonFetcher` compilam sem alteração.
- [ ] Progresso, cancelamento e erro com "tentar de novo".
- [ ] Cancelar não deixa arquivo temporário.

### T4. Instalar pacote de repositório

**Entrega:** o usuário abre um repositório, vê o estado de cada add-on, revisa e instala o pacote com checksum conferido.

**Bloqueado por:** T3.

- [ ] Listagem aceita `packageUrl` e `sha256`; listagem só com manifesto continua funcionando.
- [ ] `packageUrl` sem `sha256` válido reprova a listagem.
- [ ] Checksum, id ou versão diferentes recusam o pacote.
- [ ] Cada item mostra Instalado, Atualização disponível, Não compatível ou Disponível, em ícone e texto.

### T5. Atualizar e voltar versão de pacote

**Entrega:** um add-on de pacote atualiza pela tela de Atualizações e volta à versão anterior com o catálogo correspondente.

**Bloqueado por:** T4.

- [ ] A verificação de atualizações encontra versão nova no repositório de origem.
- [ ] A atualização guarda a pasta anterior e apaga a mais antiga.
- [ ] O rollback restaura manifesto e catálogo juntos.
- [ ] Falha na atualização mantém a versão atual funcionando.

### T6. Tela Add-ons com as três entradas

**Entrega:** Meus add-ons, Instalar de repositório e Instalar de zip ficam visíveis e levam direto a cada fluxo, com teclado, toque e controle remoto.

**Bloqueado por:** T4.

- [ ] Entradas visíveis no desktop, na TV e no celular em 360 dp.
- [ ] Estado vazio aponta para as duas formas de instalar.
- [ ] Testes de navegação na TV e de layout no celular seguem verdes.

### T7. Tela principal no desktop: fileiras locais

**Entrega:** no desktop, o Início mostra as fileiras de Continuar assistindo, Arquivos locais e Favoritos, usando toda a largura da janela.

**Bloqueado por:** nada.

- [ ] Modelo `homeSections` puro, com a regra de "Continuar assistindo" movida sem mudar o resultado.
- [ ] Parâmetro de largura livre no `AppShell`; as outras telas continuam em 1080.
- [ ] Em 3440 × 1440 o conteúdo ocupa a largura toda, com mais pôsteres e sem aumentar o tamanho deles.
- [ ] Em janela pequena nada estoura, seguindo `test/small_window_test.dart`.
- [ ] Foco por setas, e a posição volta depois do player.
- [ ] Estado vazio, destinos escondidos e faixa de modo seguro continuam corretos.
- [ ] Testes fixam a tela atual em TV e celular.

### T8. Tela principal no desktop: fileiras de add-ons

**Entrega:** cada add-on ativo ganha uma fileira, que carrega sem travar e abre o catálogo completo.

**Bloqueado por:** T7.

- [ ] A primeira pintura não espera a rede.
- [ ] Até 20 itens, com cache em memória durante a sessão, e ação "Atualizar".
- [ ] Falha de um add-on afeta só a fileira dele, com "tentar de novo".
- [ ] Ativar ou desativar um add-on muda as fileiras sem reiniciar.
- [ ] Modo seguro não mostra fileiras de add-on.
- [ ] Reprodução passa por um único fluxo, compartilhado com o catálogo da fonte.

### T9. Tela principal na TV

**Entrega:** a TV usa as fileiras com tokens próprios, margem anti-overscan e navegação completa no D-pad.

**Bloqueado por:** T8. **Requer aprovação do dono na tela do desktop antes de começar.**

- [ ] Foco inicial previsível; voltar sai das fileiras na hierarquia atual.
- [ ] Sem novas telas brancas nem perda de foco ao rolar.
- [ ] `test/tv_navigation_test.dart` segue verde.
- [ ] Validação na TCL registrada.

### T10. Tela principal no celular

**Entrega:** o celular usa fileiras no Início, dentro das abas atuais.

**Bloqueado por:** T8. **Requer aprovação do dono na tela do desktop antes de começar.**

- [ ] Cabe em 360 dp, com rolagem por gesto.
- [ ] Navegação inferior e voltar do sistema como hoje.
- [ ] `test/mobile_layout_test.dart` segue verde.

### T11. Documentos e fechamento

**Entrega:** os documentos refletem o que foi entregue.

**Bloqueado por:** T5, T6, T8.

- [ ] `CHANGELOG.md` e `docs/FONTES_ADAPTADOR.md` atualizados.
- [ ] Trecho sobre instalação em `docs/Olympus.md` atualizado.
- [ ] Checklist de release criado no mesmo modelo dos anteriores, sem criar tag.

```text
T1 → T2 → T3 → T4 → T5 ─┐
               T4 → T6 ─┼→ T11
T7 → T8 ───────────────┘
     T8 → T9
     T8 → T10
```

---

## Parte 4. Teste no aparelho e correção

Use os seriais e o procedimento já combinados com o usuário para TCL, emulador e Windows.

**Prepare os pacotes de teste:** gere, numa pasta temporária fora do repositório, `ok.zip` (válido, com catálogo apontando para a fonte de teste do projeto), `kodi.zip` (com um `addon.xml` qualquer), `extra.zip` (com um `.py`) e `quebrado.zip` (bytes truncados). Publique o repositório de teste no `olympus-catalog` do próprio usuário somente com o pedido dele.

| # | Aparelho | Ação | Esperado |
|---|---|---|---|
| 1 | Windows | Instalação limpa, abrir instalação de zip | Bloqueado, com motivo e atalho |
| 2 | Windows | Ligar o botão pelo atalho | Aviso abre; ao ativar, a tela libera |
| 3 | Windows | Instalar `ok.zip` | Revisão completa; entra desativado |
| 4 | Windows | Ativar e tocar um item | Toca e aparece em Continuar assistindo |
| 5 | Windows | Instalar `kodi.zip`, `extra.zip` e `quebrado.zip` | Três mensagens diferentes, nada instalado |
| 6 | Windows | Desligar o botão | `ok.zip` segue ativo; instalar outro é bloqueado |
| 7 | Windows | Remover o add-on | Pasta some; mídias locais ficam |
| 8 | Windows 34" | Tela principal em tela cheia | Largura total, sem pôster gigante, com setas funcionando |
| 9 | Windows | Derrubar a rede com um add-on ativo | Só a fileira dele mostra erro |
| 10 | TCL | Zip por link e pelo caminho digitado | Funciona com o controle |
| 11 | TCL | Seletor de arquivos em "Neste aparelho" | Abre ou o app orienta a usar caminho ou link |
| 12 | Celular | Instalar zip pelo seletor | Funciona em 360 dp |

**Risco a confirmar nos itens 10 a 12:** as permissões atuais do Android cobrem vídeo, não zip, e a TV pode não ter seletor de documentos. Se o caminho digitado falhar, o link continua sendo a saída da TV. Registre o resultado em vez de pedir uma permissão ampla de armazenamento.

**Correção:** para cada defeito, abra um ticket com o passo que reproduz, rode `/diagnosing-bugs`, crie o teste que falha e só então corrija. Repita só a linha afetada e a suíte. Registre os resultados no checklist de release.

---

## Parte 5. Mapa do código

Retrato do commit `d601b34`. Se algo mudou, vale o código.

| Assunto | Onde |
|---|---|
| Contrato e implementação de add-ons | `lib/services/addon_service.dart`, `lib/services/local_addon_service.dart` |
| Rede com SSRF e limites | `lib/services/addon_fetcher.dart` |
| Modelos | `lib/models/addon_manifest.dart`, `addon_info.dart`, `addon_repository.dart`, `addon_catalog_item.dart` |
| Erros de add-on | `lib/core/errors/app_error.dart` |
| Limites | `lib/core/constants/app_constants.dart` |
| Telas de add-on | `lib/features/addons/` |
| Fluxo de reprodução do catálogo | `lib/features/addons/source_catalog_screen.dart` |
| Início | `lib/features/home/home_screen.dart`, `mobile_shell.dart` |
| Largura de 1080 | `lib/widgets/app_shell.dart` |
| Cartão atual e miniaturas | `lib/widgets/media_card.dart`, `lib/services/thumbnail_service.dart` |
| Preferências | `lib/models/preferences.dart`, `lib/features/settings/settings_screen.dart` |
| Montagem dos serviços | `lib/main.dart` |
| Guarda de arranque, que lê o documento de add-ons | `lib/services/startup_guard.dart` |
