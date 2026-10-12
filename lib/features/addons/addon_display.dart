import 'package:flutter/material.dart';
import 'package:player/models/addon_info.dart';

/// Rotulo em pt-BR para cada estado. Estado se mostra com icone + texto,
/// nunca so com cor.
String addonStateLabel(AddonState state) => switch (state) {
      AddonState.active => 'Ativo',
      AddonState.inactive => 'Inativo',
      AddonState.error => 'Erro',
    };

/// Icone para cada estado.
IconData addonStateIcon(AddonState state) => switch (state) {
      AddonState.active => Icons.check_circle_outline,
      AddonState.inactive => Icons.radio_button_unchecked,
      AddonState.error => Icons.error_outline,
    };

/// Descricao de cada permissao, mostrada antes de instalar e nos
/// detalhes (spec 6.1). Chaves cobrem [AddonManifest.knownPermissions].
const addonPermissionDescriptions = {
  'network.read': 'Acessar a rede',
  'account.login': 'Usar sua conta no serviço',
  'catalog.read': 'Ler catálogos',
  'playback.open': 'Abrir mídias para reprodução',
  'metadata.read': 'Ler metadados',
  'subtitle.read': 'Ler legendas',
};

/// Uma permissao como "chave — descricao" (revisao e detalhes).
String formatAddonPermission(String key) =>
    '$key — ${addonPermissionDescriptions[key] ?? 'permissão'}';
