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
import 'acoes.dart'; // abrirNavegacao, buscarRotaReal, abrirWhatsApp
import 'offline.dart'; // fila offline
import 'ocr.dart'; // ler texto da foto do papel (só celular)

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
  final Set<dynamic> _justificados = {}; // não visitados, mas com justificativa
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
    if (mounted && real != null && _caminho == null) setState(() => _caminho = real);
  }

  // Monta o caminho a partir de ONDE EU ESTOU → 1º cliente → próximos.
  Future<void> _recalcularCaminho() async {
    final pts = [if (_eu != null) _eu!, ..._pts];
    final real = await buscarRotaReal(pts);
    if (mounted && real != null) setState(() => _caminho = real);
  }

  Future<void> _iniciarLocalizacao() async {
    final ok = await garantirPermissaoLocalizacao();
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Ative o GPS e permita a localização para ver onde você está.'),
          backgroundColor: Color(0xFFB8860B),
        ));
      }
      return;
    }
    // 1) pega a posição agora (pra o marcador aparecer logo e a rota sair de você)
    final inicial = await posicaoAtual();
    if (inicial != null && mounted) {
      setState(() => _eu = inicial);
      _recalcularCaminho();
      try {
        _map.move(inicial, 14);
      } catch (_) {}
    }
    // 2) acompanha o deslocamento ao vivo
    _subLoc = fluxoLocalizacao().listen((pos) {
      if (!mounted) return;
      final primeira = _eu == null;
      setState(() => _eu = pos);
      if (primeira) _recalcularCaminho(); // recalcula a rota quando descobre onde você está
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
  int get _justificadas => _justificados.length;
  int get _resolvidas => _feitos.length + _justificados.length;
  bool get _tudoFeito => _resolvidas >= _total;

  bool _feito(Map c) => _feitos.contains(c['id']);
  bool _justif(Map c) => _justificados.contains(c['id']);
  bool _resolvido(Map c) => _feito(c) || _justif(c);

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
      if (!_resolvido(widget.paradas[i])) {
        _irPara(i);
        return;
      }
    }
    // Nada pendente: terminou. Centraliza na última.
    setState(() {});
    if (_tudoFeito && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Todas as paradas resolvidas! Agora é só concluir a rota.'),
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
              Text('$_resolvidas de $_total resolvidas', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
              Text('$_visitadas visitadas · $_justificadas justificadas', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(value: _total == 0 ? 0 : _resolvidas / _total, minHeight: 8, backgroundColor: Colors.white24, valueColor: const AlwaysStoppedAnimation(AppColors.coral)),
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
    final c = widget.paradas[i];
    final feito = _feito(c);
    final justif = _justif(c);
    final atual = i == _atual;
    final cor = feito ? AppColors.teal500 : (justif ? const Color(0xFFB8860B) : (atual ? AppColors.coral : AppColors.teal700));
    return Container(
      decoration: BoxDecoration(color: cor, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: atual ? 3 : 2), boxShadow: atual ? [BoxShadow(color: AppColors.coral.withOpacity(.5), blurRadius: 8)] : null),
      alignment: Alignment.center,
      child: feito
          ? const Icon(Icons.check, color: Colors.white, size: 18)
          : justif
              ? const Icon(Icons.priority_high, color: Colors.white, size: 18)
              : Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
    );
  }

  Widget _painelInferior(Map<String, dynamic> atual) {
    final feitoAtual = _feito(atual);
    final justifAtual = _justif(atual);
    final resolvidoAtual = feitoAtual || justifAtual;
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
                onPressed: resolvidoAtual ? null : () => _registrarVisita(atual),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: Text(feitoAtual ? 'Já visitada' : (justifAtual ? 'Justificada' : 'Check-in e visita')),
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
          if (!resolvidoAtual) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _justificar(atual),
                icon: const Icon(Icons.report_gmailerrorred_outlined, size: 18),
                label: const Text('Não consegui visitar (justificar)'),
                style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFB8860B), side: const BorderSide(color: Color(0xFFB8860B)), padding: const EdgeInsets.symmetric(vertical: 11)),
              ),
            ),
          ],
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
      if (await estaOnline()) {
        final r = await supabase.from('rotas').update({'status': 'concluida'}).eq('id', widget.rotaId).select('id');
        if (r.isEmpty) throw 'Sem permissão para concluir esta rota.';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rota marcada como feita! ✅'), backgroundColor: AppColors.teal700));
        }
      } else {
        // sem internet: guarda e conclui quando voltar o sinal
        await enfileirar({'tipo': 'rota_concluida', 'rota_id': widget.rotaId, 'status': 'concluida'});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sem internet — a rota será concluída automaticamente quando houver sinal.'), backgroundColor: Color(0xFFB8860B)));
        }
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _concluindo = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível concluir: $e')));
      }
    }
  }

  // ---- formulário de check-in (problema + produtos + fotos) --------------
  // ---- justificar (não consegui visitar) --------------------------------
  Future<void> _justificar(Map<String, dynamic> c) async {
    const motivos = ['Cliente ausente', 'Propriedade fechada', 'Acesso impossível (estrada/chuva)', 'Cliente recusou a visita', 'Endereço não encontrado', 'Outro'];
    String motivo = motivos.first;
    final obs = TextEditingController();
    bool enviando = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Não consegui visitar: ${c['nome']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: motivo,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Motivo', border: OutlineInputBorder()),
              items: motivos.map((m) => DropdownMenuItem(value: m, child: Text(m, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => setSheet(() => motivo = v!),
            ),
            const SizedBox(height: 12),
            TextField(controller: obs, maxLines: 2, decoration: const InputDecoration(labelText: 'Observação (opcional)', border: OutlineInputBorder(), alignLabelWithHint: true)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: enviando
                    ? null
                    : () async {
                        setSheet(() => enviando = true);
                        final ok = await _salvarJustificativa(c, motivo, obs.text.trim());
                        if (ok && ctx.mounted) Navigator.pop(ctx);
                        if (!ok) setSheet(() => enviando = false);
                      },
                icon: enviando ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.flag_outlined),
                label: Text(enviando ? 'Salvando...' : 'Registrar e ir para o próximo'),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB8860B), padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
          ]),
        ),
      ),
    );
    if (_justif(c)) _avancar();
  }

  Future<bool> _salvarJustificativa(Map<String, dynamic> c, String motivo, String obs) async {
    try {
      final uid = supabase.auth.currentUser!.id;
      final dados = {'cliente_id': c['id'], 'usuario_id': uid, 'rota_id': widget.rotaId, 'motivo': motivo, 'observacao': obs};
      if (await estaOnline()) {
        await supabase.from('justificativas').insert(dados);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Justificativa registrada.'), backgroundColor: Color(0xFFB8860B)));
      } else {
        await enfileirar({'tipo': 'justificativa', 'dados': dados});
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sem internet — justificativa salva offline.'), backgroundColor: Color(0xFFB8860B)));
      }
      setState(() => _justificados.add(c['id']));
      return true;
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível salvar: $e')));
      return false;
    }
  }

  Future<void> _registrarVisita(Map<String, dynamic> c) async {
    // catálogo de produtos — carregado DEPOIS que a tela abre (pra não travar a abertura)
    List<Map<String, dynamic>> catalogo = [];
    bool catCarregado = false;
    bool catCarregando = false;

    final problema = TextEditingController();
    // Pragas e doenças — pode ter várias, cada uma com nome e fotos próprias
    Map<String, dynamic> novoAlvo() => {'nome': TextEditingController(), 'fotos': <Uint8List>[]};
    final List<Map<String, dynamic>> pragas = [novoAlvo()];
    final List<Map<String, dynamic>> doencas = [novoAlvo()];
    // Culturas atendidas (cultura + nº de plantas) — pelo menos uma
    Map<String, dynamic> novaCultura() => {'cultura': TextEditingController(), 'plantas': TextEditingController()};
    final List<Map<String, dynamic>> culturas = [novaCultura()];
    Map<String, dynamic> novoItem() => {
          'produto': null,
          'principio': null,
          'dose': TextEditingController(),
          'unidade': TextEditingController(),
          'modalidade': TextEditingController(),
          'carencia': TextEditingController(),
        };
    final List<Map<String, dynamic>> recs = [novoItem()];
    // "O que o produtor já tem na propriedade"
    Map<String, dynamic> novoEstoque() => {
          'produto': null,
          'quantidade': TextEditingController(),
          'unidade': TextEditingController(),
          'recomendar': false,
          'dose': TextEditingController(),
          'modo': TextEditingController(),
        };
    final List<Map<String, dynamic>> jaTem = [];
    // Cronograma de aplicação (etapas ao longo do tempo)
    Map<String, dynamic> novaEtapa() => {
          'produto': null,
          'quando': TextEditingController(),
          'dose': TextEditingController(),
          'obs': TextEditingController(),
        };
    final List<Map<String, dynamic>> cronograma = [];
    final List<Uint8List> fotos = [];
    bool enviando = false;
    final picker = ImagePicker();
    // seções recolhíveis (começam fechadas pra não poluir)
    bool abrePragas = false, abreDoencas = false, abreJaTem = false, abreCrono = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> pegarFotoEm(List<Uint8List> lista, ImageSource origem) async {
            final x = await picker.pickImage(source: origem, imageQuality: 55, maxWidth: 1280);
            if (x != null) {
              final b = await x.readAsBytes();
              setSheet(() => lista.add(b));
            }
          }

          Widget botoesFoto(List<Uint8List> lista) => Row(children: [
                Expanded(child: OutlinedButton.icon(onPressed: () => pegarFotoEm(lista, ImageSource.camera), icon: const Icon(Icons.photo_camera_outlined, size: 18), label: const Text('Câmera'), style: OutlinedButton.styleFrom(foregroundColor: AppColors.teal700, side: const BorderSide(color: AppColors.teal500)))),
                const SizedBox(width: 12),
                Expanded(child: OutlinedButton.icon(onPressed: () => pegarFotoEm(lista, ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined, size: 18), label: const Text('Galeria'), style: OutlinedButton.styleFrom(foregroundColor: AppColors.teal700, side: const BorderSide(color: AppColors.teal500)))),
              ]);

          Widget faixaFotos(List<Uint8List> lista) {
            if (lista.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 10),
              child: SizedBox(
                height: 84,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: lista.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => Stack(children: [
                    ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(lista[i], width: 84, height: 84, fit: BoxFit.cover)),
                    Positioned(right: 2, top: 2, child: GestureDetector(onTap: () => setSheet(() => lista.removeAt(i)), child: Container(decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle), child: const Icon(Icons.close, color: Colors.white, size: 18)))),
                  ]),
                ),
              ),
            );
          }

          // Bloco de pragas OU doenças (várias, cada uma com nome + fotos)
          List<Widget> blocoAlvos(Color cor, List<Map<String, dynamic>> lista, String campoLabel, String botaoTxt) {
            return [
              ...List.generate(lista.length, (i) {
                final a = lista[i];
                final fotosA = a['fotos'] as List<Uint8List>;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(12)),
                  child: Column(children: [
                    Row(children: [
                      Expanded(child: TextField(controller: a['nome'] as TextEditingController, decoration: InputDecoration(labelText: campoLabel, border: const OutlineInputBorder(), isDense: true, filled: true, fillColor: Colors.white))),
                      IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(), icon: const Icon(Icons.remove_circle_outline, color: AppColors.muted), onPressed: lista.length == 1 ? null : () => setSheet(() => lista.removeAt(i))),
                    ]),
                    const SizedBox(height: 8),
                    botoesFoto(fotosA),
                    faixaFotos(fotosA),
                  ]),
                );
              }),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setSheet(() => lista.add(novoAlvo())),
                  icon: Icon(Icons.add, size: 18, color: cor),
                  label: Text(botaoTxt, style: TextStyle(color: cor, fontWeight: FontWeight.w600)),
                ),
              ),
            ];
          }

          // Cabeçalho recolhível de uma seção (toca para abrir/fechar)
          Widget cabecalho(String titulo, IconData icone, Color cor, bool aberto, int qtd, VoidCallback onTap) {
            return InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(children: [
                  Icon(icone, size: 18, color: cor),
                  const SizedBox(width: 8),
                  Expanded(child: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink))),
                  if (qtd > 0)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: cor.withOpacity(.14), borderRadius: BorderRadius.circular(999)),
                      child: Text('$qtd', style: TextStyle(color: cor, fontWeight: FontWeight.w700, fontSize: 12)),
                    ),
                  Icon(aberto ? Icons.expand_less : Icons.expand_more, color: AppColors.muted),
                ]),
              ),
            );
          }

          // Produtos disponíveis pro cronograma: o que ele já tem + o catálogo
          final nomesCatalogo = catalogo.map((p) => p['nome'] as String).toList();
          final nomesJaTem = jaTem.map((r) => r['produto']).whereType<String>().map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
          final setJaTem = nomesJaTem.toSet();
          final opcoesProduto = <String>{...nomesJaTem, ...nomesCatalogo}.toList()..sort();

          // Carrega o catálogo em segundo plano (sem travar a abertura da tela).
          if (!catCarregado && !catCarregando) {
            catCarregando = true;
            () async {
              List<Map<String, dynamic>> lista = [];
              try {
                lista = List<Map<String, dynamic>>.from(await supabase.from('produtos').select('nome, principio_ativo, unidade, carencia, dose_recomendada').order('nome'));
              } catch (_) {
                try {
                  lista = List<Map<String, dynamic>>.from(await supabase.from('produtos').select('nome, principio_ativo, unidade, carencia').order('nome'));
                } catch (_) {}
              }
              final vistos = <String>{};
              catalogo = lista.where((p) {
                final n = (p['nome'] ?? '').toString().trim();
                return n.isNotEmpty && vistos.add(n);
              }).toList();
              catCarregado = true;
              catCarregando = false;
              try {
                setSheet(() {});
              } catch (_) {}
            }();
          }

          // Seletor de produto COM BUSCA (digita, filtra e toca no certo).
          Future<String?> escolherProduto() {
            String q = '';
            return showModalBottomSheet<String>(
              context: ctx,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (ctx2) => StatefulBuilder(
                builder: (ctx2, setS) {
                  final filtrados = q.trim().isEmpty
                      ? catalogo
                      : catalogo.where((p) => (p['nome'] ?? '').toString().toLowerCase().contains(q.toLowerCase())).toList();
                  return Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(ctx2).viewInsets.bottom + 16),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                        autofocus: true,
                        onChanged: (v) => setS(() => q = v),
                        decoration: const InputDecoration(hintText: 'Buscar produto...', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 8),
                      Flexible(
                        child: filtrados.isEmpty
                            ? Padding(padding: const EdgeInsets.all(16), child: Text(catalogo.isEmpty ? 'Catálogo vazio. Digite o nome e toque em "Usar".' : 'Nenhum produto encontrado.', style: const TextStyle(color: AppColors.muted)))
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: filtrados.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (_, i) => ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.inventory_2_outlined, color: AppColors.muted, size: 20),
                                  title: Text(filtrados[i]['nome'] ?? '', overflow: TextOverflow.ellipsis),
                                  onTap: () => Navigator.pop(ctx2, filtrados[i]['nome'] as String),
                                ),
                              ),
                      ),
                      if (q.trim().isNotEmpty)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => Navigator.pop(ctx2, q.trim()),
                            icon: const Icon(Icons.add, size: 18, color: AppColors.teal700),
                            label: Text('Usar "${q.trim()}"', style: const TextStyle(color: AppColors.teal700, fontWeight: FontWeight.w600)),
                          ),
                        ),
                    ]),
                  );
                },
              ),
            );
          }

          // Foto da anotação em papel + tenta transcrever (OCR no celular)
          Future<void> anotacaoPapel() async {
            final x = await picker.pickImage(source: ImageSource.camera, imageQuality: 70, maxWidth: 1600);
            if (x == null) return;
            final bytes = await x.readAsBytes();
            setSheet(() => fotos.add(bytes));
            final texto = await lerTextoDaImagem(x.path);
            if (!ctx.mounted) return;
            if (texto != null && texto.isNotEmpty) {
              setSheet(() {
                final atual = problema.text.trim();
                problema.text = atual.isEmpty ? texto : '$atual\n$texto';
              });
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Anotação transcrita! Confira e ajuste o texto.'), backgroundColor: AppColors.teal700));
            } else {
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Foto anexada. Não consegui transcrever — digite se precisar.'), backgroundColor: Color(0xFFB8860B)));
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
                  // checklist do que ainda falta (fica verde quando preenche)
                  Builder(builder: (_) {
                    final temCultura = culturas.any((cu) => (cu['cultura'] as TextEditingController).text.trim().isNotEmpty);
                    final temProduto = recs.any((r) => (r['produto'] as String?)?.toString().trim().isNotEmpty == true) ||
                        jaTem.any((r) => r['recomendar'] == true && ((r['produto'] as String?)?.trim().isNotEmpty ?? false));
                    final temFoto = fotos.isNotEmpty || pragas.any((a) => (a['fotos'] as List).isNotEmpty) || doencas.any((a) => (a['fotos'] as List).isNotEmpty);
                    Widget ck(String t, bool ok) => Container(
                          margin: const EdgeInsets.only(right: 8, top: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: (ok ? AppColors.teal500 : AppColors.muted).withOpacity(.12), borderRadius: BorderRadius.circular(999)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked, size: 14, color: ok ? AppColors.teal700 : AppColors.muted),
                            const SizedBox(width: 4),
                            Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ok ? AppColors.teal700 : AppColors.muted)),
                          ]),
                        );
                    return Wrap(children: [ck('Cultura', temCultura), ck('Produto', temProduto), ck('Foto', temFoto)]);
                  }),
                  const SizedBox(height: 14),
                  TextField(controller: problema, maxLines: 2, decoration: const InputDecoration(labelText: 'Problema encontrado', border: OutlineInputBorder(), alignLabelWithHint: true)),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: anotacaoPapel,
                      icon: const Icon(Icons.document_scanner_outlined, size: 18),
                      label: const Text('Anotação em papel (foto + ler)'),
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.teal700, side: const BorderSide(color: AppColors.teal500)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // ---- Culturas (uma ou mais) + nº de plantas ----
                  Row(children: const [
                    Icon(Icons.grass_outlined, size: 18, color: AppColors.teal700),
                    SizedBox(width: 6),
                    Expanded(child: Text('Culturas atendidas *', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink))),
                  ]),
                  const SizedBox(height: 8),
                  ...List.generate(culturas.length, (i) {
                    final cu = culturas[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        Expanded(flex: 3, child: TextField(controller: cu['cultura'] as TextEditingController, decoration: const InputDecoration(labelText: 'Cultura', border: OutlineInputBorder(), isDense: true))),
                        const SizedBox(width: 8),
                        Expanded(flex: 2, child: TextField(controller: cu['plantas'] as TextEditingController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Nº plantas', border: OutlineInputBorder(), isDense: true))),
                        IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(), icon: const Icon(Icons.remove_circle_outline, color: AppColors.muted), onPressed: culturas.length == 1 ? null : () => setSheet(() => culturas.removeAt(i))),
                      ]),
                    );
                  }),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setSheet(() => culturas.add(novaCultura())),
                      icon: const Icon(Icons.add, size: 18, color: AppColors.teal700),
                      label: const Text('Adicionar cultura', style: TextStyle(color: AppColors.teal700, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  // ---- Pragas (recolhível) ----
                  cabecalho('Pragas', Icons.pest_control_outlined, AppColors.coral, abrePragas,
                      pragas.where((a) => (a['nome'] as TextEditingController).text.trim().isNotEmpty || (a['fotos'] as List).isNotEmpty).length,
                      () => setSheet(() => abrePragas = !abrePragas)),
                  if (abrePragas) ...blocoAlvos(AppColors.coral, pragas, 'Praga identificada', 'Adicionar praga'),
                  const Divider(height: 1),
                  // ---- Doenças (recolhível) ----
                  cabecalho('Doenças', Icons.coronavirus_outlined, const Color(0xFFB8860B), abreDoencas,
                      doencas.where((a) => (a['nome'] as TextEditingController).text.trim().isNotEmpty || (a['fotos'] as List).isNotEmpty).length,
                      () => setSheet(() => abreDoencas = !abreDoencas)),
                  if (abreDoencas) ...blocoAlvos(const Color(0xFFB8860B), doencas, 'Doença identificada', 'Adicionar doença'),
                  const SizedBox(height: 12),
                  const Text('Recomendações *', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                  if (catCarregando)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Row(children: [
                        SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal500)),
                        SizedBox(width: 8),
                        Text('Carregando produtos...', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                      ]),
                    )
                  else if (catalogo.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('Nenhum produto cadastrado. Digite o produto ou cadastre em Menu › Produtos.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    ),
                  const SizedBox(height: 8),
                  ...List.generate(recs.length, (i) {
                    final item = recs[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(12)),
                      child: Column(children: [
                        Row(children: [
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                final escolhido = await escolherProduto();
                                if (escolhido == null) return;
                                setSheet(() {
                                  item['produto'] = escolhido;
                                  final prod = catalogo.firstWhere((p) => p['nome'] == escolhido, orElse: () => <String, dynamic>{});
                                  item['principio'] = prod['principio_ativo'];
                                  final d = item['dose'] as TextEditingController;
                                  final u = item['unidade'] as TextEditingController;
                                  final ca = item['carencia'] as TextEditingController;
                                  if (prod['unidade'] != null) u.text = '${prod['unidade']}';
                                  if (prod['carencia'] != null) ca.text = '${prod['carencia']}';
                                  if ((prod['dose_recomendada'] ?? '').toString().isNotEmpty && d.text.isEmpty) d.text = '${prod['dose_recomendada']}';
                                });
                              },
                              child: InputDecorator(
                                decoration: const InputDecoration(labelText: 'Produto', border: OutlineInputBorder(), isDense: true, filled: true, fillColor: Colors.white),
                                child: Row(children: [
                                  Expanded(child: Text((item['produto'] as String?)?.isNotEmpty == true ? '${item['produto']}' : 'Selecionar produto', overflow: TextOverflow.ellipsis, style: TextStyle(color: (item['produto'] as String?)?.isNotEmpty == true ? AppColors.ink : AppColors.muted))),
                                  const Icon(Icons.search, size: 18, color: AppColors.muted),
                                ]),
                              ),
                            ),
                          ),
                          IconButton(icon: const Icon(Icons.remove_circle_outline, color: AppColors.muted), onPressed: recs.length == 1 ? null : () => setSheet(() => recs.removeAt(i))),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(child: TextField(controller: item['dose'] as TextEditingController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Dose', border: OutlineInputBorder(), isDense: true, filled: true, fillColor: Colors.white))),
                          const SizedBox(width: 8),
                          Expanded(child: TextField(controller: item['unidade'] as TextEditingController, decoration: const InputDecoration(labelText: 'Unidade', border: OutlineInputBorder(), isDense: true, filled: true, fillColor: Colors.white))),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(child: TextField(controller: item['modalidade'] as TextEditingController, decoration: const InputDecoration(labelText: 'Aplicação', border: OutlineInputBorder(), isDense: true, filled: true, fillColor: Colors.white))),
                          const SizedBox(width: 8),
                          Expanded(child: TextField(controller: item['carencia'] as TextEditingController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Carência (dias)', border: OutlineInputBorder(), isDense: true, filled: true, fillColor: Colors.white))),
                        ]),
                      ]),
                    );
                  }),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setSheet(() => recs.add(novoItem())),
                      icon: const Icon(Icons.add, size: 18, color: AppColors.teal700),
                      label: const Text('Adicionar produto', style: TextStyle(color: AppColors.teal700, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const Divider(height: 1),
                  cabecalho('Produtos que o produtor já tem', Icons.inventory_2_outlined, AppColors.teal700, abreJaTem,
                      jaTem.where((r) => ((r['produto'] as String?)?.trim().isNotEmpty ?? false)).length,
                      () => setSheet(() => abreJaTem = !abreJaTem)),
                  if (abreJaTem) ...[
                  const Padding(
                    padding: EdgeInsets.only(top: 2, bottom: 6),
                    child: Text('O que ele já tem na propriedade — ajuda a recomendar sem repetir compra.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  ),
                  if (jaTem.isEmpty)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 2), child: Text('Nenhum item ainda.', style: TextStyle(color: AppColors.muted, fontSize: 12))),
                  ...List.generate(jaTem.length, (i) {
                    final item = jaTem[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(12)),
                      child: Column(children: [
                        Row(children: [
                          Expanded(
                            flex: 4,
                            child: catalogo.isNotEmpty
                                ? DropdownButtonFormField<String>(
                                    value: item['produto'] as String?,
                                    isExpanded: true,
                                    decoration: const InputDecoration(labelText: 'Produto', border: OutlineInputBorder(), isDense: true, filled: true, fillColor: Colors.white),
                                    items: catalogo.map((p) => DropdownMenuItem(value: p['nome'] as String, child: Text(p['nome'] ?? '', overflow: TextOverflow.ellipsis))).toList(),
                                    onChanged: (v) => setSheet(() {
                                      item['produto'] = v;
                                      final prod = catalogo.firstWhere((p) => p['nome'] == v, orElse: () => <String, dynamic>{});
                                      final u = item['unidade'] as TextEditingController;
                                      final d = item['dose'] as TextEditingController;
                                      if (prod['unidade'] != null && u.text.isEmpty) u.text = '${prod['unidade']}';
                                      if ((prod['dose_recomendada'] ?? '').toString().isNotEmpty && d.text.isEmpty) d.text = '${prod['dose_recomendada']}';
                                    }),
                                  )
                                : TextField(
                                    decoration: const InputDecoration(labelText: 'Produto', border: OutlineInputBorder(), isDense: true, filled: true, fillColor: Colors.white),
                                    onChanged: (v) => item['produto'] = v,
                                  ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(flex: 2, child: TextField(controller: item['quantidade'] as TextEditingController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Qtd', border: OutlineInputBorder(), isDense: true, filled: true, fillColor: Colors.white))),
                          const SizedBox(width: 8),
                          Expanded(flex: 2, child: TextField(controller: item['unidade'] as TextEditingController, decoration: const InputDecoration(labelText: 'Un.', border: OutlineInputBorder(), isDense: true, filled: true, fillColor: Colors.white))),
                          IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(), icon: const Icon(Icons.remove_circle_outline, color: AppColors.muted), onPressed: () => setSheet(() => jaTem.removeAt(i))),
                        ]),
                        // Recomendar aplicar o que ele já tem
                        Row(children: [
                          Transform.scale(
                            scale: .85,
                            child: Switch(
                              value: item['recomendar'] == true,
                              activeColor: AppColors.teal700,
                              onChanged: (v) => setSheet(() => item['recomendar'] = v),
                            ),
                          ),
                          const Expanded(child: Text('Recomendar aplicar este', style: TextStyle(color: AppColors.ink, fontSize: 13, fontWeight: FontWeight.w600))),
                        ]),
                        if (item['recomendar'] == true) ...[
                          const SizedBox(height: 4),
                          TextField(controller: item['dose'] as TextEditingController, decoration: const InputDecoration(labelText: 'Dose recomendada (ex.: 2 L/ha)', border: OutlineInputBorder(), isDense: true, filled: true, fillColor: Colors.white)),
                          const SizedBox(height: 8),
                          TextField(controller: item['modo'] as TextEditingController, decoration: const InputDecoration(labelText: 'Como aplicar (ex.: pulverização foliar)', border: OutlineInputBorder(), isDense: true, filled: true, fillColor: Colors.white)),
                          const SizedBox(height: 4),
                        ],
                      ]),
                    );
                  }),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setSheet(() => jaTem.add(novoEstoque())),
                      icon: const Icon(Icons.add, size: 18, color: AppColors.teal700),
                      label: const Text('Adicionar o que já tem', style: TextStyle(color: AppColors.teal700, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  ],
                  const Divider(height: 1),
                  cabecalho('Cronograma de aplicação', Icons.event_note_outlined, AppColors.teal700, abreCrono, cronograma.length,
                      () => setSheet(() => abreCrono = !abreCrono)),
                  if (abreCrono) ...[
                  const Padding(
                    padding: EdgeInsets.only(top: 2, bottom: 6),
                    child: Text('Etapas do que aplicar e quando — vai pro cliente.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  ),
                  if (cronograma.isEmpty)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 2), child: Text('Nenhuma etapa ainda.', style: TextStyle(color: AppColors.muted, fontSize: 12))),
                  ...List.generate(cronograma.length, (i) {
                    final et = cronograma[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(12)),
                      child: Column(children: [
                        Row(children: [
                          Container(width: 26, height: 26, alignment: Alignment.center, decoration: const BoxDecoration(color: AppColors.teal700, shape: BoxShape.circle), child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))),
                          const SizedBox(width: 8),
                          Expanded(
                            child: opcoesProduto.isNotEmpty
                                ? DropdownButtonFormField<String>(
                                    value: opcoesProduto.contains(et['produto']) ? et['produto'] as String? : null,
                                    isExpanded: true,
                                    decoration: const InputDecoration(labelText: 'Produto', border: OutlineInputBorder(), isDense: true, filled: true, fillColor: Colors.white),
                                    items: opcoesProduto.map((n) => DropdownMenuItem(value: n, child: Text(setJaTem.contains(n) ? '$n (já tem)' : n, overflow: TextOverflow.ellipsis))).toList(),
                                    onChanged: (v) => setSheet(() {
                                      et['produto'] = v;
                                      final prod = catalogo.firstWhere((p) => p['nome'] == v, orElse: () => <String, dynamic>{});
                                      final d = et['dose'] as TextEditingController;
                                      if ((prod['dose_recomendada'] ?? '').toString().isNotEmpty && d.text.isEmpty) d.text = '${prod['dose_recomendada']}';
                                    }),
                                  )
                                : TextField(
                                    decoration: const InputDecoration(labelText: 'Produto', border: OutlineInputBorder(), isDense: true, filled: true, fillColor: Colors.white),
                                    onChanged: (v) => et['produto'] = v,
                                  ),
                          ),
                          IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(), icon: const Icon(Icons.remove_circle_outline, color: AppColors.muted), onPressed: () => setSheet(() => cronograma.removeAt(i))),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(flex: 3, child: TextField(controller: et['quando'] as TextEditingController, decoration: const InputDecoration(labelText: 'Quando (ex.: Dia 0, após 15 dias)', border: OutlineInputBorder(), isDense: true, filled: true, fillColor: Colors.white))),
                          const SizedBox(width: 8),
                          Expanded(flex: 2, child: TextField(controller: et['dose'] as TextEditingController, decoration: const InputDecoration(labelText: 'Dose', border: OutlineInputBorder(), isDense: true, filled: true, fillColor: Colors.white))),
                        ]),
                        const SizedBox(height: 8),
                        TextField(controller: et['obs'] as TextEditingController, decoration: const InputDecoration(labelText: 'Observação (opcional)', border: OutlineInputBorder(), isDense: true, filled: true, fillColor: Colors.white)),
                      ]),
                    );
                  }),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setSheet(() => cronograma.add(novaEtapa())),
                      icon: const Icon(Icons.add, size: 18, color: AppColors.teal700),
                      label: const Text('Adicionar etapa', style: TextStyle(color: AppColors.teal700, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  ],
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  const Text('Fotos do problema *', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                  const Padding(padding: EdgeInsets.only(top: 2, bottom: 6), child: Text('Pelo menos uma foto é obrigatória (aqui, na praga ou na doença).', style: TextStyle(color: AppColors.muted, fontSize: 12))),
                  botoesFoto(fotos),
                  faixaFotos(fotos),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: enviando
                          ? null
                          : () async {
                              // Campos obrigatórios
                              final culturasOk = culturas.any((cu) => (cu['cultura'] as TextEditingController).text.trim().isNotEmpty);
                              final produtosOk = recs.any((r) => (r['produto'] as String?)?.toString().trim().isNotEmpty == true) ||
                                  jaTem.any((r) => r['recomendar'] == true && ((r['produto'] as String?)?.trim().isNotEmpty ?? false));
                              final fotosOk = fotos.isNotEmpty || pragas.any((a) => (a['fotos'] as List).isNotEmpty) || doencas.any((a) => (a['fotos'] as List).isNotEmpty);
                              if (!culturasOk) {
                                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Informe pelo menos uma cultura.')));
                                return;
                              }
                              if (!produtosOk) {
                                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Adicione pelo menos um produto na prescrição.')));
                                return;
                              }
                              if (!fotosOk) {
                                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Adicione pelo menos uma foto (problema, praga ou doença).')));
                                return;
                              }
                              setSheet(() => enviando = true);
                              final recsList = recs.where((r) => (r['produto'] as String?)?.isNotEmpty == true).map((r) {
                                final dose = (r['dose'] as TextEditingController).text.trim();
                                final unidade = (r['unidade'] as TextEditingController).text.trim();
                                return {
                                  'produto': r['produto'],
                                  'principio': r['principio'],
                                  'dose': dose,
                                  'unidade': unidade,
                                  'modalidade': (r['modalidade'] as TextEditingController).text.trim(),
                                  'carencia': (r['carencia'] as TextEditingController).text.trim(),
                                  'dosagem': [dose, unidade].where((s) => s.isNotEmpty).join(' '),
                                };
                              }).toList();
                              final jaTemList = jaTem.where((r) => ((r['produto'] as String?)?.trim().isNotEmpty ?? false)).map((r) {
                                final prod = (r['produto'] as String).trim();
                                final recomendar = r['recomendar'] == true;
                                final dose = (r['dose'] as TextEditingController).text.trim();
                                final modo = (r['modo'] as TextEditingController).text.trim();
                                // Marcado como "recomendar aplicar" -> vira recomendação (do que já tem)
                                if (recomendar) {
                                  recsList.add({
                                    'produto': prod,
                                    'principio': null,
                                    'dose': dose,
                                    'unidade': '',
                                    'modalidade': modo,
                                    'carencia': '',
                                    'origem': 'propriedade',
                                    'dosagem': dose,
                                  });
                                }
                                return {
                                  'produto': prod,
                                  'quantidade': (r['quantidade'] as TextEditingController).text.trim(),
                                  'unidade': (r['unidade'] as TextEditingController).text.trim(),
                                  'recomendado': recomendar,
                                };
                              }).toList();
                              final cronogramaList = cronograma.where((e) => ((e['produto'] as String?)?.trim().isNotEmpty ?? false)).map((e) {
                                return {
                                  'produto': (e['produto'] as String).trim(),
                                  'quando': (e['quando'] as TextEditingController).text.trim(),
                                  'dose': (e['dose'] as TextEditingController).text.trim(),
                                  'obs': (e['obs'] as TextEditingController).text.trim(),
                                };
                              }).toList();
                              final culturasList = culturas.where((cu) => (cu['cultura'] as TextEditingController).text.trim().isNotEmpty).map((cu) {
                                return {
                                  'cultura': (cu['cultura'] as TextEditingController).text.trim(),
                                  'plantas': int.tryParse((cu['plantas'] as TextEditingController).text.trim()),
                                };
                              }).toList();
                              List<Map<String, dynamic>> montarAlvos(List<Map<String, dynamic>> lista) => lista
                                  .where((x) => (x['nome'] as TextEditingController).text.trim().isNotEmpty || (x['fotos'] as List).isNotEmpty)
                                  .map((x) => {'nome': (x['nome'] as TextEditingController).text.trim(), 'fotos': x['fotos'] as List<Uint8List>})
                                  .toList();
                              final pragasData = montarAlvos(pragas);
                              final doencasData = montarAlvos(doencas);
                              final ok = await _salvar(c, problema.text.trim(), culturasList, pragasData, doencasData, recsList, jaTemList, cronogramaList, fotos);
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

    // Fechou o formulário: se a visita foi registrada, avisa o vendedor e avança.
    if (_feito(c)) {
      _oferecerAvisoVendedor(c);
      _avancar();
    }
  }

  // Avisa o vendedor dono da carteira (no app é automático via gatilho; aqui
  // confirmamos e oferecemos mandar também no WhatsApp).
  Future<void> _oferecerAvisoVendedor(Map<String, dynamic> c) async {
    try {
      final cli = await supabase.from('clientes').select('vendedor_id, nome').eq('id', c['id']).maybeSingle();
      final vid = cli?['vendedor_id'];
      if (vid == null) return;
      final v = await supabase.from('usuarios').select('nome, telefone').eq('id', vid).maybeSingle();
      final nome = (v?['nome'] ?? 'Vendedor').toString();
      final tel = (v?['telefone'] ?? '').toString();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$nome foi avisado no app sobre a prescrição.'),
        backgroundColor: AppColors.teal700,
        duration: const Duration(seconds: 6),
        action: tel.trim().isNotEmpty
            ? SnackBarAction(
                label: 'WhatsApp',
                textColor: Colors.white,
                onPressed: () => abrirWhatsApp(tel, 'Olá $nome! Nova prescrição registrada para o cliente ${cli?['nome'] ?? ''} (visita técnica da Porteira). Confira no app em Avisos.'),
              )
            : null,
      ));
    } catch (_) {}
  }

  Future<bool> _salvar(
    Map<String, dynamic> c,
    String problema,
    List<Map<String, dynamic>> culturas,
    List<Map<String, dynamic>> pragas, // [{nome, fotos: List<Uint8List>}]
    List<Map<String, dynamic>> doencas,
    List<Map<String, dynamic>> recomendacoes,
    List<Map<String, dynamic>> estoque,
    List<Map<String, dynamic>> cronograma,
    List<Uint8List> fotos,
  ) async {
    try {
      final uid = supabase.auth.currentUser!.id;
      // Localização atual (GPS do técnico, que está na propriedade)
      final pos = _eu ?? await posicaoAtual();
      final culturaPrincipal = culturas.isNotEmpty ? (culturas.first['cultura'] ?? '').toString() : '';
      final pragaNomes = pragas.map((a) => (a['nome'] ?? '').toString().trim()).where((s) => s.isNotEmpty).toList();
      final doencaNomes = doencas.map((a) => (a['nome'] ?? '').toString().trim()).where((s) => s.isNotEmpty).toList();
      final alvo = [...pragaNomes, ...doencaNomes].join(' / ');
      final checkin = {'usuario_id': uid, 'cliente_id': c['id'], 'latitude': pos?.latitude ?? c['latitude'], 'longitude': pos?.longitude ?? c['longitude'], 'observacao': problema};
      final prescricao = {
        'cliente_id': c['id'],
        'tecnico_id': uid,
        'descricao': problema,
        'cultura': culturaPrincipal,
        'alvo': alvo,
        'culturas': culturas,
        'praga': pragaNomes.join(', '),
        'doenca': doencaNomes.join(', '),
        'recomendacoes': recomendacoes,
        'estoque': estoque,
        'cronograma': cronograma,
      };

      if (await estaOnline()) {
        Future<List<String>> subir(List<Uint8List> lista, String tag) async {
          final List<String> us = [];
          for (var i = 0; i < lista.length; i++) {
            final caminho = '$uid/${tag}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
            await supabase.storage.from('fotos').uploadBinary(caminho, lista[i]);
            us.add(supabase.storage.from('fotos').getPublicUrl(caminho));
          }
          return us;
        }

        // Sobe fotos de cada praga/doença e monta [{nome, fotos:[urls]}]
        Future<List<Map<String, dynamic>>> subirAlvos(List<Map<String, dynamic>> lista, String tag) async {
          final out = <Map<String, dynamic>>[];
          for (final a in lista) {
            final urls = await subir((a['fotos'] as List).cast<Uint8List>(), tag);
            out.add({'nome': a['nome'], 'fotos': urls});
          }
          return out;
        }

        final urls = await subir(fotos, 'prob');
        final pragasOut = await subirAlvos(pragas, 'praga');
        final doencasOut = await subirAlvos(doencas, 'doenca');
        await supabase.from('checkins').insert(checkin);
        final presc = Map<String, dynamic>.from(prescricao);
        if (urls.isNotEmpty) presc['fotos'] = urls;
        presc['pragas'] = pragasOut;
        presc['doencas'] = doencasOut;
        final pf = pragasOut.expand((e) => (e['fotos'] as List)).toList();
        final df = doencasOut.expand((e) => (e['fotos'] as List)).toList();
        if (pf.isNotEmpty) presc['praga_fotos'] = pf;
        if (df.isNotEmpty) presc['doenca_fotos'] = df;
        await supabase.from('prescricoes').insert(presc);
        // salva a localização atual do cliente pra futuras visitas
        if (pos != null) {
          try {
            await supabase.rpc('atualizar_local_cliente', params: {'p_id': c['id'], 'p_lat': pos.latitude, 'p_lng': pos.longitude});
          } catch (_) {}
        }
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Visita registrada!'), backgroundColor: AppColors.teal700));
      } else {
        List<Map<String, dynamic>> emB64(List<Map<String, dynamic>> lista) => lista
            .map((a) => {'nome': a['nome'], 'fotosB64': (a['fotos'] as List).cast<Uint8List>().map((b) => base64Encode(b)).toList()})
            .toList();
        await enfileirar({
          'tipo': 'visita',
          'checkin': checkin,
          'prescricao': prescricao,
          'fotos': fotos.map((b) => base64Encode(b)).toList(),
          'pragas': emB64(pragas),
          'doencas': emB64(doencas),
          if (pos != null) 'local': {'id': c['id'], 'lat': pos.latitude, 'lng': pos.longitude},
        });
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