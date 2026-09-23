// ============================================================================
//  RotaCampo — Ações externas: WhatsApp e Navegação (Google Maps)
//  Precisa do pacote: flutter pub add url_launcher
//  Salve como: lib/acoes.dart
// ============================================================================

import 'package:url_launcher/url_launcher.dart';

// Deixa só os números do telefone
String _soDigitos(String t) => t.replaceAll(RegExp(r'\D'), '');

// Abre a conversa do WhatsApp com a mensagem já escrita.
// Retorna false se não tiver telefone.
Future<bool> abrirWhatsApp(String? telefone, String mensagem) async {
  var fone = _soDigitos(telefone ?? '');
  if (fone.isEmpty) return false;
  // Adiciona o código do Brasil (55) se não tiver
  if (!fone.startsWith('55')) fone = '55$fone';
  final url = Uri.parse('https://wa.me/$fone?text=${Uri.encodeComponent(mensagem)}');
  return launchUrl(url, mode: LaunchMode.externalApplication);
}

// Abre o Google Maps com a ROTA (navegação) até o ponto — tipo Uber/99.
Future<bool> abrirNavegacao(double lat, double lng) async {
  final url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
  return launchUrl(url, mode: LaunchMode.externalApplication);
}

// Abre o Google Maps com a ROTA INTEIRA (várias paradas, na ordem).
// pontos = lista de [latitude, longitude]. A saída é da sua localização atual.
// Obs.: o Google Maps grátis aceita ~9 paradas intermediárias.
Future<bool> abrirRotaNoMaps(List<List<double>> pontos) async {
  if (pontos.isEmpty) return false;
  final destino = pontos.last;
  final meio = pontos.sublist(0, pontos.length - 1); // paradas antes do destino
  final params = <String, String>{
    'api': '1',
    'destination': '${destino[0]},${destino[1]}',
    'travelmode': 'driving',
    if (meio.isNotEmpty) 'waypoints': meio.map((p) => '${p[0]},${p[1]}').join('|'),
  };
  final url = Uri.https('www.google.com', '/maps/dir/', params);
  return launchUrl(url, mode: LaunchMode.externalApplication);
}

// Mensagem padrão perguntando se o cliente quer a visita.
String mensagemVisita(String nomeCliente) =>
    'Olá $nomeCliente! Aqui é da Porteira Agrocomercial. '
    'Estamos programando uma visita técnica na sua região nos próximos dias. '
    'Você gostaria de receber a visita? Responda SIM ou NÃO. Obrigado!';