// ============================================================================
//  RotaCampo — Tela de Mapa (completa)
//  Clientes + Lojas + Municípios + Áreas de atuação + Rotas + Edição
//  OpenStreetMap (grátis) via flutter_map, lendo do Supabase.
//
//  Pacotes: flutter pub add flutter_map latlong2
//  Precisa também do arquivo: lib/mapa_dados.dart
//  Salve como: lib/mapa_screen.dart
// ============================================================================

import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'main.dart'; // supabase, AppColors, UserRole
import 'mapa_dados.dart'; // lojas, municípios, áreas, divisa
import 'rota_execucao_screen.dart'; // executar rota (check-in + prescrição)
import 'acoes.dart'; // WhatsApp e navegação
import 'avisar_clientes.dart'; // avisar clientes via WhatsApp

class MapaScreen extends StatefulWidget {
  final UserRole role;
  const MapaScreen({super.key, required this.role});

  @override
  State<MapaScreen> createState() => _MapaScreenState();
}

class _MapaScreenState extends State<MapaScreen> {
  List<Map<String, dynamic>> _clientes = [];
  final List<Map<String, dynamic>> _rota = [];
  bool _carregando = true;
  String? _erro;

  // Ligar/desligar camadas
  bool _verMunicipios = true;
  bool _verAreas = true;
  bool _verLojas = true;
  bool _satelite = false; // false = mapa normal | true = satélite

  // Regra dos 15 dias
  Set<dynamic> _visitados = {}; // ids de clientes visitados nos últimos 15 dias
  bool _esconderVisitados = false;

  // Desenhos geográficos (montados uma vez)
  final List<Polygon> _polMunicipios = [];
  final List<Marker> _rotMunicipios = [];
  final List<Polygon> _polAreas = [];
  final List<Marker> _rotAreas = [];
  final List<Polyline> _divisa = [];
  final List<Marker> _lojas = [];

  @override
  void initState() {
    super.initState();
    _prepararGeo();
    _carregar();
  }

