import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:player/app/tv_mode.dart';
import 'package:player/features/open_media/tv_file_browser_screen.dart';
import 'package:player/services/video_file_listing.dart';

/// Escolhe um arquivo para instalar add-on ([extension] sem o ponto). Na TV
/// usa o navegador próprio, porque o seletor do sistema não abre no Google
/// TV; no celular e no desktop, o seletor nativo. Devolve o caminho ou null
/// ao desistir.
Future<String?> pickAddonFile(
  BuildContext context, {
  required String extension,
  required String title,
}) async {
  if (TvMode.of(context)) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => TvFileBrowserScreen(
          list: (path) => listFolderWithExtension(path, '.$extension'),
          title: title,
          emptyMessage: 'Nenhum arquivo .$extension nesta pasta. Conceda acesso '
              'aos arquivos ou escolha outra pasta.',
        ),
      ),
    );
  }
  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: [extension],
    dialogTitle: title,
  );
  return files.singleOrNull?.path;
}
