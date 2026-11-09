// ============================================================================
//  RotaCampo — Avisos (notificações internas)
//  O vendedor recebe aqui, automaticamente, quando o técnico registra uma
//  prescrição para um cliente da carteira dele. Gestor vê todos.
//  Precisa da tabela 'notificacoes' (rode notificacoes_vendedor.sql).
//  Salve como: lib/notificacoes_screen.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'main.dart'; // supabase, AppColors, UserRole
import 'visitas_screen.dart' show formatarData;

class NotificacoesScreen extends StatefulWidget {
  final UserRole role;
  const NotificacoesScreen({super.key, required this.role});

  @override
  State<NotificacoesScreen> createState() => _NotificacoesScreenState();
}

class _NotificacoesScreenState extends State<NotificacoesScreen> {
  List<Map<String, dynamic>> _lista = [];
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
      final data = await supabase
          .from('notificacoes')
          .select('id, tipo, titulo, corpo, cliente_id, lido, criado_em, clientes(nome, telefone)')
          .order('criado_em', ascending: false)
          .limit(200);
      setState(() {
        _lista = List<Map<String, dynamic>>.from(data);
        _carregando = false;
      });
    } catch (e) {
      setState(() {
        _erro = '$e';
        _carregando = false;
      });
    }
  }

  Future<void> _marcarLida(Map<String, dynamic> n, bool lida) async {
    try {
      await supabase.from('notificacoes').update({'lido': lida}).eq('id', n['id']);
      _carregar();
    } catch (_) {}
  }

  Future<void> _marcarTodasLidas() async {
    try {
      final naoLidas = _lista.where((n) => n['lido'] != true).map((n) => n['id']).toList();
      for (final id in naoLidas) {
        await supabase.from('notificacoes').update({'lido': true}).eq('id', id);
      }
      _carregar();
    } catch (_) {}
  }

  Future<void> _apagar(Map<String, dynamic> n) async {
    try {
      await supabase.from('notificacoes').delete().eq('id', n['id']);
      _carregar();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final naoLidas = _lista.where((n) => n['lido'] != true).length;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.teal700,
        foregroundColor: Colors.white,
        title: const Text('Avisos'),
        actions: [
          if (naoLidas > 0)
            TextButton(
              onPressed: _marcarTodasLidas,
              child: const Text('Marcar todas', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator(color: AppColors.teal500))
          : _erro != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Erro: $_erro', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFC23A2B)))))
              : _lista.isEmpty
                  ? const Center(child: Text('Nenhum aviso ainda.', style: TextStyle(color: AppColors.muted)))
                  : RefreshIndicator(
                      onRefresh: _carregar,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _lista.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final n = _lista[i];
                          final lido = n['lido'] == true;
                          final cli = n['clientes'] as Map<String, dynamic>?;
                          return Container(
                            decoration: BoxDecoration(
                              color: lido ? Colors.white : AppColors.teal500.withOpacity(.07),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: lido ? AppColors.fieldBorder : AppColors.teal500.withOpacity(.4)),
                            ),
                            child: ListTile(
                              onTap: () => _marcarLida(n, !lido),
                              leading: CircleAvatar(
                                backgroundColor: (lido ? AppColors.muted : AppColors.teal700).withOpacity(.14),
                                child: Icon(lido ? Icons.notifications_none : Icons.notifications_active, color: lido ? AppColors.muted : AppColors.teal700),
                              ),
                              title: Text(n['titulo'] ?? 'Aviso', style: TextStyle(fontWeight: lido ? FontWeight.w600 : FontWeight.w800, color: AppColors.ink)),
                              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                if ((n['corpo'] as String?)?.isNotEmpty == true) Text(n['corpo'], style: const TextStyle(color: AppColors.ink)),
                                const SizedBox(height: 2),
                                Text(formatarData(n['criado_em'] as String?) ?? '', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                              ]),
                              trailing: PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert, color: AppColors.muted),
                                onSelected: (v) {
                                  if (v == 'lida') _marcarLida(n, !lido);
                                  if (v == 'apagar') _apagar(n);
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(value: 'lida', child: Text(lido ? 'Marcar como não lida' : 'Marcar como lida')),
                                  const PopupMenuItem(value: 'apagar', child: Text('Apagar')),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
