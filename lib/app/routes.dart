/// Nomes de rota (mapa geral de navegacao, spec 6). Arquivo separado para
/// que telas e o roteador compartilhem as rotas sem import circular.
abstract final class AppRoutes {
  static const home = '/';
  static const player = '/player';
  static const library = '/library';
  static const favorites = '/favorites';
  static const history = '/history';
  static const settings = '/settings';
  static const openMedia = '/open';
  static const onboarding = '/onboarding';
  static const addons = '/addons';
  static const addonDetails = '/addons/details';
  static const addonInstall = '/addons/install';
  static const addonRepos = '/addons/repos';
  static const addonUpdates = '/addons/updates';
  static const diagnostics = '/diagnostics';
}
