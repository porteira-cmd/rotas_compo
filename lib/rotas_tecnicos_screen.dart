// ============================================================================
//  Porteira sem fronteiras — Rotas dos técnicos (dia ou semana)
//  O técnico (e o gestor) vê as rotas dos técnicos: pra onde vão e quais
//  clientes vão visitar. Só leitura (acompanhamento).
//  Usa: rotas_tecnicos_do_dia(p_data)  e  rotas_tecnicos_periodo(p_ini, p_fim)
//  Salve como: lib/rotas_tecnicos_screen.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'main.dart'; // supabase, AppColors, UserRole

class RotasTecnicosScreen extends StatefulWidget {
  final UserRole role;
  const RotasTecnicosScreen({super.key, required this.role});

  @override
  State<RotasTecnicosScreen> createState() => _RotasTecnicosScreenState();
}

class _RotasTecnicosScreenState extends State<RotasTecnicosScreen> {
  String _modo = 'semana'; // 'dia' | 'semana'
  DateTime _ancora = DateTime.now(); // dia de referência
  List<Map<String, dynamic>> _rotas = [];
  bool _carregando = true;
  String? _erro;

  static const _dds = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
  static const _meses = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  DateTime _soData(DateTime d) => DateTime(d.year, d.month, d.day);
  String _iso(DateTime d) => d.toIso8601String().substring(0, 10);
  String _dm(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  bool get _ehHoje {
    final h = DateTime.now();
    return _ancora.year == h.year && _ancora.month == h.month && _ancora.day == h.day;
  }

  // Segunda e domingo da semana da âncora
  (DateTime, DateTime) _semana() {
    final d = _soData(_ancora);
    final ini = d.subtract(Duration(days: d.weekday - 1));
    return (ini, ini.add(const Duration(days: 6)));
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final dynamic data;
      if (_modo == 'dia') {
        data = await supabase.rpc('rotas_tecnicos_do_dia', params: {'p_data': _iso(_ancora)});
      } else {
        final (ini, fim) = _semana();
        data = await supabase.rpc('rotas_tecnicos_periodo', params: {'p_ini': _iso(ini), 'p_fim': _iso(fim)});
      }
      setState(() {
        _rotas = List<Map<String, dynamic>>.from((data as List?) ?? []);
        _carregando = false;
      });
    } catch (e) {
      setState(() {
        _erro = '$e';
        _carregando = false;
      });
    }
  }

  void _mover(int sinal) {
    setState(() => _ancora = _ancora.add(Duration(days: _modo == 'dia' ? sinal : sinal * 7)));
    _carregar();
  }

  void _trocarModo(String m) {
    if (_modo == m) return;
    setState(() => _modo = m);
    _carregar();
  }

