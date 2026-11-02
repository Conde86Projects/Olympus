# Release Checklist — v0.4.2

Versão `0.4.2+1014`. Acabamento da auditoria sobre a 0.4.1, sem função nova.

- [x] `flutter analyze` limpo e 1171 testes passando
- [x] `integration_test/addons_desktop_test.dart` no Windows real
- [x] add-on sem feed nem pacote fica sem itens (teste automático)
- [x] pôster e vídeo de catálogo com IP interno são recusados (teste automático)
- [x] versionName `0.4.2` na TCL (`dumpsys`), com a fileira de add-on e os dados mantidos
- [x] pacote do Windows abre pelo zip; versão `0.4.2+1014` no `player.exe`, sem a DLL do cofre

## Limites conhecidos

- O bloqueio de rede interna em pôster e vídeo vale para IP escrito na URL. Nome que
  resolve para IP interno só é bloqueado nos downloads do próprio app.
- Quem abre um link à mão continua podendo usar a rede interna: é escolha da pessoa.
- Os testes à mão da v0.4.0 seguem pendentes.

## SHA-256

- `Olympus-0.4.2.apk`: `25a3d8ad2d53998a3e8216913b0de846be37d3f0d8a05a42adbe4308da4f1bab`
- `Olympus-0.4.2-windows.zip`: `0fbfa4ad499430b70d3c495213790368b2757c742f22667826fcc9da283a6af3`
