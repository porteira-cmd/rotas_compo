// ============================================================================
//  RotaCampo — Rota no mapa
//  Mostra as paradas numeradas e o CAMINHO REAL pelas estradas (OSRM).
//  Se não houver internet, mostra a linha reta como reserva.
//  Botão "Executar rota" leva pra execução (check-in + concluir).
//  Salve como: lib/rota_mapa_screen.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'main.dart'; // AppColors
import 'acoes.dart'; // abrirNavegacao, abrirRotaNoMaps, buscarRotaReal
import 'rota_execucao_screen.dart'; // executar

class RotaMapaScreen extends StatefulWidget {
  final List<Map<String, dynamic>> paradas;
  final dynamic rotaId; // se veio de "Minhas rotas", permite marcar como feita
  const RotaMapaScreen({super.key, required this.paradas, this.rotaId});

  @override
  State<RotaMapaScreen> createState() => _RotaMapaScreenState();
}

class _RotaMapaScreenState extends State<RotaMapaScreen> {
  List<LatLng> _pts = [];
  List<LatLng>? _caminhoReal; // linha pelas estradas (null = usa linha reta)
  bool _buscandoRota = true;
  bool _satelite = false; // visão de satélite

  @override
  void initState() {
    super.initState();
    _pts = widget.paradas
        .map((c) => LatLng((c['latitude'] as num).toDouble(), (c['longitude'] as num).toDouble()))
        .toList();
    _carregarCaminho();
  }

  Future<void> _carregarCaminho() async {
    final real = await buscarRotaReal(_pts);
    if (mounted) {
      setState(() {
        _caminhoReal = real;
        _buscandoRota = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final paradas = widget.paradas;
    final linha = _caminhoReal ?? _pts; // estradas, ou reta se falhar

    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.teal700, foregroundColor: Colors.white, title: const Text('Rota no mapa')),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: _pts.isNotEmpty ? _pts.first : const LatLng(-13.4, -41.5),
              initialZoom: 10,
              initialCameraFit: _pts.isNotEmpty
                  ? CameraFit.bounds(bounds: LatLngBounds.fromPoints(_pts), padding: const EdgeInsets.all(60))
                  : null,
              maxZoom: 18,
            ),
            children: [
              _satelite
                  ? TileLayer(
                      urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                      userAgentPackageName: 'com.rotacampo.app',
                    )
                  : TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.rotacampo.app',
                    ),
              if (linha.length >= 2)
                PolylineLayer(polylines: [Polyline(points: linha, strokeWidth: 4, color: _satelite ? AppColors.coral : AppColors.teal700)]),
              MarkerLayer(markers: [
                for (var i = 0; i < paradas.length; i++)
                  Marker(
                    point: _pts[i],
                    width: 42,
                    height: 42,
                    child: GestureDetector(
                      onTap: () => _mostrar(context, i, paradas[i], _pts[i]),
                      child: Container(
                        decoration: BoxDecoration(color: AppColors.teal700, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                        alignment: Alignment.center,
                        child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ),
              ]),
              RichAttributionWidget(attributions: [
                TextSourceAttribution(_satelite ? 'Esri, Maxar, Earthstar Geographics' : 'OpenStreetMap contributors'),
              ]),
            ],
          ),
          Positioned(top: 12, left: 12, child: _pill('${paradas.length} paradas')),
          Positioned(
            right: 12,
            top: 12,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 3,
              child: IconButton(
                tooltip: _satelite ? 'Ver mapa de ruas' : 'Ver satélite',
                icon: Icon(_satelite ? Icons.map_outlined : Icons.satellite_alt_outlined, color: AppColors.teal700),
                onPressed: () => setState(() => _satelite = !_satelite),
              ),
            ),
          ),
          if (_buscandoRota) Positioned(top: 56, left: 12, child: _pill('Traçando rota...')),
          if (!_buscandoRota && _caminhoReal == null) Positioned(top: 56, left: 12, child: _pill('Linha reta (sem internet)')),
          Positioned(
            left: 12, right: 12, bottom: 12,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => RotaExecucaoScreen(paradas: paradas, rotaId: widget.rotaId),
                  )),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Executar rota'),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.coral, padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => abrirRotaNoMaps(paradas.map((c) => [(c['latitude'] as num).toDouble(), (c['longitude'] as num).toDouble()]).toList()),
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('Abrir no Google Maps'),
                  style: OutlinedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.teal700, side: const BorderSide(color: AppColors.teal500), padding: const EdgeInsets.symmetric(vertical: 12)),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _pill(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.12), blurRadius: 8)]),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 13)),
      );

  void _mostrar(BuildContext context, int i, Map c, LatLng p) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Parada ${i + 1}: ${c['nome'] ?? ''}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
          if ((c['municipio'] as String?)?.isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text(c['municipio'], style: const TextStyle(color: AppColors.muted)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => abrirNavegacao(p.latitude, p.longitude),
              icon: const Icon(Icons.navigation_outlined, size: 18),
              label: const Text('Navegar até aqui'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.teal700),
            ),
          ),
        ]),
      ),
    );
  }
}