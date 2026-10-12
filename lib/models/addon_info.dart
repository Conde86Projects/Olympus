import 'package:player/models/addon_manifest.dart';

/// Estado operacional de um add-on instalado (spec 6.1). Disponivel
/// para atualizar NAO e estado: e a flag [AddonInfo.updateAvailable],
/// ortogonal (um estado exclusivo desativaria quem esta ativo ou
/// ativaria quem esta inativo ao detectar update).
enum AddonState { active, inactive, error }

/// Add-on instalado: manifesto + estado operacional. Imutavel; transicoes
/// de estado produzem copias via [copyWith].
class AddonInfo {
  const AddonInfo({
    required this.manifest,
    this.state = AddonState.inactive,
    this.originTrusted = false,
    required this.installedAt,
    this.updatedAt,
    this.diagnostic,
    this.updateAvailable = false,
    this.deferredVersion,
    this.approvedOrigin,
  });

  final AddonManifest manifest;
  final AddonState state;

  /// A origem era confiavel quando instalado. Origem nova instala
  /// desativada (spec 6.1); a confianca decide o comportamento padrao.
  final bool originTrusted;
  final DateTime installedAt;
  final DateTime? updatedAt;

  /// Motivo legivel quando [state] e [AddonState.error]. Nunca contem
  /// stack trace nem dados sensiveis.
  final String? diagnostic;

  /// Ha versao mais nova no updateUrl (detectado pelo check). Nao muda
  /// o funcionamento: ativo segue ativo, inativo segue inativo.
  final bool updateAvailable;

  /// Versao adiada pelo usuario: o check nao a oferece de novo (so uma
  /// versao AINDA mais nova reaparece).
  final String? deferredVersion;

  /// Host do feed aprovado explicitamente pelo usuario (5B, spec 6.1.1).
  /// Nulo quando o add-on nao tem feed ou veio de documento antigo
  /// (nesse caso, a primeira ativacao com feed pede aprovacao).
  final String? approvedOrigin;

  /// Verdadeiro quando o feed atual ainda nao foi aprovado: host
  /// diferente do aprovado (ou primeiro feed, aprovado nulo).
  bool get needsApproval =>
      _hostOf(manifest.catalogUrl) != approvedOrigin;

  static String? _hostOf(String? url) {
    if (url == null || url.isEmpty) return null;
    final host = Uri.tryParse(url)?.host ?? '';
    return host.isEmpty ? null : host.toLowerCase();
  }

  AddonInfo copyWith({
    AddonManifest? manifest,
    AddonState? state,
    bool? originTrusted,
    DateTime? Function()? updatedAt,
    String? Function()? diagnostic,
    bool? updateAvailable,
    String? Function()? deferredVersion,
    String? Function()? approvedOrigin,
  }) {
    return AddonInfo(
      manifest: manifest ?? this.manifest,
      state: state ?? this.state,
      originTrusted: originTrusted ?? this.originTrusted,
      installedAt: installedAt,
      updatedAt: updatedAt != null ? updatedAt() : this.updatedAt,
      diagnostic: diagnostic != null ? diagnostic() : this.diagnostic,
      updateAvailable: updateAvailable ?? this.updateAvailable,
      deferredVersion: deferredVersion != null
          ? deferredVersion()
          : this.deferredVersion,
      approvedOrigin:
          approvedOrigin != null ? approvedOrigin() : this.approvedOrigin,
    );
  }

  Map<String, Object?> toMap() => {
        'manifest': manifest.toMap(),
        'state': state.name,
        'originTrusted': originTrusted,
        'installedAt': installedAt.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'diagnostic': diagnostic,
        'updateAvailable': updateAvailable,
        'deferredVersion': deferredVersion,
        'approvedOrigin': approvedOrigin,
      };

  factory AddonInfo.fromMap(Map<String, Object?> map) {
    return AddonInfo(
      manifest: AddonManifest.fromMap(
          Map<String, Object?>.from(map['manifest']! as Map)),
      state: AddonState.values.byName(map['state']! as String),
      originTrusted: (map['originTrusted'] ?? false) as bool,
      installedAt: DateTime.parse(map['installedAt']! as String),
      updatedAt: map['updatedAt'] == null
          ? null
          : DateTime.parse(map['updatedAt']! as String),
      diagnostic: map['diagnostic'] as String?,
      updateAvailable: (map['updateAvailable'] ?? false) as bool,
      deferredVersion: map['deferredVersion'] as String?,
      approvedOrigin: map['approvedOrigin'] as String?,
    );
  }
}
