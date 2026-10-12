import 'dart:convert';

import 'package:player/core/constants/app_constants.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/core/utils/media_utils.dart';

/// Manifesto de add-on (spec 4.1.1). Imutavel. O [fromMap] VALIDA a
/// entrada e lanca [AddonError] com motivo em pt-BR: manifestos chegam
/// de origens externas e nunca sao confiaveis por padrao.
class AddonManifest {
  /// Decodifica um manifesto a partir do texto JSON bruto (colado,
  /// arquivo ou corpo de resposta HTTP). Aplica o teto de tamanho
  /// antes de decodificar e delega o resto ao [fromMap].
  static AddonManifest parseJson(String raw) {
    if (raw.length > AppConstants.maxManifestBytes) {
      throw const AddonError.invalidManifest(
        'O manifesto é grande demais (limite de 256 KB).',
      );
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        throw const AddonError.invalidManifest(
          'O manifesto precisa ser um objeto JSON.',
        );
      }
      return AddonManifest.fromMap(decoded);
    } on AddonError {
      rethrow;
    } catch (_) {
      throw const AddonError.invalidManifest(
        'O manifesto não é um JSON válido.',
      );
    }
  }

  const AddonManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.author,
    required this.description,
    required this.icon,
    required this.homepage,
    required this.repository,
    required this.permissions,
    required this.supportedPlatforms,
    required this.contentTypes,
    this.updateUrl,
    this.catalogUrl,
    required this.legalNotice,
    this.changelog,
  });

  final String id;
  final String name;
  final String version;
  final String author;
  final String description;
  final String icon;
  final String homepage;
  final String repository;
  final List<String> permissions;
  final List<String> supportedPlatforms;
  final List<String> contentTypes;
  final String? updateUrl;

  /// Feed de catalogo remoto (Fase 5): envelope `{"items": [...]}`.
  /// Opcional; sem ele o add-on serve o catalogo embutido.
  final String? catalogUrl;
  final String legalNotice;

  /// Novidades desta versao, exibidas na tela de atualizacao. Opcional,
  /// texto livre com teto de tamanho.
  final String? changelog;

  /// Permissoes declaraveis, sempre explicitas (spec 4.1.1).
  static const knownPermissions = [
    'network.read',
    'account.login',
    'catalog.read',
    'playback.open',
    'metadata.read',
    'subtitle.read',
  ];

  static const knownPlatforms = ['windows', 'linux', 'macos', 'android'];

  static final _idPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');
  static final _versionPattern =
      RegExp(r'^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$');

  /// O manifesto declara suporte a [platform] (ex. "windows").
  bool supports(String platform) => supportedPlatforms.contains(platform);

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'version': version,
        'author': author,
        'description': description,
        'icon': icon,
        'homepage': homepage,
        'repository': repository,
        'permissions': permissions,
        'supportedPlatforms': supportedPlatforms,
        'contentTypes': contentTypes,
        'updateUrl': updateUrl,
        'catalogUrl': catalogUrl,
        'legalNotice': legalNotice,
        'changelog': changelog,
      };

  /// Tetos de tamanho: manifestos vem de fora e valores absurdos
  /// inchariam UI, logs e armazenamento. Nada legitimo chega perto.
  static const maxShortText = 512;
  static const maxLongText = 8000;
  static const maxUrl = 2048;
  static const maxListItems = 64;
  static const maxListItem = 128;

  factory AddonManifest.fromMap(Map<String, Object?> map) {
    String text(String key, String message, {int max = maxShortText}) {
      final value = map[key];
      if (value is! String || value.trim().isEmpty) {
        throw AddonError.invalidManifest(message);
      }
      if (value.length > max) {
        throw AddonError.invalidManifest(
            'Campo "$key" excede o tamanho máximo.');
      }
      return value;
    }

    List<String> strings(String key, String message) {
      final value = map[key];
      if (value is! List) throw AddonError.invalidManifest(message);
      if (value.length > maxListItems) {
        throw AddonError.invalidManifest(
            'Campo "$key" excede o tamanho máximo.');
      }
      final items = <String>[];
      for (final item in value) {
        if (item is! String || item.trim().isEmpty) {
          throw AddonError.invalidManifest(message);
        }
        if (item.length > maxListItem) {
          throw AddonError.invalidManifest(
              'Campo "$key" excede o tamanho máximo.');
        }
        items.add(item);
      }
      return List.unmodifiable(items);
    }

    final id = text('id', 'Identificador do add-on ausente ou inválido.');
    if (!_idPattern.hasMatch(id)) {
      throw const AddonError.invalidManifest(
          'Identificador do add-on inválido (use letras, números, ponto, hífen ou sublinhado).');
    }
    final version =
        text('version', 'Versão do add-on ausente (use o formato 1.2.3).');
    if (!_versionPattern.hasMatch(version)) {
      throw const AddonError.invalidManifest(
          'Versão do add-on inválida (use o formato 1.2.3).');
    }
    final permissions =
        strings('permissions', 'Lista de permissões do add-on inválida.');
    for (final permission in permissions) {
      if (!knownPermissions.contains(permission)) {
        throw AddonError.invalidManifest(
            'Permissão desconhecida: "$permission".');
      }
    }
    final platforms = strings('supportedPlatforms',
        'Lista de plataformas suportadas inválida.');
    if (platforms.isEmpty) {
      throw const AddonError.invalidManifest(
          'O add-on precisa declarar ao menos uma plataforma.');
    }
    for (final platform in platforms) {
      if (!knownPlatforms.contains(platform)) {
        throw AddonError.invalidManifest(
            'Plataforma desconhecida: "$platform".');
      }
    }
    final contentTypes = strings(
        'contentTypes', 'Lista de tipos de conteúdo inválida.');
    if (contentTypes.isEmpty) {
      throw const AddonError.invalidManifest(
          'O add-on precisa declarar ao menos um tipo de conteúdo.');
    }
    final rawUpdateUrl = map['updateUrl'];
    String? updateUrl;
    if (rawUpdateUrl != null) {
      if (rawUpdateUrl is! String) {
        throw const AddonError.invalidManifest(
            'Endereço de atualização inválido (use http/https).');
      }
      final trimmed = rawUpdateUrl.trim();
      if (trimmed.isNotEmpty) {
        if (trimmed.length > maxUrl || !isSupportedUrl(trimmed)) {
          throw AddonError.invalidManifest(
              trimmed.length > maxUrl
                  ? 'Campo "updateUrl" excede o tamanho máximo.'
                  : 'Endereço de atualização inválido (use http/https).');
        }
        updateUrl = trimmed;
      }
    }
    final rawCatalogUrl = map['catalogUrl'];
    String? catalogUrl;
    if (rawCatalogUrl != null) {
      if (rawCatalogUrl is! String) {
        throw const AddonError.invalidManifest(
            'Endereço de catálogo inválido (use http/https).');
      }
      final trimmed = rawCatalogUrl.trim();
      if (trimmed.isNotEmpty) {
        if (trimmed.length > maxUrl || !isSupportedUrl(trimmed)) {
          throw AddonError.invalidManifest(
              trimmed.length > maxUrl
                  ? 'Campo "catalogUrl" excede o tamanho máximo.'
                  : 'Endereço de catálogo inválido (use http/https).');
        }
        catalogUrl = trimmed;
      }
    }
    final rawChangelog = map['changelog'];
    String? changelog;
    if (rawChangelog != null) {
      if (rawChangelog is! String) {
        throw const AddonError.invalidManifest(
            'Campo "changelog" inválido.');
      }
      final trimmed = rawChangelog.trim();
      if (trimmed.isNotEmpty) {
        if (trimmed.length > maxLongText) {
          throw const AddonError.invalidManifest(
              'Campo "changelog" excede o tamanho máximo.');
        }
        changelog = trimmed;
      }
    }
    return AddonManifest(
      id: id,
      name: text('name', 'Nome do add-on ausente.'),
      version: version,
      author: text('author', 'Autor do add-on ausente.'),
      description: text('description', 'Descrição do add-on ausente.',
          max: maxLongText),
      icon: text('icon', 'Ícone do add-on ausente.'),
      homepage: text('homepage', 'Página do add-on ausente.'),
      repository: text('repository', 'Repositório de origem ausente.'),
      permissions: permissions,
      supportedPlatforms: platforms,
      contentTypes: contentTypes,
      updateUrl: updateUrl,
      catalogUrl: catalogUrl,
      legalNotice: text('legalNotice', 'Aviso legal do add-on ausente.',
          max: maxLongText),
      changelog: changelog,
    );
  }

  /// Copia com outro feed. Usado pela edicao de endereco (5B); a
  /// validacao da URL nova acontece no servico antes de chegar aqui.
  AddonManifest withCatalogUrl(String? catalogUrl) => AddonManifest(
        id: id,
        name: name,
        version: version,
        author: author,
        description: description,
        icon: icon,
        homepage: homepage,
        repository: repository,
        permissions: permissions,
        supportedPlatforms: supportedPlatforms,
        contentTypes: contentTypes,
        updateUrl: updateUrl,
        catalogUrl: catalogUrl,
        legalNotice: legalNotice,
        changelog: changelog,
      );

  /// Sintetiza o manifesto de um feed JSON direto (5B, spec 6.1.1):
  /// fonte de DADOS, sem codigo. Id derivado do host + hash da URL
  /// (a mesma URL sempre gera o mesmo id: duplicata e rejeitada na
  /// instalacao). [url] ja validada (http/https).
  factory AddonManifest.fromFeed({required String url, required int itemCount}) {
    final uri = Uri.parse(url);
    final host = uri.host.toLowerCase();
    final slug = host.replaceAll(RegExp('[^a-z0-9.-]'), '-');
    var hash = 5381;
    for (final unit in url.codeUnits) {
      hash = ((hash << 5) + hash + unit) & 0xFFFFFFFF;
    }
    final short = hash.toRadixString(16).padLeft(8, '0').substring(0, 6);
    return AddonManifest(
      id: 'feed.$slug-$short',
      name: 'Fonte $host',
      version: '1.0.0',
      author: host,
      description: 'Fonte de dados com $itemCount '
          '${itemCount == 1 ? 'item' : 'itens'} (feed JSON).',
      icon: 'rss_feed',
      homepage: '${uri.scheme}://$host',
      repository: url,
      permissions: const ['catalog.read', 'playback.open'],
      supportedPlatforms: const ['windows', 'linux', 'macos', 'android'],
      contentTypes: const ['video'],
      catalogUrl: url,
      legalNotice:
          'Fonte desconhecida adicionada pelo usuário. O aplicativo não '
          'verificou este conteúdo.',
    );
  }

  /// Compara versoes semver: negativo se [a] < [b], zero se iguais,
  /// positivo se [a] > [b]. Nucleos numericos, depois sufixo (versao
  /// sem sufixo e maior que com sufixo; sufixos em ordem lexica).
  static int compareVersions(String a, String b) {
    List<Object?> parts(String version) {
      final coreAndSuffix = version.split(RegExp('[-+]'));
      final numbers = coreAndSuffix.first.split('.');
      int numberAt(int index) => numbers.length > index
          ? int.tryParse(numbers[index]) ?? 0
          : 0;
      final suffix = version.contains(RegExp('[-+]'))
          ? version.substring(version.indexOf(RegExp('[-+]')) + 1)
          : null;
      return [numberAt(0), numberAt(1), numberAt(2), suffix];
    }

    final pa = parts(a);
    final pb = parts(b);
    for (var i = 0; i < 3; i++) {
      final diff = (pa[i] as int).compareTo(pb[i] as int);
      if (diff != 0) return diff;
    }
    final sa = pa[3] as String?;
    final sb = pb[3] as String?;
    if (sa == null && sb == null) return 0;
    if (sa == null) return 1;
    if (sb == null) return -1;
    return sa.compareTo(sb);
  }
}
