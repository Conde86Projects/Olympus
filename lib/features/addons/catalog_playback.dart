import 'dart:async';

import 'package:player/app/app.dart';
import 'package:player/models/addon_catalog_item.dart';
import 'package:player/models/media_item.dart';
import 'package:player/services/thumbnail_service.dart';

/// Fluxo único para tocar um item de catálogo (tela da fonte e fileiras
/// do Início): resolve pelo add-on, guarda na biblioteca e devolve o
/// item salvo para o player. Lança [AddonError] quando o add-on recusa.
Future<MediaItem> prepareCatalogItem(
  AppDependencies dependencies,
  String addonId,
  AddonCatalogItem item,
) async {
  final media = await dependencies.addonService.resolvePlayback(addonId, item);
  final saved = await dependencies.libraryService.upsert(media);
  unawaited(ThumbnailService.backfill(dependencies.libraryService, saved));
  return saved;
}
