// ============================================================================
//  RotaCampo — Executar rota (modo guiado, tipo Uber)
//  Mapa em cima com o percurso real (OSRM) + a parada da vez destacada.
//  O técnico registra o check-in do cliente atual e o app AVANÇA sozinho
//  para o próximo, até o último. No fim: "Concluir rota" marca como feita.
//  Pacotes: flutter_map, latlong2, image_picker, connectivity_plus,
//           shared_preferences, http
//  Salve como: lib/rota_execucao_screen.dart
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';
import 'main.dart'; // supabase, AppColors
import 'acoes.dart'; // abrirNavegacao, buscarRotaReal
import 'offline.dart'; // fila offline

class RotaExecucaoScreen extends StatefulWidget {
  final List<Map<String, dynamic>> paradas;
  final dynamic rotaId; // se veio de "Minhas rotas", dá pra marcar como feita
  const RotaExecucaoScreen({super.key, required this.paradas, this.rotaId});

  @override
  State<RotaExecucaoScreen> createState() => _RotaExecucaoScreenState();
}

class _RotaExecucaoScreenState extends State<RotaExecucaoScreen> {
  final MapController _map = MapController();
  final Set<dynamic> _feitos = {};
  List<LatLng> _pts = [];
  List<LatLng>? _caminho; // percurso real pelas estradas
  int _atual = 0; // índice da parada da vez
  bool _concluindo = false;

  LatLng? _eu; // minha posição ao vivo (boneco do técnico)
  StreamSubscription<LatLng>? _subLoc;
  bool _seguir = false; // se o mapa acompanha meu deslocamento
  bool _satelite = false; // visão de satélite ligada/desligada
  String? _minhaFoto; // foto de perfil do técnico (pro boneco)

  @override
  void initState() {
    super.initState();
    _pts = widget.paradas
        .map((c) => LatLng((c['latitude'] as num).toDouble(), (c['longitude'] as num).toDouble()))
        .toList();
    sincronizar();
    _carregarCaminho();
    _iniciarLocalizacao();
    _carregarFoto();
  }

