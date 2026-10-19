// ============================================================================
//  RotaCampo — Montar rota
//  • Clientes agrupados por CIDADE (cada município é uma seção)
//  • Botão "10 mais próximos": escolhe um cliente âncora e seleciona
//    ele + os 9 vizinhos mais próximos, em ordem de distância.
//  • Continua podendo: abrir no Google Maps, iniciar no app, avisar no
//    WhatsApp e (gestor) enviar a rota do dia pro técnico.
//  Salve como: lib/rotas_screen.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart'; // cálculo de distância (já instalado)
import 'main.dart'; // supabase, AppColors, UserRole
import 'acoes.dart'; // abrirRotaNoMaps
import 'rota_execucao_screen.dart'; // executar rota no app
import 'avisar_clientes.dart'; // avisar clientes via WhatsApp

class RotasScreen extends StatefulWidget {
  final UserRole role;
  const RotasScreen({super.key, required this.role});

  @override
  State<RotasScreen> createState() => _RotasScreenState();
}

class _RotasScreenState extends State<RotasScreen> {
  List<Map<String, dynamic>> _clientes = [];
  final List<Map<String, dynamic>> _rota = []; // paradas escolhidas, em ordem
  List<Map<String, dynamic>> _tecnicos = []; // para o gestor atribuir
  bool _carregando = true;
  String? _erro;
  String _busca = '';

  static const Distance _distancia = Distance();

  @override
  void initState() {
    super.initState();
    _carregar();
    if (widget.role == UserRole.gestor) _carregarTecnicos();
  }

  Future<void> _carregarTecnicos() async {
    try {
      final data = await supabase.from('usuarios').select('id, nome').eq('perfil', 'tecnico').order('nome');
      setState(() => _tecnicos = List<Map<String, dynamic>>.from(data));
    } catch (_) {}
  }

  Future<void> _carregar() async {
    try {
      final data = await supabase
          .from('clientes')
          .select('id, nome, telefone, municipio, latitude, longitude')
          .not('latitude', 'is', null)
          .not('longitude', 'is', null)
          .order('nome');
      setState(() {
        _clientes = List<Map<String, dynamic>>.from(data);
        _carregando = false;
      });
    } catch (e) {
      setState(() {
        _erro = '$e';
        _carregando = false;
      });
    }
  }

  // ---- seleção ------------------------------------------------------------
  int _posicao(Map c) => _rota.indexWhere((r) => r['id'] == c['id']);
  bool _selecionado(Map c) => _posicao(c) >= 0;

  void _alternar(Map<String, dynamic> c) {
    setState(() {
      _selecionado(c) ? _rota.removeWhere((r) => r['id'] == c['id']) : _rota.add(c);
    });
  }

  LatLng _ponto(Map c) => LatLng((c['latitude'] as num).toDouble(), (c['longitude'] as num).toDouble());
  double _km(Map a, Map b) => _distancia.as(LengthUnit.Kilometer, _ponto(a), _ponto(b));

  String _cidadeDe(Map c) => ((c['municipio'] as String?)?.trim().isNotEmpty == true) ? c['municipio'] : 'Sem cidade';

