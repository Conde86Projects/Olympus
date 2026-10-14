import 'package:flutter/material.dart';
import 'package:player/core/utils/language_names.dart';
import 'package:player/widgets/app_shell.dart';

/// Seletor de idioma preferido (legendas ou áudio) sem campo de texto:
/// na TV física o IME come as setas com o campo focado e o D-pad
/// prende dentro do TextField (o DpadFieldExit nunca recebe o evento).
/// A lista navegável não prende nunca: seta desce/sobe, OK confirma,
/// voltar fecha sem alterar. Vale igual no desktop.
class LanguagePickerPage extends StatefulWidget {
  const LanguagePickerPage({
    super.key,
    required this.title,
    required this.current,
    required this.onSelected,
  });

  /// Título da página ("Idioma das legendas", "Idioma do áudio").
  final String title;

  /// Código atual (null/vazio = padrão do sistema).
  final String? current;

  /// Chamado com o código escolhido (null = padrão do sistema).
  final ValueChanged<String?> onSelected;

  @override
  State<LanguagePickerPage> createState() => _LanguagePickerPageState();
}

class _LanguagePickerPageState extends State<LanguagePickerPage> {
  /// Nó da opção atual: o foco é levado para ele na abertura de forma
  /// determinística (só o autofocus do ListTile perde a corrida quando
  /// a página abre por cima de uma linha já focada — o D-pad precisa
  /// nascer dentro da lista).
  final FocusNode _selectedFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _selectedFocus.canRequestFocus) {
        _selectedFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _selectedFocus.dispose();
    super.dispose();
  }

  bool _isCurrent(String? code) {
    final saved = widget.current?.trim();
    if (code == null) return saved == null || saved.isEmpty;
    return saved?.toLowerCase() == code;
  }

  void _select(String? code) => widget.onSelected(code);

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: widget.title,
      showBack: true,
      body: ListView(
        children: [
          _Option(
            label: 'Padrão do sistema',
            selected: _isCurrent(null),
            focusNode: _isCurrent(null) ? _selectedFocus : null,
            onTap: () => _select(null),
          ),
          for (final code in languagePickerCodes)
            _Option(
              label: languageDisplayName(code),
              code: code,
              selected: _isCurrent(code),
              focusNode: _isCurrent(code) ? _selectedFocus : null,
              onTap: () => _select(code),
            ),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.label,
    this.code,
    required this.selected,
    this.focusNode,
    required this.onTap,
  });

  final String label;
  final String? code;
  final bool selected;
  final FocusNode? focusNode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      focusNode: focusNode,
      autofocus: focusNode != null,
      title: Text(label),
      subtitle: code == null ? null : Text(code!),
      trailing: selected ? const Icon(Icons.check) : null,
      onTap: onTap,
    );
  }
}
