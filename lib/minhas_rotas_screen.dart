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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.teal700, foregroundColor: Colors.white, title: const Text('Minhas rotas')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator(color: AppColors.teal500))
          : _erro != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Erro: $_erro', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFC23A2B)))))
              : _rotas.isEmpty
                  ? const Center(child: Text('Nenhuma rota atribuída ainda.', style: TextStyle(color: AppColors.muted)))
                  : RefreshIndicator(
                      onRefresh: _carregar,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _rotas.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final r = _rotas[i];
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
                              title: Text('${ehHoje ? 'Rota de hoje — ' : 'Rota de '}${formatarData(r['data'])?.split(' às').first ?? r['data']}', style: const TextStyle(fontWeight: FontWeight.w700)),
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
                              trailing: concluida
                                  ? const Icon(Icons.check_circle, color: Color(0xFF2E7D5B))
                                  : IconButton(
                                      icon: const Icon(Icons.done_all, color: AppColors.muted),
                                      tooltip: 'Marcar como concluída',
                                      onPressed: () => _concluir(r),
                                    ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}