# Resultados — feed definitivo (0.2.1, Fase 0.3)

Build de teste: commit `48a6fa2` (versão `0.2.1+11`).
APK release SHA-256
`831878f38350c48e9057ef8df5bd1da9512c00923798ea4b449fc4695d40dcdc`
(97.807.576 bytes; `aapt`: versionCode 11, versionName 0.2.1).
Gates antes do build: `flutter analyze` limpo, 646/646 testes.

Feed: `https://conde86projects.github.io/olympus-catalog/feed.json`
(só Big Buck Bunny). `feed-smoke.json` não foi usado nesta rodada.

## 1. Windows (19/10, `player.exe` 0.2.1+11, pilotado por mouse)

| Caso | Resultado |
|---|---|
| Adicionar fonte → Link → prévia | OK: origem certa, "Catálogo: 1 item · Big Buck Bunny" |
| Aprovar → ativar → atualizar | OK: "Catálogo atualizado: 1 item" |
| Catálogo e miniatura | OK: miniatura própria, descrição CC-BY, 9:56 |
| Reproduzir MP4 | OK: abre em 720p, controles com 9:56 |
| Seek para frente | OK: clique no meio → 5:06, imagem certa logo de cara |
| Seek para trás | OK: retroceder volta ~10 s |
| Histórico / progresso | OK: topo do "Continuar assistindo", "parou em 5:10" |
| Retomada | OK: reabre em ~5:10 |
| Conclusão (97%) | OK: fim → "Reprodução concluída"; item sai do "Continuar assistindo" |
| "Ver de novo" | OK: "Você já concluiu este vídeo · Começa do início" → 0:02 |
| Fechar pelo X | OK: processo termina; ao reabrir, "parou em 2:36" |
| Erro controlado | OK: editar para `feed-inexistente.json` recusa com "O endereço não respondeu (HTTP 404)"; fonte segue no feed certo |
| Janela pequena | Não repetido (código inalterado desde a 0.2.0) |

Observação (não bloqueia): na tela do catálogo o rótulo mostra
"Ativo · ainda não atualizado" logo depois de "Catálogo atualizado:
1 item". Conferir se o rótulo deveria mudar.

## 2. TCL (BeyondTV, Android 9)

- [x] APK 0.2.1 instalado por cima da 0.2.0 sem desinstalar
      (`192.168.1.4:5555`), dados e preferências preservados.
- [x] Prévia do feed definitivo (URL digitada pelo usuário com o
      controle): "Fonte Própria (teste)", 1 item, origem certa.
- [ ] Aprovar, ativar, catálogo, miniatura, reprodução, seek,
      retomada, histórico, 97%, "Ver de novo", voltar ao catálogo,
      D-pad/foco — com o controle remoto.

Automação: `adb input` na TCL perde e altera teclas (`onde86`,
`fee.json`, `htts;`) e deixou o campo com texto inválido invisível
("Endereço inválido"); com o controle a mesma URL funcionou. O foco
do D-pad também não aparece pelo `adb input` (igual à rodada 0.2.0).
Validar a TCL só com o controle.

## 3. Celular (Xiaomi 24069PC21G)

- [x] APK 0.2.1 instalado do zero: o app anterior tinha outra
      assinatura (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`), desinstalado
      com autorização; a MIUI pede "Permitir" no aparelho.
- [x] Roteiro completo executado pelo usuário (19/10). A MIUI bloqueia
      `adb input` (`INJECT_EVENTS`), então não houve pilotagem por adb.

## 4. Achado: "Cancelar" transparente ao adiantar/pausar

Visto pelo usuário nos três aparelhos. O indicador de carga do
player mostrava o botão "Cancelar" em `loading` **e** em `buffering`;
seek e pausa passam por `buffering`, então o botão piscava no meio do
vídeo — e tocá-lo chamava `stop()`, parando a reprodução.

Correção: "Cancelar" só na abertura (`loading` ou posição zero); no
meio do vídeo fica só o indicador. Travamento longo continua virando
erro pelo supervisor, com "Tentar novamente". Testes novos em
`test/playback_recovery_test.dart` (o do meio do vídeo falha sem a
correção). Gates: analyze limpo, 648/648.

Pendente: revalidar nos aparelhos com um build novo, que precisa de
versão nova (o `0.2.1+11` testado não tem a correção).
