import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:player/core/constants/app_constants.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/core/utils/media_utils.dart';

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
    var current = Uri.parse(url.trim());
    final origin = '${current.scheme}://${current.host}:${current.port}';
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      for (var hop = 0; hop <= maxRedirects; hop++) {
        if (!allowPrivate) await _ensurePublic(current);
        final request = await client.getUrl(current).timeout(timeout);
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
        if (response.contentLength > maxBytes) {
          throw const AddonError.fetchFailed(
            'O documento é grande demais (limite de 256 KB).',
          );
        }
        final buffer = <int>[];
        await for (final chunk in response.timeout(timeout)) {
          buffer.addAll(chunk);
          if (buffer.length > maxBytes) {
            throw const AddonError.fetchFailed(
              'O documento é grande demais (limite de 256 KB).',
            );
          }
        }
        return utf8.decode(buffer);
      }
      throw const AddonError.fetchFailed('Redirecionamentos demais.');
    } on AddonError {
      rethrow;
    } on FormatException {
      throw const AddonError.fetchFailed(
        'A resposta não é um texto válido.',
      );
    } on TimeoutException {
      throw const AddonError.fetchFailed(
        'O endereço demorou demais a responder.',
      );
    } catch (_) {
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
}

/// Verdadeiro para loopback, link-local, multicast, redes privadas
/// (10/8, 172.16/12, 192.168/16), ULA (fc00::/7), zerados e formato
/// desconhecido. Exposto para teste; a decisao de bloqueio mora aqui.
bool isBlockedInternetAddress(InternetAddress address) {
  if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
    return true;
  }
  bool blockedV4(List<int> v4) {
    if (v4[0] == 10) return true;
    if (v4[0] == 172 && v4[1] >= 16 && v4[1] <= 31) return true;
    if (v4[0] == 192 && v4[1] == 168) return true;
    if (v4[0] == 127) return true;
    return v4.every((b) => b == 0);
  }

  final raw = address.rawAddress;
  if (raw.length == 4) return blockedV4(raw);
  if (raw.length == 16) {
    if ((raw[0] & 0xFE) == 0xFC) return true;
    if (raw.every((b) => b == 0)) return true;
    // IPv4 mapeado (::ffff:a.b.c.d): vale o v4 embutido.
    var mapped = raw[10] == 0xFF && raw[11] == 0xFF;
    for (var i = 0; i < 10 && mapped; i++) {
      if (raw[i] != 0) mapped = false;
    }
    if (mapped) return blockedV4(raw.sublist(12));
    return false;
  }
  return true;
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
