import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:player/app/tv_mode.dart';
import 'package:player/features/open_media/tv_file_browser_screen.dart';

/// Escolhe um vídeo local. Na TV usa o navegador próprio (o seletor do
/// sistema não abre no Google TV); no celular e no desktop, o seletor nativo.
/// Devolve o caminho ou null quando o usuário desiste.
Future<String?> pickVideoFile(
  BuildContext context, {
  required String title,
}) async {
  if (TvMode.of(context)) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const TvFileBrowserScreen()),
    );
  }
  final files = await FilePicker.pickFiles(
    type: FileType.video,
    dialogTitle: title,
  );
  return files.singleOrNull?.path;
}
