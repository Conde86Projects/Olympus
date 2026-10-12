import 'package:flutter/foundation.dart';
import 'package:player/models/addon_catalog_item.dart';
import 'package:player/models/addon_info.dart';
import 'package:player/models/addon_manifest.dart';
import 'package:player/models/addon_repository.dart';
import 'package:player/models/media_item.dart';

/// Gerenciador de add-ons (spec 4.1.1, 6.1). A UI depende apenas deste
/// contrato. Implementacoes isolam falhas por add-on: um add-on com
/// defeito vira estado de erro com diagnostico, nunca excecao para a UI.
abstract class AddonService extends ChangeNotifier {
  /// Instalados, ordenados por nome.
  List<AddonInfo> get addons;

  AddonInfo? findById(String addonId);

  AddonState getStatus(String addonId);

  /// Valida um manifesto vindo de fora. Lanca [AddonError] com o motivo.
  Future<AddonManifest> validate(Map<String, Object?> json);

  /// Baixa e valida o manifesto de uma URL. Lanca [AddonError] com o
  /// motivo (rede ou manifesto).
  Future<AddonManifest> fetchManifest(String url);

  /// Instala sempre desativado (padrao seguro, spec 6.1). Rejeita id
  /// duplicado.
  Future<AddonInfo> install(
    AddonManifest manifest, {
    required bool originTrusted,
  });

  /// Ativa apos checar compatibilidade. Incompativel mantem desativado
  /// com o motivo no diagnostico (sem excecao).
  Future<void> enable(String addonId);

  Future<void> disable(String addonId);

  /// Remove somente os dados do add-on. Nunca toca midias (spec 6.1).
  Future<void> uninstall(String addonId);

  /// Apaga todos os add-ons, repositorios e a ultima alteracao.
  /// Diagnostico "limpar dados": nunca toca midias.
  Future<void> clearAllData();

  /// Verifica atualizacoes nos updateUrls instalados. Marca a flag por
  /// add-on (persiste) e devolve os manifestos mais novos, exceto os
  /// adiados. Falha de rede/manifesto pula o item sem falhar o check.
  Future<List<AddonManifest>> checkForUpdates();

  /// Aplica a versao do updateUrl apos validar identidade, novidade e
  /// compatibilidade. Guarda a anterior para rollback. Lanca
  /// [AddonError] com o motivo (rede, manifesto, incompatibilidade).
  Future<AddonInfo> update(String addonId);

  /// Adia a versao pendente: o check nao a oferece de novo (so uma
  /// versao ainda mais nova reaparece).
  Future<void> deferUpdate(String addonId);

  /// Volta ao manifesto anterior guardado pelo ultimo update.
  Future<AddonInfo> rollback(String addonId);

  /// Versao anterior guardada para rollback, ou null quando nao ha.
  String? previousVersion(String addonId);

  /// Catalogo do add-on. Add-on inativo devolve lista vazia; com defeito
  /// registra estado de erro e devolve lista vazia (isolamento, §26.14).
  Future<List<AddonCatalogItem>> getCatalog(String addonId);

  /// Busca no catalogo (case-insensitive em titulo e subtitulo). Busca
  /// em branco devolve lista vazia. Mesmo isolamento do catalogo.
  Future<List<AddonCatalogItem>> search(String addonId, String query);

  /// Resolve um item do catalogo para reproducao. Lanca [AddonError]
  /// controlado quando desativado ou com defeito (a UI mostra "fonte
  /// indisponivel", nunca uma tela travada).
  Future<MediaItem> resolvePlayback(String addonId, AddonCatalogItem item);

  /// Repositorios cadastrados, ordenados por nome.
  List<AddonRepository> get repositories;

  /// Cadastra um repositorio apos validar nome e endereco. Rejeita
  /// endereco duplicado.
  Future<AddonRepository> addRepository({
    required String name,
    required String originUrl,
    bool trusted = false,
  });

  /// Remove o cadastro. Nunca toca add-ons instalados nem midias.
  Future<void> removeRepository(String repositoryId);

  /// Lista os manifestos publicados por um repositorio. Falha de rede
  /// vira "fonte indisponivel"; listagem malformada vira erro de
  /// validacao. Lanca [AddonError] com o motivo.
  Future<List<AddonManifest>> fetchRepoAddons(String repositoryId);

  /// Previa de fonte por URL (5B, spec 6.1.1): baixa e detecta
  /// manifesto OU feed JSON direto (sintetiza o manifesto do feed).
  /// Nao salva nada. Lanca [AddonError]: URL invalida, rede ou corpo
  /// que nao e nem manifesto nem feed valido.
  Future<SourcePreview> previewSource(String url);

  /// Troca o feed de um add-on instalado (5B): valida a nova URL
  /// (http/https, rede, feed parseavel) ANTES de salvar. Mesma origem
  /// mantem estado e aprovacao; origem nova desativa e exige nova
  /// aprovacao ([AddonInfo.needsApproval]). Lanca [AddonError]
  /// com o motivo e nao salva nada.
  Future<AddonInfo> updateSourceUrl(String addonId, String newUrl);

  /// Aprova explicitamente a origem atual do feed (5B). Nao ativa:
  /// a ativacao continua manual. Sem feed, nao faz nada.
  Future<AddonInfo> approveSource(String addonId);

  /// Recarrega o feed agora e devolve a quantidade de itens validos
  /// (5B). Sem feed remoto, lanca [AddonError]. Falha isola a fonte
  /// e lanca o motivo.
  Future<int> refreshSource(String addonId);
}

/// Previa somente-leitura de uma fonte por URL: manifesto (real ou
/// sintetizado do feed) + amostra do catalogo para a revisao humana.
class SourcePreview {
  const SourcePreview({
    required this.manifest,
    required this.feedItemCount,
    this.feedSample = const [],
  });

  final AddonManifest manifest;

  /// Itens validos do feed, ou null quando a URL era um manifesto
  /// (catalogo ainda nao baixado).
  final int? feedItemCount;

  /// Primeiros titulos validos (no maximo 5), para a previa.
  final List<String> feedSample;
}

/// Paginacao sobre o contrato (Fase 5): extension para nao quebrar
/// implementadores (`implements` nao herda metodos concretos).
/// Paginas comecam em 1; fatia o catalogo cheio.
extension AddonServicePaging on AddonService {
  Future<AddonCatalogPage> getCatalogPage(
    String addonId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    return paginateCatalogItems(await getCatalog(addonId),
        page: page, pageSize: pageSize);
  }

  Future<AddonCatalogPage> searchPage(
    String addonId,
    String query, {
    int page = 1,
    int pageSize = 20,
  }) async {
    return paginateCatalogItems(await search(addonId, query),
        page: page, pageSize: pageSize);
  }
}
