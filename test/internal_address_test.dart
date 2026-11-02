import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/core/utils/internal_address.dart';
import 'package:player/models/addon_catalog_item.dart';

Map<String, Object?> item({String? source, String? poster}) => {
      'id': 'v1',
      'title': 'Vídeo',
      'sourceUrl': source ?? 'https://cdn.exemplo.org/v.mp4',
      if (poster != null) 'thumbnailUrl': poster,
    };

void main() {
  group('faixa 100.64.0.0/10', () {
    test('dentro é interna; fora, pública', () {
      for (final ip in ['100.64.0.1', '100.100.100.100', '100.127.255.255']) {
        expect(isBlockedInternetAddress(InternetAddress(ip)), isTrue, reason: ip);
      }
      for (final ip in ['100.63.255.255', '100.128.0.1']) {
        expect(isBlockedInternetAddress(InternetAddress(ip)), isFalse, reason: ip);
      }
    });
  });

  group('endereço interno direto na URL', () {
    test('reconhece IP interno e localhost', () {
      for (final url in [
        'http://192.168.0.1/admin',
        'http://10.0.0.5:8080/x.jpg',
        'http://127.0.0.1/x',
        'http://[::1]/x',
        'http://localhost/x',
        'http://roteador.localhost/x',
        'http://100.64.0.1/x',
      ]) {
        expect(pointsToInternalAddress(url), isTrue, reason: url);
      }
    });

    test('deixa passar endereço público e nome comum', () {
      for (final url in [
        'https://cdn.exemplo.org/x.jpg',
        'http://8.8.8.8/x',
        'https://localhost.exemplo.org/x',
      ]) {
        expect(pointsToInternalAddress(url), isFalse, reason: url);
      }
    });
  });

  group('item de catálogo vindo de fora', () {
    test('recusa pôster na rede interna', () {
      expect(
        () => AddonCatalogItem.fromJson(item(poster: 'http://192.168.0.1/a.png')),
        throwsA(isA<AddonError>()),
      );
    });

    test('recusa vídeo na rede interna', () {
      expect(
        () => AddonCatalogItem.fromJson(item(source: 'http://10.0.0.5/v.mp4')),
        throwsA(isA<AddonError>()),
      );
    });

    test('aceita endereços públicos', () {
      final parsed = AddonCatalogItem.fromJson(
          item(poster: 'https://cdn.exemplo.org/a.png'));
      expect(parsed.thumbnailUrl, 'https://cdn.exemplo.org/a.png');
    });
  });
}