  Future<void> _carregarFoto() async {
    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) return;
      final r = await supabase.from('usuarios').select('foto_url').eq('id', uid).maybeSingle();
      if (mounted && r != null) setState(() => _minhaFoto = r['foto_url'] as String?);
    } catch (_) {}
  }

  @override
  void dispose() {
    _subLoc?.cancel();
    super.dispose();
  }

  Future<void> _carregarCaminho() async {
    final real = await buscarRotaReal(_pts);
    if (mounted && real != null) setState(() => _caminho = real);
  }

  Future<void> _iniciarLocalizacao() async {
    final ok = await garantirPermissaoLocalizacao();
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Ative o GPS e permita a localização para ver seu deslocamento.'),
          backgroundColor: Color(0xFFB8860B),
        ));
      }
      return;
    }
    _subLoc = fluxoLocalizacao().listen((pos) {
      if (!mounted) return;
      setState(() => _eu = pos);
      if (_seguir) {
        try {
          _map.move(pos, _map.camera.zoom);
        } catch (_) {}
      }
    });
  }

  void _centralizarEmMim() {
    if (_eu == null) return;
    setState(() => _seguir = true);
    try {
      _map.move(_eu!, 15);
    } catch (_) {}
  }

  int get _total => widget.paradas.length;
  int get _visitadas => _feitos.length;
  bool get _tudoFeito => _visitadas >= _total;

  bool _feito(Map c) => _feitos.contains(c['id']);

  // Vai para uma parada: destaca e centraliza o mapa nela.
  void _irPara(int i) {
    if (i < 0 || i >= _pts.length) return;
    setState(() => _atual = i);
    try {
      _map.move(_pts[i], 14);
    } catch (_) {}
  }

  // Depois de registrar, encontra a próxima parada pendente.
  void _avancar() {
    for (var i = 0; i < widget.paradas.length; i++) {
      if (!_feito(widget.paradas[i])) {
        _irPara(i);
        return;
      }
    }
    // Nada pendente: terminou. Centraliza na última.
    setState(() {});
    if (_tudoFeito && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Todas as paradas visitadas! Agora é só concluir a rota.'),
        backgroundColor: AppColors.teal700,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final linha = _caminho ?? _pts;
    final atual = widget.paradas[_atual];

    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.teal700, foregroundColor: Colors.white, title: const Text('Executar rota')),
      body: Column(
        children: [
          // ---- progresso --------------------------------------------------
          Container(
            width: double.infinity,
            color: AppColors.teal700,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$_visitadas de $_total paradas visitadas', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(value: _total == 0 ? 0 : _visitadas / _total, minHeight: 8, backgroundColor: Colors.white24, valueColor: const AlwaysStoppedAnimation(AppColors.coral)),
              ),
            ]),
          ),
          // ---- mapa -------------------------------------------------------
          Expanded(
            child: Stack(children: [
              FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCenter: _pts.isNotEmpty ? _pts.first : const LatLng(-13.4, -41.5),
                  initialZoom: 12,
                  initialCameraFit: _pts.isNotEmpty ? CameraFit.bounds(bounds: LatLngBounds.fromPoints(_pts), padding: const EdgeInsets.all(50)) : null,
                  maxZoom: 18,
                  // se eu arrasto o mapa, paro de "seguir" automaticamente
                  onPositionChanged: (pos, gesture) {
                    if (gesture && _seguir) setState(() => _seguir = false);
                  },
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
                  if (linha.length >= 2) PolylineLayer(polylines: [Polyline(points: linha, strokeWidth: 4, color: _satelite ? AppColors.coral : AppColors.teal700)]),
                  MarkerLayer(markers: [
                    for (var i = 0; i < widget.paradas.length; i++)
                      Marker(
                        point: _pts[i],
                        width: 40,
                        height: 40,
                        child: GestureDetector(onTap: () => _irPara(i), child: _pino(i)),
                      ),
                  ]),
                  // boneco do técnico (eu) — fica por cima das paradas
                  if (_eu != null)
                    MarkerLayer(markers: [
                      Marker(
                        point: _eu!,
                        width: 48,
                        height: 48,
                        child: _bonecoEu(),
                      ),
                    ]),
                  RichAttributionWidget(attributions: [
                    TextSourceAttribution(_satelite ? 'Esri, Maxar, Earthstar Geographics' : 'OpenStreetMap contributors'),
                  ]),
                ],
              ),
              // botão satélite / mapa de ruas
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
              // botão "centralizar em mim"
              Positioned(
                right: 12,
                bottom: 12,
                child: FloatingActionButton.small(
                  heroTag: 'meuLocal',
                  backgroundColor: Colors.white,
                  foregroundColor: _seguir ? AppColors.coral : AppColors.teal700,
                  onPressed: _eu == null ? null : _centralizarEmMim,
                  child: Icon(_seguir ? Icons.my_location : Icons.location_searching),
                ),
              ),
            ]),
          ),
          // ---- painel da parada da vez ------------------------------------
          _painelInferior(atual),
        ],
      ),
    );
  }

  // Boneco do técnico: foto de perfil (ou ícone de pessoa) num círculo azul.
  Widget _bonecoEu() {
    final temFoto = _minhaFoto != null && _minhaFoto!.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.3), blurRadius: 6)],
      ),
      padding: const EdgeInsets.all(2.5),
      child: CircleAvatar(
        radius: 20,
        backgroundColor: const Color(0xFF2A7DE1),
        backgroundImage: temFoto ? NetworkImage(_minhaFoto!) : null,
        child: temFoto ? null : const Icon(Icons.person, color: Colors.white, size: 26),
      ),
    );
  }

  Widget _pino(int i) {
    final feito = _feito(widget.paradas[i]);
    final atual = i == _atual;
    final cor = feito ? AppColors.teal500 : (atual ? AppColors.coral : AppColors.teal700);
    return Container(
      decoration: BoxDecoration(color: cor, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: atual ? 3 : 2), boxShadow: atual ? [BoxShadow(color: AppColors.coral.withOpacity(.5), blurRadius: 8)] : null),
      alignment: Alignment.center,
      child: feito ? const Icon(Icons.check, color: Colors.white, size: 18) : Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
    );
  }

  Widget _painelInferior(Map<String, dynamic> atual) {
    final feitoAtual = _feito(atual);
    return Container(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(.14), blurRadius: 12)]),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Se terminou tudo, mostra concluir
        if (_tudoFeito) ...[
          const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.check_circle, color: AppColors.teal500),
            SizedBox(width: 8),
            Text('Rota toda visitada!', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink, fontSize: 16)),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _concluindo ? null : _concluirRota,
              icon: _concluindo ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.flag),
              label: const Text('Concluir rota (marcar como feita)'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.teal700, padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ),
        ] else ...[
          Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: AppColors.coral.withOpacity(.14), shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text('${_atual + 1}', style: const TextStyle(color: AppColors.coral, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Parada ${_atual + 1} de $_total', style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
                Text(atual['nome'] ?? 'Cliente', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.ink)),
                if ((atual['municipio'] as String?)?.isNotEmpty == true)
                  Text(atual['municipio'], style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              ]),
            ),
            IconButton(
              tooltip: 'Abrir navegação (Google Maps)',
              icon: const Icon(Icons.navigation_outlined, color: AppColors.teal700),
              onPressed: () => abrirNavegacao((atual['latitude'] as num).toDouble(), (atual['longitude'] as num).toDouble()),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: feitoAtual ? null : () => _registrarVisita(atual),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: Text(feitoAtual ? 'Já visitada' : 'Check-in e visita'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.coral, padding: const EdgeInsets.symmetric(vertical: 13)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  // pular pro próximo sem registrar (deixa essa parada pra depois)
                  final prox = (_atual + 1) % _total;
                  _irPara(prox);
                },
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.teal700, side: const BorderSide(color: AppColors.teal500), padding: const EdgeInsets.symmetric(vertical: 13)),
                child: const Text('Pular'),
              ),
            ),
          ]),
        ],
      ]),
    );
  }

  // ---- marca a rota como FEITA -------------------------------------------
  Future<void> _concluirRota() async {
    if (widget.rotaId == null) {
      if (mounted) Navigator.of(context).pop(true);
      return;
    }
    setState(() => _concluindo = true);
    try {
      final r = await supabase.from('rotas').update({'status': 'concluida'}).eq('id', widget.rotaId).select('id');
      if (r.isEmpty) throw 'Sem permissão para concluir esta rota.';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rota marcada como feita! ✅'), backgroundColor: AppColors.teal700));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _concluindo = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível concluir: $e')));
      }
    }
  }

  // ---- formulário de check-in (problema + produtos + fotos) --------------
  Future<void> _registrarVisita(Map<String, dynamic> c) async {
    final problema = TextEditingController();
    final List<Map<String, TextEditingController>> recs = [
      {'produto': TextEditingController(), 'dosagem': TextEditingController()},
    ];
    final List<Uint8List> fotos = [];
    bool enviando = false;
    final picker = ImagePicker();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> pegarFoto(ImageSource origem) async {
            final x = await picker.pickImage(source: origem, imageQuality: 55, maxWidth: 1280);
            if (x != null) {
              final b = await x.readAsBytes();
              setSheet(() => fotos.add(b));
            }
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Visita: ${c['nome']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
                  const SizedBox(height: 16),
                  TextField(controller: problema, maxLines: 2, decoration: const InputDecoration(labelText: 'Problema encontrado', border: OutlineInputBorder(), alignLabelWithHint: true)),
                  const SizedBox(height: 18),
                  const Text('Recomendações (produto + dosagem)', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                  const SizedBox(height: 8),
                  ...List.generate(recs.length, (i) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(children: [
                          Expanded(flex: 3, child: TextField(controller: recs[i]['produto'], decoration: const InputDecoration(labelText: 'Produto', border: OutlineInputBorder(), isDense: true))),
                          const SizedBox(width: 8),
                          Expanded(flex: 2, child: TextField(controller: recs[i]['dosagem'], decoration: const InputDecoration(labelText: 'Dosagem', border: OutlineInputBorder(), isDense: true))),
                          IconButton(icon: const Icon(Icons.remove_circle_outline, color: AppColors.muted), onPressed: recs.length == 1 ? null : () => setSheet(() => recs.removeAt(i))),
                        ]),
                      )),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setSheet(() => recs.add({'produto': TextEditingController(), 'dosagem': TextEditingController()})),
                      icon: const Icon(Icons.add, size: 18, color: AppColors.teal700),
                      label: const Text('Adicionar produto', style: TextStyle(color: AppColors.teal700, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Fotos do problema', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: OutlinedButton.icon(onPressed: () => pegarFoto(ImageSource.camera), icon: const Icon(Icons.photo_camera_outlined, size: 18), label: const Text('Câmera'), style: OutlinedButton.styleFrom(foregroundColor: AppColors.teal700, side: const BorderSide(color: AppColors.teal500)))),
                    const SizedBox(width: 12),
                    Expanded(child: OutlinedButton.icon(onPressed: () => pegarFoto(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined, size: 18), label: const Text('Galeria'), style: OutlinedButton.styleFrom(foregroundColor: AppColors.teal700, side: const BorderSide(color: AppColors.teal500)))),
                  ]),
                  if (fotos.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 84,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: fotos.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) => Stack(children: [
                          ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(fotos[i], width: 84, height: 84, fit: BoxFit.cover)),
                          Positioned(right: 2, top: 2, child: GestureDetector(onTap: () => setSheet(() => fotos.removeAt(i)), child: Container(decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle), child: const Icon(Icons.close, color: Colors.white, size: 18)))),
                        ]),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: enviando
                          ? null
                          : () async {
                              setSheet(() => enviando = true);
                              final recsList = recs
                                  .map((r) => {'produto': r['produto']!.text.trim(), 'dosagem': r['dosagem']!.text.trim()})
                                  .where((r) => (r['produto'] as String).isNotEmpty)
                                  .toList();
                              final ok = await _salvar(c, problema.text.trim(), recsList, fotos);
                              if (ok && ctx.mounted) Navigator.pop(ctx);
                              if (!ok) setSheet(() => enviando = false);
                            },
                      icon: enviando ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check_circle_outline),
                      label: Text(enviando ? 'Enviando...' : 'Registrar e ir para o próximo'),
                      style: FilledButton.styleFrom(backgroundColor: AppColors.teal700, padding: const EdgeInsets.symmetric(vertical: 14)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    // Fechou o formulário: se a visita foi registrada, avança sozinho.
    if (_feito(c)) _avancar();
  }

  Future<bool> _salvar(Map<String, dynamic> c, String problema, List<Map<String, dynamic>> recomendacoes, List<Uint8List> fotos) async {
    try {
      final uid = supabase.auth.currentUser!.id;
      final checkin = {'usuario_id': uid, 'cliente_id': c['id'], 'latitude': c['latitude'], 'longitude': c['longitude'], 'observacao': problema};
      final prescricao = {'cliente_id': c['id'], 'tecnico_id': uid, 'descricao': problema, 'recomendacoes': recomendacoes};

      if (await estaOnline()) {
        final List<String> urls = [];
        for (var i = 0; i < fotos.length; i++) {
          final caminho = '$uid/${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
          await supabase.storage.from('fotos').uploadBinary(caminho, fotos[i]);
          urls.add(supabase.storage.from('fotos').getPublicUrl(caminho));
        }
        await supabase.from('checkins').insert(checkin);
        final presc = Map<String, dynamic>.from(prescricao);
        if (urls.isNotEmpty) presc['fotos'] = urls;
        await supabase.from('prescricoes').insert(presc);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Visita registrada!'), backgroundColor: AppColors.teal700));
      } else {
        final fotosB64 = fotos.map((b) => base64Encode(b)).toList();
        await enfileirar({'tipo': 'visita', 'checkin': checkin, 'prescricao': prescricao, 'fotos': fotosB64});
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sem internet — visita salva offline.'), backgroundColor: Color(0xFFB8860B)));
      }

      setState(() => _feitos.add(c['id']));
      return true;
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível registrar: $e')));
      return false;
    }
  }
}