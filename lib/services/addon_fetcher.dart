import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:player/core/constants/app_constants.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/core/utils/internal_address.dart';
import 'package:player/core/utils/media_utils.dart';
import 'package:player/services/addon_package.dart';

/// Motivo de erro quando o usuário cancela um download (T3). É o
/// contrato do `cancel` do [fetchBytes]: completar cancela.
const fetchCancelledMessage = 'Download cancelado.';

/// Busca o corpo textual de um documento remoto (manifesto ou
/// repositorio). Contrato injetavel: a UI e os testes usam fakes, a
/// producao usa o [HttpAddonFetcher] (spec 24.13).
abstract class AddonFetcher {
  const AddonFetcher();

  /// Baixa e devolve o corpo como texto. Falhas (URL invalida,
  /// timeout, HTTP != 200, corpo grande demais, rede) viram
  /// [AddonError] com motivo em pt-BR. [headers] carrega
  /// autenticacao do adaptador (nunca logado).
  Future<String> fetchText(String url, {Map<String, String> headers = const {}});

  /// Baixa o corpo binário (pacote zip, T3), com progresso e
  /// cancelamento. Mesmas proteções do texto (SSRF, redirects
  /// revalidados). Concreto com recusa para os fakes antigos
  /// compilarem sem mudar; quem baixa de verdade sobrescreve.
  /// Completar [cancel] aborta a conexão e vira [fetchCancelledMessage].
  Future<Uint8List> fetchBytes(
    String url, {
    Map<String, String> headers = const {},
    void Function(int received, int? total)? onProgress,
    Future<void>? cancel,
  }) {
    throw UnimplementedError('fetchBytes não suportado neste buscador.');
  }
}

/// Implementacao sobre [HttpClient] (sem dependencia externa).
/// Aplica o timeout e o teto de tamanho de [AppConstants], bloqueia
/// alvos internos/privados (SSRF, 5C) e revalida cada salto de
/// redirect. [allowPrivate] existe so para os testes (servidor em
/// loopback); a producao usa o padrao seguro.
class HttpAddonFetcher extends AddonFetcher {
  const HttpAddonFetcher({
    this.timeout = AppConstants.addonFetchTimeout,
    this.maxBytes = AppConstants.maxManifestBytes,
    this.allowPrivate = false,
  });

  final Duration timeout;
  final int maxBytes;
  final bool allowPrivate;

  static const maxRedirects = 3;

  @override
  Future<String> fetchText(String url,
      {Map<String, String> headers = const {}}) async {
    if (!isSupportedUrl(url)) {
      throw const AddonError.fetchFailed(
        'Endereço inválido. Use um link http ou https.',
      );
    }
    try {
      final bytes = await _download(
        Uri.parse(url.trim()),
        headers,
        maxBytes,
        'O documento é grande demais (limite de 256 KB).',
      );
      try {
        return utf8.decode(bytes);
      } on FormatException {
        throw const AddonError.fetchFailed(
          'A resposta não é um texto válido.',
        );
      }
    } on AddonError {
      rethrow;
    } on TimeoutException {
      throw const AddonError.fetchFailed(
        'O endereço demorou demais a responder.',
      );
    } catch (_) {
      throw const AddonError.fetchFailed(
        'Não foi possível buscar o endereço. Verifique a conexão.',
      );
    }
  }

  /// Baixa o zip com teto de 10 MB (T3, sem temporário): os bytes
  /// ficam em memória até a prévia. Completar [cancel] aborta a
  /// conexão e vira [fetchCancelledMessage].
  @override
  Future<Uint8List> fetchBytes(
    String url, {
    Map<String, String> headers = const {},
    void Function(int received, int? total)? onProgress,
    Future<void>? cancel,
  }) async {
    if (!isSupportedUrl(url)) {
      throw const AddonError.fetchFailed(
        'Endereço inválido. Use um link http ou https.',
      );
    }
    try {
      final bytes = await _download(
        Uri.parse(url.trim()),
        headers,
        AddonPackageLimits.maxCompressedBytes,
        'O pacote é grande demais (limite de 10 MB).',
        onProgress: onProgress,
        cancel: cancel,
      );
      return Uint8List.fromList(bytes);
    } on AddonError {
      rethrow;
    } on TimeoutException {
      throw const AddonError.fetchFailed(
        'O endereço demorou demais a responder.',
      );
    } catch (_) {
      throw const AddonError.fetchFailed(
        'Não foi possível buscar o endereço. Verifique a conexão.',
      );
    }
  }

