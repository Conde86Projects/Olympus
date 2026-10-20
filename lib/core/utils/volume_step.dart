/// Passo do ajuste de volume dentro do app (5%).
const volumeStep = 0.05;

/// Volume depois de um passo: arredondado ao passo (sem 0,3499999) e
/// limitado a 0.0–1.0.
double steppedVolume(double current, int direction) {
  final raw = current + direction * volumeStep;
  final snapped = (raw / volumeStep).round() * volumeStep;
  return (double.parse(snapped.toStringAsFixed(2))).clamp(0.0, 1.0);
}
