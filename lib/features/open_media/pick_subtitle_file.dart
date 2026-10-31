import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:player/app/tv_mode.dart';
import 'package:player/features/open_media/tv_file_browser_screen.dart';
import 'package:player/services/video_file_listing.dart';

/// Escolhe um arquivo de legenda. Na TV usa o navegador próprio; no celular
/// e no desktop, o seletor nativo. Devolve o caminho ou null ao desistir.
Future<String?> pickSubtitleFile(BuildContext context) async {
  if (TvMode.of(context)) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const TvFileBrowserScreen(
          list: listSubtitleFolder,
          title: 'Escolher legenda',
          emptyMessage: 'Nenhuma legenda nesta pasta. Conceda acesso aos '
              'arquivos ou escolha outra pasta.',
        ),
      ),
    );
  }
  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: [
      for (final extension in subtitleExtensions) extension.substring(1),
    ],
    dialogTitle: 'Abrir arquivo de legenda',
  );
  return files.singleOrNull?.path;
}
