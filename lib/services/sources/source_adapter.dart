import 'package:player/models/addon_catalog_item.dart';
import 'package:player/models/addon_manifest.dart';
import 'package:player/services/sources/source_credentials.dart';

/// Adaptador de fonte remota (5C): traduz O formato de UMA fonte
/// especifica para o contrato do app. Cada fonte real ganha seu
/// arquivo em `lib/services/sources/`; o [AddonService] nao muda.
///
/// Regras duras (spec 6.1.1 + hardening):
/// - o adaptador e codigo revisado que VEM NO APP: feed e dado, nunca
///   codigo; nada que a fonte envie e interpretado como logica;
/// - parse estrito na borda: [parseCatalog] lanca [AddonError] com
///   motivo, nunca devolve item pela metade;
/// - segredos so via [SourceCredentialStore] (nunca em URL, log ou
///   manifesto); cabecalhos saem de [headersFor].
abstract class SourceAdapter {
  const SourceAdapter();

  /// Identificador estavel do adaptador (ex. "demo.feed").
  String get id;

  /// Verdadeiro quando este adaptador entende a URL (host/padrao).
  bool canHandle(Uri uri);

  /// Cabecalhos da requisicao, incluindo autenticacao lida do
  /// [credentials]. Sem segredo configurado e sem auth opcional,
  /// devolve mapa vazio. Nunca loga valores.
  Future<Map<String, String>> headersFor(
    Uri uri,
    SourceCredentialStore credentials,
  );

  /// Converte o corpo bruto no envelope do app. Itens invalidos sao
  /// pulados (spec 6.1.1); corpo fora do formato lanca [AddonError].
  SourceCatalogPage parseCatalog(String body);

  /// Manifesto da fonte para a revisao humana (instalacao por URL).
  /// [itemCount] e a contagem valida observada na previa.
  AddonManifest manifestFor(String url, int itemCount);

  /// URL da pagina N (1-based) da fonte, ou null quando a fonte nao
  /// pagina no servidor (o app fatia localmente).
  Uri? pageUrl(Uri base, int page) => null;

  /// URL de busca no servidor, ou null quando a fonte nao busca
  /// (o app filtra localmente).
  Uri? searchUrl(Uri base, String query) => null;
}

/// Pagina ja convertida: itens validos + se ha mais no servidor.
class SourceCatalogPage {
  const SourceCatalogPage({required this.items, this.hasMore = false});

  final List<AddonCatalogItem> items;
  final bool hasMore;
}

/// Registro puro (testavel): primeiro adaptador que entende a URL
/// vence; nenhum = formato generico `{"items": [...]}` do app.
class SourceAdapters {
  const SourceAdapters._();

  static SourceAdapter? forUrl(String url, List<SourceAdapter> adapters) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host.isEmpty) return null;
    for (final adapter in adapters) {
      if (adapter.canHandle(uri)) return adapter;
    }
    return null;
  }
}
