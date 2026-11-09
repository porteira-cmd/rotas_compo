// ============================================================================
//  RotaCampo — Minhas rotas (rotas atribuídas)
//  O Técnico vê as rotas que o Gestor enviou pra ele, abre e executa.
//  O Gestor vê todas as rotas (acompanhamento).
//  Salve como: lib/minhas_rotas_screen.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'main.dart'; // supabase, AppColors, UserRole
import 'rota_mapa_screen.dart'; // abre a rota no mapa (com botão Executar)
import 'visitas_screen.dart' show formatarData;

class MinhasRotasScreen extends StatefulWidget {
  final UserRole role;
  const MinhasRotasScreen({super.key, required this.role});

  @override
  State<MinhasRotasScreen> createState() => _MinhasRotasScreenState();
}

class _MinhasRotasScreenState extends State<MinhasRotasScreen> {
  List<Map<String, dynamic>> _rotas = [];
  bool _carregando = true;
  String? _erro;
  String _filtro = 'semana'; // 'semana' | 'todas' (usado pelo técnico)

  static const _diasSemana = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
  DateTime _soData(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime? _dataRota(Map r) => DateTime.tryParse((r['data'] ?? '').toString());

  // Segunda e domingo da semana atual
  (DateTime, DateTime) _semanaAtual() {
    final hoje = _soData(DateTime.now());
    final ini = hoje.subtract(Duration(days: hoje.weekday - 1));
    return (ini, ini.add(const Duration(days: 6)));
  }

  String _tituloData(Map r) {
    final d = _dataRota(r);
    final base = formatarData(r['data'])?.split(' às').first ?? '${r['data']}';
    if (d == null) return base;
    return '${_diasSemana[d.weekday - 1]}, $base';
  }

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      // A RLS já filtra: Técnico vê as suas; Gestor vê todas.
      final data = await supabase
          .from('rotas')
          .select('id, data, status, rota_paradas(count)')
          .order('data', ascending: false);
      setState(() {
        _rotas = List<Map<String, dynamic>>.from(data);
        _carregando = false;
      });
    } catch (e) {
      setState(() {
        _erro = '$e';
        _carregando = false;
      });
    }
  }

  int _qtdParadas(Map r) {
    final rp = r['rota_paradas'];
    if (rp is List && rp.isNotEmpty && rp.first is Map && rp.first['count'] != null) {
      return rp.first['count'] as int;
    }
    return 0;
  }

  (String, Color) _selo(String status) => switch (status) {
        'concluida' => ('Concluída', const Color(0xFF2E7D5B)),
        'em_andamento' => ('Em andamento', const Color(0xFFB8860B)),
        _ => ('Pendente', AppColors.coral),
      };

  // Abre a rota: carrega as paradas e vai pra tela de execução
  Future<void> _abrir(Map<String, dynamic> rota) async {
    try {
      final paradas = await supabase
          .from('rota_paradas')
          .select('ordem, clientes!inner(id, nome, municipio, latitude, longitude)')
          .eq('rota_id', rota['id'])
          .order('ordem');

      final lista = (paradas as List).map((p) => Map<String, dynamic>.from(p['clientes'])).toList();
      if (lista.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Esta rota não tem paradas.')));
        return;
      }
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => RotaMapaScreen(paradas: lista, rotaId: rota['id'])));
      _carregar(); // atualiza ao voltar (mostra a rota já como "Concluída")
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao abrir a rota: $e')));
    }
  }

  Future<void> _concluir(Map<String, dynamic> rota) async {
    try {
      await supabase.from('rotas').update({'status': 'concluida'}).eq('id', rota['id']);
      _carregar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível concluir: $e')));
    }
  }

  // Apagar rota (somente gestor) — usa a função apagar_rota no banco
  Future<void> _apagar(Map<String, dynamic> rota) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar rota'),
        content: const Text('Apagar esta rota e suas paradas? As visitas já registradas não são apagadas.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC23A2B)), child: const Text('Apagar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await supabase.rpc('apagar_rota', params: {'p_id': rota['id']});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rota apagada.'), backgroundColor: AppColors.teal700));
      _carregar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível apagar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ehTecnico = widget.role != UserRole.gestor;
    final (iniSem, fimSem) = _semanaAtual();

    // Lista a mostrar: técnico pode filtrar pela semana atual
    var lista = _rotas;
    if (ehTecnico && _filtro == 'semana') {
      lista = _rotas.where((r) {
        final d = _dataRota(r);
        if (d == null) return false;
        final dd = _soData(d);
        return !dd.isBefore(iniSem) && !dd.isAfter(fimSem);
      }).toList()
        ..sort((a, b) => '${a['data']}'.compareTo('${b['data']}')); // na ordem dos dias
    }

    final vazio = _filtro == 'semana' && ehTecnico
        ? 'Nenhuma rota para esta semana.'
        : 'Nenhuma rota atribuída ainda.';

    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.teal700, foregroundColor: Colors.white, title: Text(widget.role == UserRole.gestor ? 'Rotas da equipe' : 'Minhas rotas')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator(color: AppColors.teal500))
          : _erro != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Erro: $_erro', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFC23A2B)))))
              : Column(children: [
                  if (ehTecnico) _seletorSemana(iniSem, fimSem),
                  Expanded(
                    child: lista.isEmpty
                        ? Center(child: Text(vazio, style: const TextStyle(color: AppColors.muted)))
                        : RefreshIndicator(
                            onRefresh: _carregar,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: lista.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (_, i) {
                                final r = lista[i];
                                final (txt, cor) = _selo(r['status'] ?? 'pendente');
                                final concluida = r['status'] == 'concluida';
                                final hoje = DateTime.now().toIso8601String().substring(0, 10);
                                final ehHoje = (r['data'] ?? '').toString() == hoje;
                                return Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: ehHoje ? AppColors.teal500 : AppColors.fieldBorder, width: ehHoje ? 1.8 : 1),
                            ),
                            child: ListTile(
                              onTap: () => _abrir(r),
                              leading: const CircleAvatar(backgroundColor: Color(0x1A0E6157), child: Icon(Icons.route, color: AppColors.teal700)),
                              title: Text('${ehHoje ? 'Hoje — ' : ''}${_tituloData(r)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Row(children: [
                                if (ehHoje) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(color: AppColors.teal700, borderRadius: BorderRadius.circular(999)),
                                    child: const Text('HOJE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11)),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(color: cor.withOpacity(.12), borderRadius: BorderRadius.circular(999)),
                                  child: Text(txt, style: TextStyle(color: cor, fontWeight: FontWeight.w600, fontSize: 12)),
                                ),
                                const SizedBox(width: 8),
                                Text('${_qtdParadas(r)} paradas', style: const TextStyle(color: AppColors.muted)),
                              ]),
                              trailing: widget.role == UserRole.gestor
                                  ? PopupMenuButton<String>(
                                      icon: const Icon(Icons.more_vert, color: AppColors.muted),
                                      onSelected: (v) {
                                        if (v == 'concluir') _concluir(r);
                                        if (v == 'apagar') _apagar(r);
                                      },
                                      itemBuilder: (_) => [
                                        if (!concluida) const PopupMenuItem(value: 'concluir', child: Text('Marcar como concluída')),
                                        const PopupMenuItem(value: 'apagar', child: Text('Apagar rota')),
                                      ],
                                    )
                                  : (concluida
                                      ? const Icon(Icons.check_circle, color: Color(0xFF2E7D5B))
                                      : IconButton(
                                          icon: const Icon(Icons.done_all, color: AppColors.muted),
                                          tooltip: 'Marcar como concluída',
                                          onPressed: () => _concluir(r),
                                        )),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ]),
    );
  }

  // Seletor "Esta semana / Todas" + faixa com o intervalo da semana
  Widget _seletorSemana(DateTime ini, DateTime fim) {
    String d(DateTime x) => '${x.day.toString().padLeft(2, '0')}/${x.month.toString().padLeft(2, '0')}';
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: _chipFiltro('Esta semana', 'semana')),
          const SizedBox(width: 8),
          Expanded(child: _chipFiltro('Todas', 'todas')),
        ]),
        if (_filtro == 'semana') ...[
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.date_range, size: 16, color: AppColors.muted),
            const SizedBox(width: 6),
            Text('${d(ini)} a ${d(fim)}', style: const TextStyle(color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ],
      ]),
    );
  }

  Widget _chipFiltro(String rotulo, String valor) {
    final sel = _filtro == valor;
    return InkWell(
      onTap: () => setState(() => _filtro = valor),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: sel ? AppColors.teal700 : AppColors.field,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: sel ? AppColors.teal700 : AppColors.fieldBorder),
        ),
        child: Text(rotulo, style: TextStyle(color: sel ? Colors.white : AppColors.ink, fontWeight: FontWeight.w700, fontSize: 13)),
      ),
    );
  }
}