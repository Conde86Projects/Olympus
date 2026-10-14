# Checklist de release — Olympus 0.1.0-rc.8

RC do seletor de idioma navegável por D-pad (correção
pré-release, fora do escopo da RC7 mas exigida antes da versão
pública). Commit do fix: `583cbe9`; marco RC8: versionamento
`0.1.0-rc.8+8` + este checklist. Sem tag final. Tags anteriores
intactas (`v0.1.0-rc.7` em `09ca0af`, etc.).

## Gates (antes da tag)

- [x] Suíte completa verde: 536/536 testes (`flutter test`).
- [x] `dart analyze` limpo, sem issues.
- [x] Árvore limpa no commit de versionamento.
- [x] `version_consistency_test`: `AppConstants.appVersion`
      acompanha o núcleo do `version:` do pubspec.
- [x] Diff RC7→RC8 limitado a Configurações/idioma, testes,
      checklist e changelog (nada em player, HLS, modo seguro
      ou diagnóstico).

## Consistência das 4 fontes

- [x] `pubspec.yaml`: `0.1.0-rc.8+8`.
- [x] `AppConstants.appVersion`: `0.1.0-rc.8`.
- [x] Tela Diagnóstico e Sobre exibindo `0.1.0-rc.7` no binário
      do fix (o bump para rc.8 é só string de versão; o
      conteúdo validado é idêntico).
- [x] `versionName=0.1.0-rc.8` via dumpsys após `adb install -r`
      do APK gerado de `9dddc7c` (debug, mesmo perfil da RC7).
- [x] SHA-256 do APK:
  `B32A8DFE4C02B37BADFCED304CC3B9A7215E8A4F147F6D875DBD7EE0530FDBC4`.
- [x] Diagnóstico e Sobre no binário RC8 exibem `0.1.0-rc.8`
  (Sobre usa o mesmo `AppConstants.appVersion` do Diagnóstico).

## Validação do fix na TCL (BeyondTV, Android 9, 13/10/2026)

Causa raiz: com o IME fechado o foco ficava retido no TextField
e a TCL entrega DPAD_UP/DOWN ao IME antes do Flutter — o
`DpadFieldExit` nunca recebia as setas. Fix: sem TextField no
caminho do D-pad; linha abre `LanguagePickerPage` (ListView de
ListTiles, foco determinístico via FocusNode pós-frame).

- [x] DOWN sai do campo (Padrão → alemão, foco segue na lista).
- [x] UP retorna ao item anterior, sem armadilha.
- [x] OK confirma (`defaultSubtitle=deu`, linha mostra alemão).
- [x] BACK fecha preservando (`defaultSubtitle=null`).
- [x] Teclado desktop intacto (Abrir vídeo segue com
      `DpadFieldExit`, coberto por testes).
- [x] `DropdownButton`, fontes e reprodução: intocados.
- [x] 6 testes novos em `test/language_picker_test.dart`.

## Limpeza + teste curto final na TCL (13/10/2026)

- [x] Biblioteca: só os 4 itens RC6 (cold-* e URL errada
      removidos); históricos órfãos e `.bak-reg` removidos;
      `/data/local/tmp` e `/sdcard` limpos.
- [x] Prefs: volume 100% (`initialVolume=1.0`), legendas off,
      idioma pt-BR, tvMode on, `manualSafeMode=false`.
- [x] Boot + Home normais; player abre com diálogo de retomada
      (x36 3:44→3:54, 35%→37%, ID/fonte intactos).
- [x] Idioma preferido: ciclo DOWN/UP/BACK preserva Padrão.
- [x] Sobre: `0.1.0-rc.7`; Diagnóstico: 4 vídeos, 4 entradas,
      último erro antigo (11/10, pré-existente).
- [x] Modo seguro: on → banner → off → boot normal.
- [x] Cold probe: por construção (player/HLS intocados desde a
      validação RC7 S1/S2/S3 + pronta + permanente).

## Validação do APK RC8 na TCL (13/10/2026, `9dddc7c`)

APK debug instalado por cima (dados preservados). Protetor de
tela (dream) cobriu a tela no início — tela do launcher por cima do
app focado; dispensa com qualquer tecla, sem relação com o app.

- [x] Boot + Home normais (x36 5:10, ForBigger 0:33).
- [x] D-pad completo: DOWN/UP/OK (`deu`, linha mostra alemão),
      BACK preserva, Padrão restaurado (`null`).
- [x] Retomada HLS: x36 3:54→5:10 tocando, ID/fonte intactos.
- [x] Player + histórico: biblioteca 4 itens, 4 entradas.
- [x] Modo seguro: on → banner → off → boot normal
      (`manualSafeMode=false`).
- [x] Diagnóstico: `0.1.0-rc.8`, 4 vídeos, 4 entradas, último
      erro antigo (11/10, pré-existente).
- [x] Volume: `initialVolume=1.0` antes e depois da reabertura.
- [x] Cold probe: rede lenta → master imediato + erro
      controlado com `cold-failed attempt=1` único; com
      recuperação → `cold-ready attempt=1 count=5` e reprodução
      flui (BBB); sem troca silenciosa, reopen, seek ou
      mudança de histórico/ID.
- [x] Aparelho limpo ao fim: 4 lib / 4 hist (só RC6), prefs em
      default, `player_data` só com os 3 JSON, tmp e sdcard
      limpos, servidor local parado, reverse removido.

## APK final 0.1.0 (commit `29f7965`, 14/10/2026)

- [x] APK debug gerado sem alterar código, instalado na TCL
      (BeyondTV, Android 9 — DHCP mudou para `192.168.1.4:5555`).
- [x] `versionName=0.1.0` exato via dumpsys.
- [x] SHA-256 do APK final:
  `5211A70DE76B3E2786E330AA8AD7E49BAAC311E987841C4494D89759AA06C0F0`.
- [x] Diagnóstico exibe `0.1.0` (4 vídeos, 4 entradas, modo
      seguro não); Sobre exibe `Versão 0.1.0 — protótipo`.
- [x] Gates reconfirmados: 536/536 testes, `analyze` limpo,
      árvore limpa, tags rc.1–rc.8 intactas.
- [x] Tag `v0.1.0` criada exatamente em `29f7965` (tags
      `v0.1.0-rc.1`…`v0.1.0-rc.8` não movidas).

## Comportamento de volume (definição)

- Primeira instalação → volume padrão seguro (`initialVolume`
  1.0 no modelo).
- Reabertura → preserva o volume do usuário (prefs).
- Os 65% vistos eram estado persistido de teste, não defeito;
  nenhum dado de usuário real foi apagado (só resíduos de
  teste no aparelho de validação).
