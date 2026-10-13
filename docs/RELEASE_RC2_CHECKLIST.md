# Checklist de release — Olympus 0.1.0-rc.2+2

Tag: `v0.1.0-rc.2` (anotada, em `3d1ad3f`). Sem tag final.

## Gates (preservados)

- [x] Suíte completa verde: 504/504 testes (`flutter test`).
- [x] `dart analyze` limpo, sem issues.
- [x] Bateria HLS verde (75 testes): seletor, política, retomada,
      sonda e prontidão.
- [x] Build Windows Release compila (`player.exe`).

## Artefato identificado (fora do git, `build/` ignorado)

- Arquivo: `build/app/outputs/flutter-apk/player-olympus-0.1.0-rc.2-debug.apk`
  (cópia identificada de `app-debug.apk`, mesmos bytes).
- SHA-256:
  `438502F55758D176873FF6E684315026BABAE368CE1E6ABEE9FDF5D99D7B7F3E`
- Tamanho: 210601929 bytes. `versionName=0.1.0-rc.2` confirmado no
  aparelho após `adb install -r`.

## Aceitação na TCL (BeyondTV, Android 9, 1920x1080) — sem código novo

| Item | Resultado |
|---|---|
| Rede pronta + variante tetada | OK: mpv abre `url_4` (288p); painel "Automática · 288p" |
| Retomada HLS (alvo 2:08) | OK: gate espera 1º avanço, pousa exato, sem correção; histórico íntegro |
| Seek +10 s | OK: mpv busca 203.6 s |
| Qualidade manual 720p | OK: mpv abre `url_0`; painel mostra "720p" |
| Retorno para Automática | OK: mpv reabre `url_4` |
| Downgrade observado + efetiva | OK: `url_4` → `url_2`; painel "Automática · 184p" |
| MP4 inacessível (rede) | OK: erro controlado em PT, sem crash |
| MP4 local (histórico do aparelho) | OK (reprodução completa registrada hoje, caminho intocado) |
| Playlist simples (media playlist) | OK: reproduz, sem linha Qualidade, histórico próprio |
| Histórico/IDs | OK: entradas únicas por id, sem concluído indevido |
| Rótulos | OK: PT em todas as telas, sem URLs/códigos |
| Troca de qualidade preserva posição | **FALHOU**: seek pós-troca falha no mpv frio (`error running command _command(seek, …)`); posição 193 s → ~10 s; histórico salvou 26 s. Mesmo mecanismo do resume frio, mas no caminho de troca — item separado abaixo, não bloqueia o que passou |
| Rede fria / fallback master | Não reproduzido no aparelho (rede pronta nas rodadas); coberto em suíte. Investigação separada abaixo |

## Aceitação Windows (neste host)

- Desktop nunca tetado pelo viewport, Automática = master, manual
  e retorno, sem rebaixamento pelo observador (testes dedicados).
- `flutter build windows` Release compila.

## Logs sem credenciais

- Sonda `resume-*` no log técnico: só números, estados, id do item
  e rótulo da variante (teste varre `http` em todas as entradas).
- Linhas `[hls-resume]` no logcat (debug): id + milissegundos.
- Linhas `[player-diag]` do mpv contêm URLs das mídias tocadas
  (comportamento anterior, só no aparelho); o relatório exportado
  do diagnóstico continua sem URL/caminho/credencial.

## Instalação

Android TV (depuração USB/LAN ativada):

```sh
adb connect 192.168.1.8:5555
adb install -r player-olympus-0.1.0-rc.2-debug.apk
```

Windows: `flutter build windows`, executar
`build/windows/x64/runner/Release/player.exe`.

Rollback: reinstalar o APK da tag anterior
(`git show v0.1.0-rc.1 --stat` para referência) ou
`git revert 3d1ad3f`; dados locais (`history.json`,
`library.json`) são preservados pelo reinstall.

## Próximo hardening (não bloqueia a RC2)

- Modo seguro.
- Diagnóstico (evolução).
- [Investigação, sem bloqueio] Detecção fria de variantes HLS —
  ver BACKLOG: aquecimento posterior da detecção, uma única
  tentativa limitada após a abertura, sem reiniciar reprodução,
  sem trocar qualidade durante o vídeo, sem alterar
  histórico/ID.
- [Falha registrada] Seek pós-troca de variante no mpv frio —
  mesma classe do resume frio, no caminho `_switchHlsQuality`/
  downgrade; exige gate de seek antes de reabrir em variante
  (proposta, sem código aplicado).
