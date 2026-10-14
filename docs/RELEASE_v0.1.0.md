# Olympus 0.1.0 — página de release

Versão final do player local, validada em hardware real (TCL
BeyondTV, Android 9). Tag `v0.1.0` em `29f7965`.

## Artefato

- Arquivo: `build/app/outputs/flutter-apk/app-release.apk`
  (97 MB, `flutter build apk --release`, sem alteração de código
  sobre a tag).
- SHA-256:
  `2AE9A69293D5826D09E5B033FAE25091035107E6B67F6ABC49BC55EAF27F9C0A`
- Assinatura: chave dedicada de release (RSA 4096, válida até
  ~2051), DN `CN=Olympus Player, OU=Release, O=Olympus, C=BR`,
  impressão SHA-256 do certificado:
  `413746219A7754355E2E1F6CE15438B3B6E6F415670E248B1FE3FE5801F2C3BD`.
- `versionName=0.1.0`, `versionCode=9` (via dumpsys após instalar).
- A chave privada (`android/upload-keystore.jks` + senha em
  `android/key.properties`) NÃO está no git — faça backup agora;
  sem ela não há atualização futura com a mesma assinatura.

## O que há nesta versão (resumo do CHANGELOG)

Reprodução local (arquivo e link autorizado), biblioteca,
histórico com retomada exata, favoritos, retomada HLS precisa,
seleção manual de qualidade, política automática por
desempenho, detecção fria de variantes (sonda única posterior),
seletor de idioma por D-pad, diagnóstico com exporto sanitizado
e modo seguro. Detalhes em [CHANGELOG.md](../CHANGELOG.md).

## Requisitos

- Android 7.0+ (API 24, `minSdk=24`); validado no Android 9 (API 28).
- TV com D-pad ou desktop Windows/Linux; touchscreen opcional.
- Internet apenas para links remotos (reprodução local é offline).
- ~100 MB livres para o APK.

## Limitações conhecidas

- Estilo visual das legendas (tamanho/cor/fundo/posição): o
  media_kit não expõe as propriedades do mpv pela API Dart.
- TV antiga (Mali-470 não renderiza Vulkan/GLES3); validação
  visual vale para TVs atuais.
- Nenhum provider real conectado: fontes externas entram como
  adaptador isolado em `lib/services/sources/`.
- Último erro antigo no diagnóstico (zone mismatch, 11/10):
  pré-existente, sem impacto observado.

## Instalação

Instalação limpa (testada na TCL):

```sh
adb install app-release.apk
```

Primeira abertura mostra o onboarding; volume inicial 100%,
legendas desligadas, idioma pt-BR.

## Atualização a partir da RC8-debug

A RC8 instalada na TCL era assinada com a chave debug; o APK
final usa a chave dedicada — o Android recusa a atualização
direta (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`, observado). É um
custo único de migração de chave:

1. Salve o essencial (o app não exporta biblioteca ainda;
   anote links e posições).
2. `adb uninstall com.example.player` (apaga os dados).
3. `adb install app-release.apk`.
4. Readicione os vídeos.

Atualizações futuras com a mesma chave preservam
biblioteca/histórico/prefs pelo contrato da plataforma
(reinstalação com a mesma chave testada: instala e abre normal;
o manifest não desativa backup). Os dados da RC8 da TCL estão
copiados em `.fl-tmp/cold-hls/rel-lib.json`,
`rel-hist.json` e `rel-prefs.xml` (fora do git).