  // ---- 10 mais próximos ---------------------------------------------------
  Future<void> _dezMaisProximos() async {
    // 1) escolher o cliente de referência (âncora)
    final ancora = await _escolherAncora();
    if (ancora == null) return;

    // 2) ordenar todos pela distância até a âncora e pegar os 10 primeiros
    final lista = List<Map<String, dynamic>>.from(_clientes);
    lista.sort((a, b) => _km(ancora, a).compareTo(_km(ancora, b)));
    final grupo = lista.take(10).toList(); // a própria âncora entra (distância 0)

    setState(() {
      _rota
        ..clear()
        ..addAll(grupo);
    });
    if (mounted) {
      final distMax = grupo.isEmpty ? 0.0 : _km(ancora, grupo.last);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${grupo.length} clientes mais próximos de "${ancora['nome']}" (até ${distMax.toStringAsFixed(1)} km).'),
        backgroundColor: AppColors.teal700,
      ));
    }
  }

  Future<Map<String, dynamic>?> _escolherAncora() {
    String busca = '';
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final filtrados = _clientes.where((c) => (c['nome'] as String).toLowerCase().contains(busca.toLowerCase())).toList();
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.7,
              child: Column(children: [
                const SizedBox(height: 12),
                Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.fieldBorder, borderRadius: BorderRadius.circular(999))),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Ponto de partida', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                    const SizedBox(height: 4),
                    const Text('Escolha um cliente — vou montar a rota com ele e os 9 mais próximos.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                    const SizedBox(height: 12),
                    TextField(
                      autofocus: true,
                      onChanged: (v) => setS(() => busca = v),
                      decoration: InputDecoration(hintText: 'Buscar cliente...', prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                    ),
                  ]),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: filtrados.length,
                    itemBuilder: (_, i) {
                      final c = filtrados[i];
                      return ListTile(
                        leading: const Icon(Icons.my_location, color: AppColors.coral),
                        title: Text(c['nome'] ?? ''),
                        subtitle: Text(_cidadeDe(c)),
                        onTap: () => Navigator.pop(ctx, c),
                      );
                    },
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  // ---- adicionar cidade inteira ------------------------------------------
  void _adicionarCidade(List<Map<String, dynamic>> daCidade) {
    setState(() {
      for (final c in daCidade) {
        if (!_selecionado(c)) _rota.add(c);
      }
    });
  }

  // ---- enviar pro técnico (gestor) ---------------------------------------
  Future<void> _enviarParaTecnico() async {
    if (_tecnicos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhum técnico cadastrado. Cadastre um na tela Equipe.')));
      return;
    }
    String tecnicoId = _tecnicos.first['id'] as String;
    DateTime dataRota = DateTime.now();
    String dois(int n) => n.toString().padLeft(2, '0');

    final enviar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Enviar rota do dia'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${_rota.length} paradas serão enviadas.', style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: tecnicoId,
              decoration: const InputDecoration(labelText: 'Técnico responsável', border: OutlineInputBorder()),
              items: _tecnicos.map((t) => DropdownMenuItem(value: t['id'] as String, child: Text(t['nome'] ?? ''))).toList(),
              onChanged: (v) => setD(() => tecnicoId = v!),
            ),
            const SizedBox(height: 14),
            Row(children: [
              const Icon(Icons.event, color: AppColors.muted, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('Dia: ${dois(dataRota.day)}/${dois(dataRota.month)}/${dataRota.year}')),
              TextButton(
                onPressed: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: dataRota,
                    firstDate: DateTime.now().subtract(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 60)),
                  );
                  if (d != null) setD(() => dataRota = d);
                },
                child: const Text('Trocar'),
              ),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enviar')),
          ],
        ),
      ),
    );
    if (enviar != true) return;

    try {
      final dia = dataRota.toIso8601String().substring(0, 10);
      final nova = await supabase.from('rotas').insert({'usuario_id': tecnicoId, 'data': dia, 'status': 'pendente'}).select('id').single();
      final rotaId = nova['id'];
      final paradas = <Map<String, dynamic>>[];
      for (var i = 0; i < _rota.length; i++) {
        paradas.add({'rota_id': rotaId, 'cliente_id': _rota[i]['id'], 'ordem': i + 1});
      }
      await supabase.from('rota_paradas').insert(paradas);

      final nome = _tecnicos.firstWhere((t) => t['id'] == tecnicoId)['nome'];
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Rota enviada para $nome!'), backgroundColor: AppColors.teal700));
        setState(() => _rota.clear());
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível enviar: $e')));
    }
  }

  // ---- monta a lista agrupada por cidade ---------------------------------
  // Retorna uma lista mista: String (nome da cidade) ou Map (cliente).
  List<dynamic> _itensAgrupados() {
    final filtrados = _clientes.where((c) => (c['nome'] as String).toLowerCase().contains(_busca.toLowerCase())).toList();
    final Map<String, List<Map<String, dynamic>>> porCidade = {};
    for (final c in filtrados) {
      porCidade.putIfAbsent(_cidadeDe(c), () => []).add(c);
    }
    final cidades = porCidade.keys.toList()..sort();
    final itens = <dynamic>[];
    for (final cidade in cidades) {
      itens.add(cidade); // cabeçalho
      itens.addAll(porCidade[cidade]!);
    }
    return itens;
  }

  @override
  Widget build(BuildContext context) {
    final itens = _itensAgrupados();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.teal700,
        foregroundColor: Colors.white,
        title: const Text('Montar rota'),
        actions: [
          if (_rota.isNotEmpty) IconButton(icon: const Icon(Icons.clear_all), tooltip: 'Limpar', onPressed: () => setState(_rota.clear)),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator(color: AppColors.teal500))
          : _erro != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Erro: $_erro', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFC23A2B)))))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: TextField(
                        onChanged: (v) => setState(() => _busca = v),
                        decoration: InputDecoration(
                          hintText: 'Buscar cliente...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    // Botão: 10 mais próximos
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _clientes.isEmpty ? null : _dezMaisProximos,
                          icon: const Icon(Icons.near_me_outlined, size: 18),
                          label: const Text('Montar com os 10 mais próximos'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.teal700,
                            side: const BorderSide(color: AppColors.teal500),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: itens.isEmpty
                          ? const Center(child: Text('Nenhum cliente encontrado.', style: TextStyle(color: AppColors.muted)))
                          : ListView.builder(
                              itemCount: itens.length,
                              itemBuilder: (_, i) {
                                final item = itens[i];
                                // Cabeçalho de cidade
                                if (item is String) {
                                  final daCidade = _clientes.where((c) => _cidadeDe(c) == item && (c['nome'] as String).toLowerCase().contains(_busca.toLowerCase())).toList();
                                  return Container(
                                    color: AppColors.field,
                                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                                    child: Row(children: [
                                      const Icon(Icons.location_city, size: 18, color: AppColors.teal700),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text('$item  ·  ${daCidade.length}',
                                            style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink, fontSize: 14)),
                                      ),
                                      TextButton.icon(
                                        onPressed: () => _adicionarCidade(daCidade),
                                        icon: const Icon(Icons.playlist_add, size: 18),
                                        label: const Text('Todos'),
                                        style: TextButton.styleFrom(foregroundColor: AppColors.teal700),
                                      ),
                                    ]),
                                  );
                                }
                                // Cliente
                                final c = item as Map<String, dynamic>;
                                final pos = _posicao(c);
                                final sel = pos >= 0;
                                return ListTile(
                                  onTap: () => _alternar(c),
                                  leading: sel
                                      ? CircleAvatar(
                                          backgroundColor: AppColors.teal700,
                                          radius: 16,
                                          child: Text('${pos + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                                        )
                                      : const CircleAvatar(backgroundColor: AppColors.field, radius: 16, child: Icon(Icons.add, color: AppColors.muted, size: 18)),
                                  title: Text(c['nome'] ?? '', style: TextStyle(fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
                                  subtitle: Text(c['municipio'] ?? ''),
                                  trailing: sel ? const Icon(Icons.check_circle, color: AppColors.teal500) : null,
                                );
                              },
                            ),
                    ),
                  ],
                ),
      bottomNavigationBar: _rota.isEmpty ? null : _barraInferior(),
    );
  }

  Widget _barraInferior() {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(.12), blurRadius: 10)]),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            const Icon(Icons.route, color: AppColors.teal700),
            const SizedBox(width: 8),
            Text('${_rota.length} paradas selecionadas', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => abrirRotaNoMaps(_rota.map((c) => [(c['latitude'] as num).toDouble(), (c['longitude'] as num).toDouble()]).toList()),
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('Google Maps'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.coral, padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RotaExecucaoScreen(paradas: List.from(_rota)))),
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Iniciar'),
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
          if (widget.role == UserRole.gestor) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _enviarParaTecnico,
                icon: const Icon(Icons.send, size: 18),
                label: const Text('Enviar para técnico'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.teal700, padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}