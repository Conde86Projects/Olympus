import 'package:flutter/material.dart';
import 'package:player/app/app.dart';
import 'package:player/app/routes.dart';
import 'package:player/features/open_media/open_media_screen.dart';
import 'package:player/widgets/app_shell.dart';
import 'package:player/widgets/focusable_button.dart';
import 'package:player/widgets/scroll_when_short.dart';

/// Apresentacao inicial (spec 6, 7): uma tela rapida na primeira execucao,
/// que pode ser pulada. Marca [showOnboarding] como visto ao sair por
/// qualquer acao.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Player',
      // Janela baixa (compacto ~480x270): rola em vez de estourar.
      body: ScrollWhenShort(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.play_circle_outline,
                  size: 72,
                  color: Colors.white70,
                ),
                const SizedBox(height: 24),
                Text(
                  'Assista sem complicação',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Abra arquivos do aparelho ou links de mídia, continue de onde parou e organize favoritos e histórico — tudo fica com você, nada sai do aparelho.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    FocusableButton(
                      label: 'Começar',
                      icon: Icons.arrow_forward,
                      primary: true,
                      autofocus: true,
                      onPressed: () => _dismiss(context, AppRoutes.home),
                    ),
                    FocusableButton(
                      label: 'Abrir vídeo',
                      icon: Icons.folder_open,
                      onPressed: () => _dismiss(
                        context,
                        AppRoutes.openMedia,
                        const OpenMediaArgs(tab: OpenMediaTab.file),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _dismiss(
    BuildContext context,
    String route, [
    Object? arguments,
  ]) async {
    final prefs = dependencies.preferencesService;
    await prefs.update(prefs.current.copyWith(showOnboarding: false));
    if (!context.mounted) return;
    // A rota inicial '/onboarding' monta um '/' escondido por baixo.
    // Indo ao Inicio, troca tudo por ele (senao ficavam dois Inicios e
    // o voltar levava ao de baixo); indo a outra tela, o Inicio de
    // baixo fica como destino do voltar.
    Navigator.of(context).pushNamedAndRemoveUntil(
      route,
      (r) => route != AppRoutes.home && r.settings.name == AppRoutes.home,
      arguments: arguments,
    );
  }
}
