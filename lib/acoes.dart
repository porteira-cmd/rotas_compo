// ============================================================================
//  RotaCampo — Ações externas: WhatsApp e Navegação (Google Maps)
//  Precisa do pacote: flutter pub add url_launcher
//  Salve como: lib/acoes.dart
// ============================================================================

import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
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

// Busca a ROTA REAL pelas estradas (OSRM, gratuito, sem chave).
// Recebe os pontos na ordem das paradas e devolve a linha do caminho
// (vários pontos). Se der erro ou estiver sem internet, devolve null —
// aí o app desenha a linha reta como reserva.
Future<List<LatLng>?> buscarRotaReal(List<LatLng> paradas) async {
  if (paradas.length < 2) return null;
  try {
    // OSRM espera "longitude,latitude" separados por ponto-e-vírgula
    final coords = paradas.map((p) => '${p.longitude},${p.latitude}').join(';');
    final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/$coords?overview=full&geometries=geojson');
    final resp = await http.get(url, headers: {'User-Agent': 'RotaCampo/1.0'}).timeout(const Duration(seconds: 12));
    if (resp.statusCode != 200) return null;
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final rotas = data['routes'] as List?;
    if (rotas == null || rotas.isEmpty) return null;
    final linha = rotas.first['geometry']['coordinates'] as List;
    // GeoJSON vem como [lon, lat]; o flutter_map usa LatLng(lat, lon)
    return linha.map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
  } catch (_) {
    return null;
  }
}

// Garante que o GPS está ligado e com permissão. Devolve true se pode usar.
Future<bool> garantirPermissaoLocalizacao() async {
  if (!await Geolocator.isLocationServiceEnabled()) return false;
  var p = await Geolocator.checkPermission();
  if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
  if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return false;
  return true;
}

// Fluxo contínuo da localização do aparelho, já em LatLng (pro flutter_map).
// Atualiza a cada ~8 metros de deslocamento.
Stream<LatLng> fluxoLocalizacao() {
  const settings = LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 8);
  return Geolocator.getPositionStream(locationSettings: settings).map((p) => LatLng(p.latitude, p.longitude));
}

// Pega a posição atual uma única vez.
Future<LatLng?> posicaoAtual() async {
  try {
    if (!await garantirPermissaoLocalizacao()) return null;
    final p = await Geolocator.getCurrentPosition();
    return LatLng(p.latitude, p.longitude);
  } catch (_) {
    return null;
  }
}

// Mensagem padrão perguntando se o cliente quer a visita.
String mensagemVisita(String nomeCliente) =>
    'Olá $nomeCliente! Aqui é da Porteira Agrocomercial. '
    'Estamos programando uma visita técnica na sua região nos próximos dias. '
    'Você gostaria de receber a visita? Responda SIM ou NÃO. Obrigado!';