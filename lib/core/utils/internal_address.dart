import 'dart:io';

/// Verdadeiro para loopback, link-local, multicast, redes privadas
/// (10/8, 172.16/12, 192.168/16, CGNAT 100.64/10), ULA (fc00::/7), zerados e formato
/// desconhecido. Exposto para teste; a decisao de bloqueio mora aqui.
bool isBlockedInternetAddress(InternetAddress address) {
  if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
    return true;
  }
  bool blockedV4(List<int> v4) {
    if (v4[0] == 10) return true;
    if (v4[0] == 100 && v4[1] >= 64 && v4[1] <= 127) return true;
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

/// A URL aponta direto para a rede interna: IP interno escrito no endereço
/// ou `localhost`. Serve para o que um feed manda o aparelho abrir sozinho
/// (pôster, vídeo). Nome comum precisaria de DNS: fica para quem baixa.
bool pointsToInternalAddress(String url) {
  var host = Uri.tryParse(url.trim())?.host.toLowerCase();
  if (host == null || host.isEmpty) return false;
  if (host.endsWith('.')) host = host.substring(0, host.length - 1);
  if (host == 'localhost' || host.endsWith('.localhost')) return true;
  final literal = InternetAddress.tryParse(host);
  if (literal != null) return isBlockedInternetAddress(literal);
  // `2130706433`, `127.1` e `0x7f.0.0.1` não são IP para o Dart, mas o
  // sistema os resolve como tal: host só de números é bloqueado.
  return host
      .split('.')
      .every((part) => RegExp(r'^(0x[0-9a-f]+|[0-9]+)$').hasMatch(part));
}
