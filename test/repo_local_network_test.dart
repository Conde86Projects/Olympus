import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:player/core/errors/app_error.dart';
import 'package:player/core/storage/local_store.dart';
import 'package:player/services/addon_fetcher.dart';
import 'package:player/services/local_addon_service.dart';
import 'support/demo_addons.dart';

const _lan = 'http://192.168.1.2:8080/listagem.json';

/// Faz o papel do [HttpAddonFetcher] de produção: recusa rede interna, e só
/// o par devolvido por [allowingLocalNetwork] atende o endereço da casa.
class _StrictFetcher extends AddonFetcher {
  _StrictFetcher(this.open);

  final _OpenFetcher open;

  @override
  AddonFetcher get allowingLocalNetwork => open;

  @override
  Future<String> fetchText(String url,
      {Map<String, String> headers = const {}}) async {
    throw const AddonError.fetchFailed(
      'Endereço interno ou reservado. Use um endereço público.',
    );
  }
}

class _OpenFetcher extends AddonFetcher {
  final calls = <String>[];

  @override
  Future<String> fetchText(String url,
      {Map<String, String> headers = const {}}) async {
    calls.add(url);
    return jsonEncode({
      'addons': [demoManifestJson(id: 'casa.catalogo')],
    });
  }
}

void main() {
  late _OpenFetcher open;
  late LocalAddonService service;

  setUp(() {
    open = _OpenFetcher();
    service = LocalAddonService(
      InMemoryLocalStore(),
      fetcher: _StrictFetcher(open),
      allowUnknownSources: () => true,
    );
  });

  test('repositório confiável na rede local lista os add-ons', () async {
    final repo = await service.addRepository(
        name: 'Casa', originUrl: _lan, trusted: true);

    final listing = await service.fetchRepoAddons(repo.id);

    expect(listing.map((m) => m.id), ['casa.catalogo']);
    expect(open.calls, [_lan]);
  });

  test('repositório não confiável na rede local segue recusado', () async {
    final repo = await service.addRepository(
        name: 'Casa', originUrl: _lan, trusted: false);

    await expectLater(
      service.fetchRepoAddons(repo.id),
      throwsA(isA<AddonError>()
          .having((e) => e.message, 'mensagem', contains('interno'))),
    );
    expect(open.calls, isEmpty);
  });
}
