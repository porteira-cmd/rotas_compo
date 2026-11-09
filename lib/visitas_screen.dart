// ============================================================================
//  RotaCampo — Visitas (histórico dos check-ins)
//  Gestor vê todas | Técnico vê as suas | Vendedor vê as da carteira dele
//  Salve como: lib/visitas_screen.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'main.dart'; // supabase, AppColors, UserRole

String formatarData(String? iso) {
  if (iso == null) return '';
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '';
  String dois(int n) => n.toString().padLeft(2, '0');
  return '${dois(d.day)}/${dois(d.month)}/${d.year} às ${dois(d.hour)}:${dois(d.minute)}';
}

class VisitasScreen extends StatefulWidget {
  final UserRole role;
  const VisitasScreen({super.key, required this.role});

  @override
  State<VisitasScreen> createState() => _VisitasScreenState();
}

class _VisitasScreenState extends State<VisitasScreen> {
  List<Map<String, dynamic>> _visitas = [];
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final uid = supabase.auth.currentUser!.id;
    try {
      var q = supabase
          .from('checkins')
          .select('id, feito_em, observacao, clientes!inner(nome, municipio, vendedor_id)');

      if (widget.role == UserRole.tecnico) {
        q = q.eq('usuario_id', uid);
      } else if (widget.role == UserRole.vendedor) {
        q = q.eq('clientes.vendedor_id', uid);
      }

      final data = await q.order('feito_em', ascending: false);
      setState(() {
        _visitas = List<Map<String, dynamic>>.from(data);
        _carregando = false;
      });
    } catch (e) {
      setState(() {
        _erro = '$e';
        _carregando = false;
      });
    }
  }

  // Apagar visita/check-in (só gestor) — usa a função apagar_checkin no banco
  Future<void> _apagarVisita(Map<String, dynamic> v) async {
    final nome = (v['clientes'] as Map<String, dynamic>?)?['nome'] ?? 'cliente';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar visita'),
        content: Text('Apagar a visita de $nome? Essa ação não pode ser desfeita. (A prescrição ligada, se houver, não é apagada por aqui.)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC23A2B)), child: const Text('Apagar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await supabase.rpc('apagar_checkin', params: {'p_id': v['id']});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Visita apagada.'), backgroundColor: AppColors.teal700));
      _carregar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível apagar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.teal700, foregroundColor: Colors.white, title: const Text('Visitas')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator(color: AppColors.teal500))
          : _erro != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Erro: $_erro', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFC23A2B)))))
              : _visitas.isEmpty
                  ? const Center(child: Text('Nenhuma visita registrada ainda.', style: TextStyle(color: AppColors.muted)))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _visitas.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final v = _visitas[i];
                        final c = v['clientes'] as Map<String, dynamic>?;
                        return Container(
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.fieldBorder)),
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                const Icon(Icons.check_circle, color: Color(0xFF2E7D5B), size: 20),
                                const SizedBox(width: 8),
                                Expanded(child: Text(c?['nome'] ?? 'Cliente', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink))),
                                if (widget.role == UserRole.gestor)
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    icon: const Icon(Icons.delete_outline, color: Color(0xFFC23A2B), size: 20),
                                    tooltip: 'Apagar visita',
                                    onPressed: () => _apagarVisita(v),
                                  ),
                              ]),
                              const SizedBox(height: 4),
                              Text(formatarData(v['feito_em'] as String?), style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                              if ((v['observacao'] as String?)?.isNotEmpty == true) ...[
                                const SizedBox(height: 8),
                                Text(v['observacao'], style: const TextStyle(color: AppColors.ink)),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
    );
  }
}