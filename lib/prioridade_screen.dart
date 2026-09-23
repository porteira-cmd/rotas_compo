// ============================================================================
//  RotaCampo — Precisa de visita (prioridade)
//  Lista os clientes por tempo sem visita (nunca / mais antigos primeiro),
//  com filtros. Selecione os urgentes e monte a rota. Salve como:
//  lib/prioridade_screen.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'main.dart'; // supabase, AppColors, UserRole
import 'acoes.dart'; // abrirRotaNoMaps
import 'rota_execucao_screen.dart'; // executar rota
import 'cliente_historico_screen.dart'; // histórico
import 'avisar_clientes.dart'; // avisar clientes via WhatsApp

class PrioridadeScreen extends StatefulWidget {
  final UserRole role;
  const PrioridadeScreen({super.key, required this.role});

  @override
  State<PrioridadeScreen> createState() => _PrioridadeScreenState();
}

class _PrioridadeScreenState extends State<PrioridadeScreen> {
  List<Map<String, dynamic>> _clientes = [];
  final List<Map<String, dynamic>> _rota = []; // selecionados pra rota
  bool _carregando = true;
  String? _erro;
  int _filtro = 15; // 0 = todos | 15 | 30 | -1 = nunca

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final clientes = List<Map<String, dynamic>>.from(await supabase
          .from('clientes')
          .select('id, nome, municipio, telefone, latitude, longitude')
          .not('latitude', 'is', null)
          .not('longitude', 'is', null));

      final checkins = List<Map<String, dynamic>>.from(await supabase.from('checkins').select('cliente_id, feito_em'));

      // última visita de cada cliente
      final Map<dynamic, DateTime> ultima = {};
      for (final ck in checkins) {
        final d = DateTime.tryParse(ck['feito_em'] ?? '');
        if (d == null) continue;
        final id = ck['cliente_id'];
        if (!ultima.containsKey(id) || d.isAfter(ultima[id]!)) ultima[id] = d;
      }

      // calcula dias sem visita (null = nunca)
      for (final c in clientes) {
        final u = ultima[c['id']];
        c['_dias'] = u == null ? null : DateTime.now().difference(u).inDays;
      }

      // ordena: nunca primeiro, depois mais dias
      clientes.sort((a, b) {
        final da = a['_dias'] == null ? 1 << 30 : a['_dias'] as int;
        final db = b['_dias'] == null ? 1 << 30 : b['_dias'] as int;
        return db.compareTo(da);
      });

      setState(() {
        _clientes = clientes;
        _carregando = false;
      });
    } catch (e) {
      setState(() {
        _erro = '$e';
        _carregando = false;
      });
    }
  }

  bool _passaFiltro(Map c) {
    final d = c['_dias'];
    switch (_filtro) {
      case -1:
        return d == null; // nunca visitados
      case 15:
        return d == null || d > 15;
      case 30:
        return d == null || d > 30;
      default:
        return true; // todos
    }
  }

  int _pos(Map c) => _rota.indexWhere((r) => r['id'] == c['id']);
  void _alternar(Map<String, dynamic> c) => setState(() {
        _pos(c) >= 0 ? _rota.removeWhere((r) => r['id'] == c['id']) : _rota.add(c);
      });

  (String, Color) _selo(dynamic dias) {
    if (dias == null) return ('Nunca visitado', const Color(0xFFC23A2B));
    if (dias > 30) return ('Há $dias dias', const Color(0xFFC23A2B));
    if (dias > 15) return ('Há $dias dias', const Color(0xFFB8860B));
    return ('Há $dias dias', const Color(0xFF2E7D5B));
  }

  @override
  Widget build(BuildContext context) {
    final lista = _clientes.where(_passaFiltro).toList();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.teal700,
        foregroundColor: Colors.white,
        title: const Text('Precisa de visita'),
        actions: [
          if (_rota.isNotEmpty) IconButton(icon: const Icon(Icons.clear_all), onPressed: () => setState(_rota.clear)),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator(color: AppColors.teal500))
          : _erro != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Erro: $_erro', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFC23A2B)))))
              : Column(
                  children: [
                    SizedBox(
                      height: 56,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        children: [
                          _chip('Todos', 0),
                          _chip('+15 dias', 15),
                          _chip('+30 dias', 30),
                          _chip('Nunca', -1),
                        ],
                      ),
                    ),
                    Expanded(
                      child: lista.isEmpty
                          ? const Center(child: Text('Nenhum cliente neste filtro. 🎉', style: TextStyle(color: AppColors.muted)))
                          : ListView.builder(
                              itemCount: lista.length,
                              itemBuilder: (_, i) {
                                final c = lista[i];
                                final sel = _pos(c) >= 0;
                                final (txt, cor) = _selo(c['_dias']);
                                return ListTile(
                                  onTap: () => _alternar(c),
                                  leading: sel
                                      ? CircleAvatar(radius: 16, backgroundColor: AppColors.teal700, child: Text('${_pos(c) + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)))
                                      : const CircleAvatar(radius: 16, backgroundColor: AppColors.field, child: Icon(Icons.add, color: AppColors.muted, size: 18)),
                                  title: Text(c['nome'] ?? '', style: TextStyle(fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
                                  subtitle: Row(children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(color: cor.withOpacity(.12), borderRadius: BorderRadius.circular(999)),
                                      child: Text(txt, style: TextStyle(color: cor, fontWeight: FontWeight.w600, fontSize: 12)),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(c['municipio'] ?? '', style: const TextStyle(color: AppColors.muted), overflow: TextOverflow.ellipsis)),
                                  ]),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.history, color: AppColors.muted),
                                    tooltip: 'Histórico',
                                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ClienteHistoricoScreen(cliente: c))),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
      bottomNavigationBar: _rota.isEmpty ? null : _barra(),
    );
  }

  Widget _chip(String label, int valor) {
    final ativo = _filtro == valor;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: ativo,
        onSelected: (_) => setState(() => _filtro = valor),
        selectedColor: AppColors.teal700,
        labelStyle: TextStyle(color: ativo ? Colors.white : AppColors.ink, fontWeight: FontWeight.w600),
        backgroundColor: Colors.white,
        shape: StadiumBorder(side: BorderSide(color: ativo ? AppColors.teal700 : AppColors.fieldBorder)),
      ),
    );
  }

  Widget _barra() {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(.12), blurRadius: 10)]),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
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
      ]),
    );
  }
}