import 'package:flutter/material.dart';
import 'package:player/widgets/focusable_button.dart';

/// Diálogo de confirmação para ações destrutivas sobre mídias
/// (F3, Fase 4b). Mesmo padrão da remoção de add-ons: Cancelar
/// nasce focado (§26.6), então o OK imediato no D-pad cancela
/// com segurança em vez de destruir. Devolve true só quando o
/// usuário confirma explicitamente.
///
/// O Cancelar é também o visualmente primário (preenchido): na TV
/// o botão preenchido parecia "ativo" mesmo sem foco, e o usuário
/// apertava OK achando que confirmava quando na verdade cancelava.
/// Estilo agora acompanha foco e segurança.
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
        FocusableButton(
          label: 'Cancelar',
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        FocusableButton(
          label: confirmLabel,
          destructive: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
