import 'dart:convert';

import 'package:player/core/errors/app_error.dart';
import 'package:player/core/utils/media_utils.dart';
import 'package:player/models/addon_manifest.dart';

/// Repositorio autorizado de add-ons (spec 6.1): nome, origem e estado
/// de confianca. Imutavel. A origem e validada como URL porque sera
/// buscada pela rede.
class AddonRepository {
  const AddonRepository({
    required this.id,
    required this.name,
    required this.originUrl,
    this.trusted = false,
    required this.addedAt,
  });

  final String id;
  final String name;
  final String originUrl;

  /// Repositorio confiavel. Origens digitadas comecam nao confiaveis;
  /// a confianca decide o comportamento padrao na instalacao.
  final bool trusted;
  final DateTime addedAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'originUrl': originUrl,
        'trusted': trusted,
        'addedAt': addedAt.toIso8601String(),
      };

  factory AddonRepository.fromMap(Map<String, Object?> map) {
    String text(String key, String message) {
      final value = map[key];
      if (value is! String || value.trim().isEmpty) {
        throw AddonError.invalidManifest(message);
      }
      if (value.length > AddonManifest.maxShortText) {
        throw AddonError.invalidManifest(
            'Campo "$key" excede o tamanho máximo.');
      }
      return value;
    }

    final originUrl =
        text('originUrl', 'Endereço do repositório ausente.');
    if (originUrl.length > AddonManifest.maxUrl ||
        !isSupportedUrl(originUrl)) {
      throw const AddonError.invalidManifest(
          'Endereço do repositório inválido (use http/https).');
    }
    return AddonRepository(
      id: text('id', 'Identificador do repositório ausente.'),
      name: text('name', 'Nome do repositório ausente.'),
      originUrl: originUrl,
      trusted: (map['trusted'] ?? false) as bool,
      addedAt: DateTime.parse(map['addedAt']! as String),
    );
  }

  /// Decodifica a listagem publicada por um repositorio:
  /// `{"addons": [<manifesto>, ...]}`. Estrita de proposito: um item
  /// invalido reprova a listagem inteira em vez de instalar metade
  /// certa e metade errada. O corpo ja passou pelo teto do fetcher.
  static List<AddonManifest> parseListing(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        throw const AddonError.invalidManifest(
          'O repositório retornou dados inválidos.',
        );
      }
      final items = decoded['addons'];
      if (items is! List) {
        throw const AddonError.invalidManifest(
          'O repositório retornou dados inválidos.',
        );
      }
      return items.map((entry) {
        if (entry is! Map<String, Object?>) {
          throw const AddonError.invalidManifest(
            'O repositório retornou dados inválidos.',
          );
        }
        return AddonManifest.fromMap(entry);
      }).toList();
    } on AddonError {
      rethrow;
    } catch (_) {
      throw const AddonError.invalidManifest(
        'O repositório retornou dados inválidos.',
      );
    }
  }
}