  // ---------- helpers geográficos ----------
  List<LatLng> _anel(List coords) => coords
      .map<LatLng>((p) => LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()))
      .toList();

  Color _hex(String h) => Color(int.parse('FF${h.replaceAll('#', '')}', radix: 16));

  void _prepararGeo() {
    // Municípios (divisão das cidades)
    for (final f in (jsonDecode(municipiosJson)['features'] as List)) {
      final cor = _hex(f['properties']['color']);
      _polMunicipios.add(Polygon(
        points: _anel(f['geometry']['coordinates'][0]),
        color: cor.withOpacity(.10),
        borderColor: cor,
        borderStrokeWidth: 1.2,
      ));
      _rotMunicipios.add(_rotulo(f['properties']['name'],
          (f['properties']['ly'] as num).toDouble(), (f['properties']['lx'] as num).toDouble(), cor));
    }
    // Áreas de atuação (Piatã / Barra da Estiva)
    for (final f in (jsonDecode(areasJson)['features'] as List)) {
      final cor = _hex(f['properties']['color']);
      _polAreas.add(Polygon(
        points: _anel(f['geometry']['coordinates'][0]),
        color: cor.withOpacity(.08),
        borderColor: cor,
        borderStrokeWidth: 3,
      ));
      _rotAreas.add(_rotulo(f['properties']['loja'],
          (f['properties']['ly'] as num).toDouble(), (f['properties']['lx'] as num).toDouble(), cor,
          forte: true));
    }
    // Divisa entre as áreas
    for (final f in (jsonDecode(divisaJson)['features'] as List)) {
      _divisa.add(Polyline(
        points: _anel(f['geometry']['coordinates']),
        color: const Color(0xFFEA580C),
        strokeWidth: 3,
      ));
    }
    // Lojas
    for (final s in (jsonDecode(lojasJson) as List)) {
      _lojas.add(Marker(
        point: LatLng((s['lat'] as num).toDouble(), (s['lng'] as num).toDouble()),
        width: 40,
        height: 40,
        child: GestureDetector(
          onTap: () => _abrirLoja(s),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.teal900,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(Icons.store, color: Colors.white, size: 20),
          ),
        ),
      ));
    }
  }

  Marker _rotulo(String txt, double lat, double lng, Color cor, {bool forte = false}) => Marker(
        point: LatLng(lat, lng),
        width: 140,
        height: 26,
        child: IgnorePointer(
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: forte ? cor : Colors.white.withOpacity(.85),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(txt,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: forte ? 12 : 10,
                      fontWeight: FontWeight.w700,
                      color: forte ? Colors.white : cor)),
            ),
          ),
        ),
      );

  // ---------- dados do banco ----------
  Future<void> _carregar() async {
    try {
      final data = await supabase
          .from('clientes')
          .select('id, nome, telefone, endereco, municipio, latitude, longitude')
          .not('latitude', 'is', null)
          .not('longitude', 'is', null);
      setState(() {
        _clientes = List<Map<String, dynamic>>.from(data);
        _carregando = false;
      });
      await _carregarVisitados();
    } catch (e) {
      setState(() {
        _erro = '$e';
        _carregando = false;
      });
    }
  }

  // Quem foi visitado (check-in) nos últimos 15 dias
  Future<void> _carregarVisitados() async {
    try {
      final limite = DateTime.now().subtract(const Duration(days: 15)).toIso8601String();
      final data = await supabase.from('checkins').select('cliente_id').gte('feito_em', limite);
      setState(() {
        _visitados = (data as List).map((r) => r['cliente_id']).toSet();
      });
    } catch (_) {
      // Sem permissão de ver check-ins (ex.: vendedor) — segue sem marcar
    }
  }

  double _lat(Map c) => (c['latitude'] as num).toDouble();
  double _lng(Map c) => (c['longitude'] as num).toDouble();

  double _dist(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final s = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(a.latitude * math.pi / 180) *
            math.cos(b.latitude * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(s), math.sqrt(1 - s));
  }

  double get _kmTotal {
    double t = 0;
    for (var i = 0; i < _rota.length - 1; i++) {
      t += _dist(LatLng(_lat(_rota[i]), _lng(_rota[i])), LatLng(_lat(_rota[i + 1]), _lng(_rota[i + 1])));
    }
    return t;
  }

  bool _naRota(Map c) => _rota.any((r) => r['id'] == c['id']);
  void _alternarRota(Map<String, dynamic> c) => setState(() {
        _naRota(c) ? _rota.removeWhere((r) => r['id'] == c['id']) : _rota.add(c);
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.teal700,
        foregroundColor: Colors.white,
        title: const Text('Mapa de clientes'),
        actions: [
          IconButton(icon: const Icon(Icons.layers_outlined), tooltip: 'Camadas', onPressed: _abrirCamadas),
          if (_rota.isNotEmpty)
            IconButton(icon: const Icon(Icons.clear_all), tooltip: 'Limpar rota', onPressed: () => setState(_rota.clear)),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator(color: AppColors.teal500))
          : _erro != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Não foi possível abrir o mapa.\n$_erro', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFC23A2B)))))
              : _buildMapa(),
    );
  }

  Widget _buildMapa() {
    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(initialCenter: LatLng(-13.4, -41.5), initialZoom: 8.5, maxZoom: 18),
          children: [
            // Camada base: satélite (Esri) ou mapa normal (OpenStreetMap)
            _satelite
                ? TileLayer(
                    urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                    userAgentPackageName: 'com.rotacampo.app',
                  )
                : TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.rotacampo.app',
                  ),
            if (_verAreas) PolygonLayer(polygons: _polAreas),
            if (_verMunicipios) PolygonLayer(polygons: _polMunicipios),
            if (_verAreas) PolylineLayer(polylines: _divisa),
            if (_rota.length >= 2)
              PolylineLayer(polylines: [
                Polyline(points: _rota.map((c) => LatLng(_lat(c), _lng(c))).toList(), strokeWidth: 4, color: AppColors.teal700),
              ]),
            MarkerLayer(markers: _marcadoresClientes()),
            if (_verLojas) MarkerLayer(markers: _lojas),
            if (_verMunicipios) MarkerLayer(markers: _rotMunicipios),
            if (_verAreas) MarkerLayer(markers: _rotAreas),
            RichAttributionWidget(attributions: [
              TextSourceAttribution(_satelite ? 'Esri World Imagery' : 'OpenStreetMap contributors'),
            ]),
          ],
        ),
        Positioned(top: 12, left: 12, child: _pill('${_clientes.length} clientes')),
        if (_rota.isNotEmpty) Positioned(left: 12, right: 12, bottom: 12, child: _painelRota()),
      ],
    );
  }

  // Monta a lista de pinos, respeitando o filtro dos 15 dias
  List<Marker> _marcadoresClientes() {
    final lista = <Marker>[];
    for (final c in _clientes) {
      final visitado = _visitados.contains(c['id']);
      if (_esconderVisitados && visitado && !_naRota(c)) continue; // some por 15 dias
      lista.add(_marcadorCliente(c, visitado));
    }
    return lista;
  }

  Marker _marcadorCliente(Map<String, dynamic> c, bool visitado) {
    final emRota = _naRota(c);
    final ordem = _rota.indexWhere((r) => r['id'] == c['id']) + 1;
    Widget pino;
    if (emRota) {
      pino = Container(
          decoration: BoxDecoration(color: AppColors.teal700, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
          alignment: Alignment.center,
          child: Text('$ordem', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)));
    } else if (visitado) {
      pino = const Icon(Icons.check_circle, color: Color(0xFF2E7D5B), size: 30); // verde = visitado (15 dias)
    } else {
      pino = const Icon(Icons.location_on, color: AppColors.coral, size: 34);
    }
    return Marker(
      point: LatLng(_lat(c), _lng(c)),
      width: 44,
      height: 44,
      child: GestureDetector(onTap: () => _abrirDetalhes(c), child: pino),
    );
  }

  Widget _pill(String texto) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.12), blurRadius: 8)]),
        child: Text(texto, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 13)),
      );

  Widget _painelRota() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.15), blurRadius: 12)]),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Icon(Icons.route, color: AppColors.teal700),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Rota: ${_rota.length} paradas', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                Text('${_kmTotal.toStringAsFixed(1)} km no total', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              ]),
            ),
            TextButton(onPressed: () => setState(_rota.clear), child: const Text('Limpar', style: TextStyle(color: AppColors.coral, fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => RotaExecucaoScreen(paradas: List.from(_rota))),
                  );
                  await _carregarVisitados();
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text('Iniciar'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.teal700, padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => abrirRotaNoMaps(_rota.map((c) => [_lat(c), _lng(c)]).toList()),
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('No Maps'),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.teal700, side: const BorderSide(color: AppColors.teal500), padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => mostrarAvisarClientes(context, _rota),
              icon: const Icon(Icons.chat, size: 18),
              label: const Text('Avisar clientes no WhatsApp'),
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF128C7E), side: const BorderSide(color: Color(0xFF128C7E)), padding: const EdgeInsets.symmetric(vertical: 12)),
            ),
          ),
        ]),
      );

  // ---------- painel de camadas ----------
  void _abrirCamadas() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('Camadas do mapa', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            SwitchListTile(
              activeColor: AppColors.teal500,
              secondary: const Icon(Icons.satellite_alt_outlined),
              title: const Text('Visão de satélite'),
              value: _satelite,
              onChanged: (v) { setState(() => _satelite = v); setSheet(() {}); },
            ),
            const Divider(height: 1),
            SwitchListTile(
              activeColor: AppColors.teal500,
              title: const Text('Municípios (divisão das cidades)'),
              value: _verMunicipios,
              onChanged: (v) { setState(() => _verMunicipios = v); setSheet(() {}); },
            ),
            SwitchListTile(
              activeColor: AppColors.teal500,
              title: const Text('Áreas de atuação (Piatã / Barra)'),
              value: _verAreas,
              onChanged: (v) { setState(() => _verAreas = v); setSheet(() {}); },
            ),
            SwitchListTile(
              activeColor: AppColors.teal500,
              title: const Text('Lojas da Porteira'),
              value: _verLojas,
              onChanged: (v) { setState(() => _verLojas = v); setSheet(() {}); },
            ),
            const Divider(height: 1),
            SwitchListTile(
              activeColor: AppColors.teal500,
              secondary: const Icon(Icons.event_available_outlined),
              title: const Text('Esconder visitados (15 dias)'),
              subtitle: const Text('Some quem já recebeu visita recente'),
              value: _esconderVisitados,
              onChanged: (v) { setState(() => _esconderVisitados = v); setSheet(() {}); },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  // ---------- loja ----------
  void _abrirLoja(Map s) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.store, color: AppColors.teal900),
            const SizedBox(width: 8),
            Expanded(child: Text(s['nome'] ?? 'Loja', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink))),
          ]),
          const SizedBox(height: 12),
          _linha(Icons.badge_outlined, s['tipo'] ?? ''),
          _linha(Icons.location_city_outlined, s['cidade'] ?? ''),
          if ((s['end'] as String?)?.isNotEmpty == true) _linha(Icons.place_outlined, s['end']),
        ]),
      ),
    );
  }

  // ---------- detalhes do cliente ----------
  void _abrirDetalhes(Map<String, dynamic> c) {
    final emRota = _naRota(c);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.location_on, color: AppColors.coral),
            const SizedBox(width: 8),
            Expanded(child: Text(c['nome'] ?? 'Cliente', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink))),
          ]),
          const SizedBox(height: 14),
          if ((c['telefone'] as String?)?.isNotEmpty == true) _linha(Icons.phone_outlined, c['telefone']),
          if ((c['municipio'] as String?)?.isNotEmpty == true) _linha(Icons.map_outlined, c['municipio']),
          if ((c['endereco'] as String?)?.isNotEmpty == true) _linha(Icons.place_outlined, c['endereco']),
          _linha(Icons.my_location, '${_lat(c).toStringAsFixed(5)}, ${_lng(c).toStringAsFixed(5)}'),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () { Navigator.pop(context); _editar(c); },
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Editar'),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.teal700, side: const BorderSide(color: AppColors.teal500), padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: () { Navigator.pop(context); _alternarRota(c); },
                icon: Icon(emRota ? Icons.remove : Icons.add, size: 18),
                label: Text(emRota ? 'Tirar da rota' : 'Add à rota'),
                style: FilledButton.styleFrom(backgroundColor: emRota ? AppColors.muted : AppColors.coral, padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final ok = await abrirWhatsApp(c['telefone'], mensagemVisita(c['nome'] ?? 'cliente'));
                  if (!ok && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Este cliente não tem telefone cadastrado.')),
                    );
                  }
                },
                icon: const Icon(Icons.chat, size: 18),
                label: const Text('WhatsApp'),
                style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF128C7E), side: const BorderSide(color: Color(0xFF128C7E)), padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => abrirNavegacao(_lat(c), _lng(c)),
                icon: const Icon(Icons.navigation_outlined, size: 18),
                label: const Text('Navegar'),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.teal700, side: const BorderSide(color: AppColors.teal500), padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _linha(IconData icon, String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: AppColors.muted),
          const SizedBox(width: 8),
          Expanded(child: Text(texto, style: const TextStyle(color: AppColors.ink, height: 1.4))),
        ]),
      );

  // ---------- editar cliente ----------
  Future<void> _editar(Map<String, dynamic> c) async {
    final nome = TextEditingController(text: c['nome'] ?? '');
    final tel = TextEditingController(text: c['telefone'] ?? '');
    final lat = TextEditingController(text: _lat(c).toString());
    final lng = TextEditingController(text: _lng(c).toString());

    final salvar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar cliente'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nome, decoration: const InputDecoration(labelText: 'Nome')),
            const SizedBox(height: 10),
            TextField(controller: tel, decoration: const InputDecoration(labelText: 'Telefone')),
            const SizedBox(height: 10),
            TextField(controller: lat, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'Latitude')),
            const SizedBox(height: 10),
            TextField(controller: lng, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'Longitude')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
        ],
      ),
    );
    if (salvar != true) return;

    try {
      await supabase.from('clientes').update({
        'nome': nome.text.trim(),
        'telefone': tel.text.trim(),
        'latitude': double.tryParse(lat.text.trim()),
        'longitude': double.tryParse(lng.text.trim()),
      }).eq('id', c['id']);
      await _carregar();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cliente atualizado!'), backgroundColor: AppColors.teal700));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível salvar (permissão?): $e')));
    }
  }
}