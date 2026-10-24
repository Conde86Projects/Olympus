# Volume por plataforma

Celular e TV usam o volume do aparelho (fora do app); no desktop o volume fica no sistema com ajuste fino interno. Em toda parte o player oferece só o mudo, e subir o volume do sistema despluga o mudo do app.

Status: accepted.

## Considered Options

Trilho de volume interno em todas as plataformas. Rejeitado: o trilho empurrava os botões no Windows e brigava com o volume do aparelho no celular e na TV.

## Consequences

O app observa o sistema via canal nativo (`getState` + `VOLUME_CHANGED_ACTION`) sem nunca ajustar o volume do aparelho. Verificado em 24/10/2026 no Xiaomi 24069PC21G (Android 16, API 36, `targetSdk=36`): o receiver registra com `registerReceiver` de 2 args e recebe os broadcasts (`dumpsys activity broadcasts` mostra o filtro do `com.example.player` com entregas `DELIVERED`). Sem flag de exportação.
