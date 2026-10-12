import 'package:flutter/material.dart';

/// Diálogo de confirmação para ações destrutivas sobre mídias
/// (F3, Fase 4b). Mesmo padrão da remoção de add-ons: Cancelar
/// nasce focado (§26.6), então o OK imediato no D-pad cancela
/// com segurança em vez de destruir. Devolve true só quando o
/// usuário confirma explicitamente.
Future<bool> confirmDestructiveAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Remover',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