  /// Núcleo compartilhado (T3, sem duplicar o fetchText): SSRF por
  /// salto, auth só na origem, teto no cabeçalho e no stream,
  /// progresso e cancelamento. Devolve os bytes brutos.
  Future<List<int>> _download(
    Uri start,
    Map<String, String> headers,
    int limitBytes,
    String limitMessage, {
    void Function(int received, int? total)? onProgress,
    Future<void>? cancel,
  }) async {
    var current = start;
    final origin = '${current.scheme}://${current.host}:${current.port}';
    final client = HttpClient()..connectionTimeout = timeout;
    var cancelled = false;
    HttpClientRequest? active;
    if (cancel != null) {
      unawaited(cancel.then((_) {
        cancelled = true;
        active?.abort();
      }));
    }
    try {
      for (var hop = 0; hop <= maxRedirects; hop++) {
        if (cancelled) _throwCancelled();
        if (!allowPrivate) await _ensurePublic(current);
        final request = await client.getUrl(current).timeout(timeout);
        active = request;
        if (cancelled) _throwCancelled();
        // Redirect manual: o HttpClient seguiria sozinho para um alvo
        // interno sem revalidar.
        request.followRedirects = false;
        // Auth so na origem: redirect para outro host nao herda
        // cabecalhos (vazamento de credencial).
        if ('${current.scheme}://${current.host}:${current.port}' ==
            origin) {
          headers.forEach(request.headers.add);
        }
        final response = await request.close().timeout(timeout);
        if (_isRedirect(response.statusCode)) {
          final location =
              response.headers.value(HttpHeaders.locationHeader);
          await response.drain();
          if (hop == maxRedirects) {
            throw const AddonError.fetchFailed(
              'Redirecionamentos demais.',
            );
          }
          current = resolveFeedRedirect(current, location);
          continue;
        }
        if (response.statusCode != HttpStatus.ok) {
          throw AddonError.fetchFailed(
            'O endereço não respondeu (HTTP ${response.statusCode}).',
          );
        }
        if (response.contentLength > limitBytes) {
          throw AddonError.fetchFailed(limitMessage);
        }
        final buffer = <int>[];
        final total =
            response.contentLength >= 0 ? response.contentLength : null;
        await for (final chunk in response.timeout(timeout)) {
          if (cancelled) _throwCancelled();
          buffer.addAll(chunk);
          if (buffer.length > limitBytes) {
            throw AddonError.fetchFailed(limitMessage);
          }
          onProgress?.call(buffer.length, total);
        }
        return buffer;
      }
      throw const AddonError.fetchFailed('Redirecionamentos demais.');
    } on AddonError {
      rethrow;
    } on TimeoutException {
      if (cancelled) _throwCancelled();
      throw const AddonError.fetchFailed(
        'O endereço demorou demais a responder.',
      );
    } catch (_) {
      if (cancelled) _throwCancelled();
      throw const AddonError.fetchFailed(
        'Não foi possível buscar o endereço. Verifique a conexão.',
      );
    } finally {
      client.close(force: true);
    }
  }

  static bool _isRedirect(int status) =>
      status == HttpStatus.movedPermanently ||
      status == HttpStatus.found ||
      status == HttpStatus.seeOther ||
      status == HttpStatus.temporaryRedirect ||
      status == HttpStatus.permanentRedirect;

  /// Barreira SSRF: literal interno bloqueia sem DNS; nome resolve e
  /// bloqueia se QUALQUER endereco for interno (falha fechado em
  /// resposta mista). Falha de DNS vira erro de conexao.
  Future<void> _ensurePublic(Uri uri) async {
    final literal = InternetAddress.tryParse(uri.host);
    if (literal != null) {
      if (isBlockedInternetAddress(literal)) _throwBlocked();
      return;
    }
    List<InternetAddress> found;
    try {
      found = await InternetAddress.lookup(uri.host).timeout(timeout);
    } on TimeoutException {
      rethrow;
    } catch (_) {
      throw const AddonError.fetchFailed(
        'Não foi possível buscar o endereço. Verifique a conexão.',
      );
    }
    if (found.isEmpty ||
        found.any(isBlockedInternetAddress)) {
      _throwBlocked();
    }
  }

  Never _throwBlocked() => throw const AddonError.fetchFailed(
        'Endereço interno ou reservado. Use um endereço público.',
      );

  Never _throwCancelled() =>
      throw const AddonError.fetchFailed(fetchCancelledMessage);
}

/// Resolve o Location de um redirect contra a URL atual. Ausente,
/// relativo quebrado ou fora de http/https rejeita (falha fechado).
Uri resolveFeedRedirect(Uri current, String? location) {
  if (location == null || location.isEmpty) {
    throw const AddonError.fetchFailed(
      'Redirecionamento inválido.',
    );
  }
  final next = current.resolve(location);
  if ((next.scheme != 'http' && next.scheme != 'https') ||
      next.host.isEmpty) {
    throw const AddonError.fetchFailed(
      'Redirecionamento inválido.',
    );
  }
  return next;
}
