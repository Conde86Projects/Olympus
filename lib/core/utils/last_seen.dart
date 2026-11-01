const _meses = [
  'jan.',
  'fev.',
  'mar.',
  'abr.',
  'mai.',
  'jun.',
  'jul.',
  'ago.',
  'set.',
  'out.',
  'nov.',
  'dez.',
];

/// Texto do último acesso do cartão: "Visto hoje", "Visto ontem" ou
/// "Visto em 3 de dez." (com o ano quando é de outro ano). Sem data
/// (nunca tocou), devolve null. "Ontem" segue o dia do calendário, não
/// 24 horas. Pura: recebe [now] para ser testável sem relógio.
String? lastSeenLabel(DateTime? lastPlayedAt, DateTime now) {
  if (lastPlayedAt == null) return null;
  final day = DateTime(lastPlayedAt.year, lastPlayedAt.month, lastPlayedAt.day);
  final today = DateTime(now.year, now.month, now.day);
  // Diferença em dias de calendário (arredonda por causa do horário de verão).
  final diff = (today.difference(day).inHours / 24).round();
  if (diff == 0) return 'Visto hoje';
  if (diff == 1) return 'Visto ontem';
  final base = 'Visto em ${day.day} de ${_meses[day.month - 1]}';
  return day.year == today.year ? base : '$base de ${day.year}';
}
