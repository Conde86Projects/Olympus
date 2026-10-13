# Checklist de release — Olympus 0.1.0-rc.3

Commit: `91fc7e8` (preservação de posição na troca de qualidade HLS).
Tag: `v0.1.0-rc.3` (anotada, em `91fc7e8`). Sem tag final.
Tag anterior `v0.1.0-rc.2` intacta em `3d1ad3f`.

## Gates (reconfirmados antes da tag)

- [x] Suíte completa verde: 512/512 testes (`flutter test`).
- [x] `dart analyze` limpo, sem issues.
- [x] Bateria HLS verde (83 testes): seletor, política, retomada,
      sonda, prontidão e preservação na troca (8 novos).
- [x] Árvore limpa no commit (só código, testes e docs da correção).

## Artefato identificado (fora do git, `build/` ignorado)

- Arquivo: `build/app/outputs/flutter-apk/player-olympus-0.1.0-rc.3-debug.apk`
  (cópia identificada de `app-debug.apk`, mesmos bytes).
- SHA-256:
  `8894FC25FB90F144AF8CA402B4B12D9B4A4D3005B97525F75BCF4E88AB7D1D68`
- Tamanho: 210603413 bytes. `versionName=0.1.0-rc.3` confirmado no
  aparelho após `adb install -r` (pubspec `0.1.0-rc.3+3`, commit
  corretivo posterior à tag; lógica HLS idêntica à validada).
- O APK anterior (SHA `52F82AE9…FBE86D8A`, `versionName=0.1.0-rc.2`)
  não é o artefato final da RC3.

## Concluídos nesta RC (validados na TCL em 13/10/2026)

BeyondTV, Android 9, 1920x1080, item `x36xhzz`
(id `1791759213619190`), logs `[hls-resume]` sem credenciais.

| Item | Resultado |
|---|---|
| Retomada HLS | OK: alvo 0:35 pousou exato, sem correção; fria (pós force-stop) em 8:04 exata com fallback master |
| Troca manual para 720p | OK: gate passou no 1º avanço (189 ms, tocando), pouso em 125,2 s, sem correção nem rollback; painel "720p" |
| Retorno à Automática | OK: pouso em 323,4 s, efetiva 288p, sem rollback |
| Rollback controlado | OK por ausência: zero linhas `rollback`/`fallback` no log — nenhum pouso saiu da tolerância de 4 s |
| Proteção do histórico | OK: após todas as trocas, histórico íntegro em 8:04; item, ID e duração intactos |
| Fallback master | OK: aberturas frias com `effective=master`, reprodução contínua |

## Não observados no aparelho (cobertos em suíte)

- Downgrade automático: não disparou (reprodução saudável em
  288p durante 60 s em Automática); o mecanismo é o mesmo
  `_reopenHlsTarget` das trocas validadas, com teste dedicado.
- Falha de seek pós-troca (rollback + pausa + proteção):
  sem ocorrência no aparelho; coberta por 3 testes dedicados
  (retorno à anterior, pausa com histórico protegido).

## Windows (sem alteração desde a RC2)

- Desktop nunca tetado pelo viewport, Automática = master,
  manual e retorno, sem rebaixamento pelo observador (testes
  dedicados verdes nesta suíte). Sem revalidação em hardware
  neste ciclo — código de desktop intocado.

## Pendências separadas (não bloqueiam esta RC)

- Detecção fria de variantes HLS (aquecimento posterior,
  sem atrasar abertura nem alterar histórico/ID).
- Modo seguro.
- Diagnóstico (endurecimento; `[player-diag]` no aparelho
  contém URLs — só no dispositivo, relatório exportado limpo).

## Instalação

Android TV (depuração USB/LAN ativada):

```sh
adb connect 192.168.1.8:5555
adb -s 192.168.1.8:5555 install -r player-olympus-0.1.0-rc.3-debug.apk
```

Dados preservados com `-r`; histórico e biblioteca mantidos.