  (String, Color) _selo(String status) => switch (status) {
        'concluida' => ('Concluída', const Color(0xFF2E7D5B)),
        'em_andamento' => ('Em andamento', const Color(0xFFB8860B)),
        _ => ('Pendente', AppColors.coral),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.teal700, foregroundColor: Colors.white, title: const Text('Rotas dos técnicos')),
      body: Column(children: [
        _cabecalho(),
        Expanded(
          child: _carregando
              ? const Center(child: CircularProgressIndicator(color: AppColors.teal500))
              : _erro != null
                  ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Erro: $_erro', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFC23A2B)))))
                  : _rotas.isEmpty
                      ? _vazio()
                      : RefreshIndicator(onRefresh: _carregar, child: _conteudo()),
        ),
      ]),
    );
  }

  Widget _cabecalho() {
    final (ini, fim) = _semana();
    final titulo = _modo == 'dia'
        ? (_ehHoje ? 'Hoje · ${_dm(_ancora)}' : '${_dds[_ancora.weekday - 1]} · ${_dm(_ancora)}')
        : 'Semana · ${_dm(ini)} a ${_dm(fim)}';
    return Container(
      color: AppColors.teal700,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(children: [
        // Alternador Dia / Semana
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: Colors.white.withOpacity(.18), borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Expanded(child: _abaModo('Dia', 'dia')),
            Expanded(child: _abaModo('Semana', 'semana')),
          ]),
        ),
        Row(children: [
          IconButton(onPressed: () => _mover(-1), icon: const Icon(Icons.chevron_left, color: Colors.white)),
          Expanded(child: Text(titulo, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15))),
          IconButton(onPressed: () => _mover(1), icon: const Icon(Icons.chevron_right, color: Colors.white)),
        ]),
      ]),
    );
  }

  Widget _abaModo(String rotulo, String valor) {
    final sel = _modo == valor;
    return InkWell(
      onTap: () => _trocarModo(valor),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(color: sel ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(8)),
        child: Text(rotulo, style: TextStyle(color: sel ? AppColors.teal700 : Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
      ),
    );
  }

  Widget _vazio() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.route_outlined, size: 56, color: AppColors.muted),
            const SizedBox(height: 12),
            Text(_modo == 'dia' ? 'Nenhuma rota de técnico neste dia.' : 'Nenhuma rota de técnico nesta semana.', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
          ]),
        ),
      );

  Widget _conteudo() {
    // No modo semana, agrupa por dia (cabeçalho de data entre os cards).
    if (_modo == 'semana') {
      final Map<String, List<Map<String, dynamic>>> porDia = {};
      for (final r in _rotas) {
        porDia.putIfAbsent((r['data'] ?? '').toString(), () => []).add(r);
      }
      final dias = porDia.keys.toList()..sort();
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final dia in dias) ...[
            _cabecalhoDia(dia),
            const SizedBox(height: 8),
            for (final r in porDia[dia]!) ...[_cardRota(r), const SizedBox(height: 10)],
            const SizedBox(height: 8),
          ],
        ],
      );
    }
    // Modo dia: lista simples
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _rotas.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _cardRota(_rotas[i]),
    );
  }

  Widget _cabecalhoDia(String isoData) {
    final d = DateTime.tryParse(isoData);
    final txt = d == null ? isoData : '${_dds[d.weekday - 1]}, ${d.day} de ${_meses[d.month - 1]}';
    return Row(children: [
      const Icon(Icons.event, size: 16, color: AppColors.teal700),
      const SizedBox(width: 6),
      Text(txt, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink, fontSize: 14)),
    ]);
  }

  Widget _cardRota(Map<String, dynamic> r) {
    final (txt, cor) = _selo((r['status'] ?? 'pendente').toString());
    final paradas = List<Map<String, dynamic>>.from((r['paradas'] as List?) ?? []);
    // "para onde vão": lista curta de municípios distintos
    final municipios = <String>{};
    for (final p in paradas) {
      final m = (p['municipio'] ?? '').toString().trim();
      if (m.isNotEmpty) municipios.add(m);
    }
    final destino = municipios.isEmpty ? '' : municipios.take(3).join(' · ');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.fieldBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(backgroundColor: AppColors.teal700.withOpacity(.12), child: const Icon(Icons.engineering_outlined, color: AppColors.teal700)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((r['tecnico'] ?? 'Técnico').toString(), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink, fontSize: 15)),
              const SizedBox(height: 3),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: cor.withOpacity(.12), borderRadius: BorderRadius.circular(999)),
                  child: Text(txt, style: TextStyle(color: cor, fontWeight: FontWeight.w600, fontSize: 12)),
                ),
                const SizedBox(width: 8),
                Text('${paradas.length} clientes', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ]),
            ]),
          ),
        ]),
        if (destino.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.place_outlined, size: 16, color: AppColors.teal700),
            const SizedBox(width: 6),
            Expanded(child: Text('Vai para: $destino', style: const TextStyle(color: AppColors.ink, fontSize: 13, fontWeight: FontWeight.w600))),
          ]),
        ],
        const SizedBox(height: 10),
        const Divider(height: 1, color: AppColors.fieldBorder),
        const SizedBox(height: 8),
        if (paradas.isEmpty)
          const Text('Rota sem clientes.', style: TextStyle(color: AppColors.muted, fontSize: 13))
        else
          for (var k = 0; k < paradas.length; k++) _linhaParada(k + 1, paradas[k]),
      ]),
    );
  }

  Widget _linhaParada(int ordem, Map<String, dynamic> p) {
    final cliente = (p['cliente'] ?? 'Cliente').toString();
    final municipio = (p['municipio'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: AppColors.teal700, shape: BoxShape.circle),
          child: Text('$ordem', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(cliente, style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600, fontSize: 14)),
            if (municipio.isNotEmpty) Text(municipio, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ]),
        ),
      ]),
    );
  }
}