import 'package:player/models/addon_catalog_item.dart';

/// Add-ons ficticios para demonstracao e testes (spec 23: testar com
/// add-on ficticio antes de integrar fontes reais). Nenhum executa codigo
/// nem acessa rede: sao manifestos e catalogos estaticos.
Map<String, Object?> demoManifestJson({
  String id = 'demo.catalogo',
  String version = '1.0.0',
}) =>
    {
      'id': id,
      'name': 'Catálogo Demo',
      'version': version,
      'author': 'Equipe Player',
      'description': 'Add-on fictício para demonstração e testes.',
      'icon': 'movie',
      'homepage': 'https://exemplo.com/demo',
      'repository': 'demo-repo',
      'permissions': ['catalog.read', 'playback.open'],
      'supportedPlatforms': ['windows', 'linux', 'macos', 'android'],
      'contentTypes': ['video'],
      'legalNotice': 'Demonstração sem conteúdo real.',
    };

/// Catalogo estatico servido a qualquer add-on ativo no prototipo. Na
/// Fase 6 cada add-on respondera pelo seu proprio catalogo.
List<AddonCatalogItem> demoCatalog() => const [
      AddonCatalogItem(
        id: 'aurora',
        title: 'Aurora Demo',
        subtitle: 'Curta de demonstração',
        sourceUrl: 'https://exemplo.com/demo/aurora.mp4',
        duration: Duration(minutes: 5),
      ),
      AddonCatalogItem(
        id: 'mare',
        title: 'Maré Demo',
        sourceUrl: 'https://exemplo.com/demo/mare.mp4',
        duration: Duration(minutes: 12),
      ),
    ];
