// ============================================================================
//  RotaCampo — Agenda de visitas (por data)
//  Marque visitas para um cliente numa data/hora, veja agrupado por dia e
//  marque como feita. Gestor vê todas; os demais veem as suas.
//  Precisa da tabela 'agendamentos' (rode perfil_agenda_catalogo.sql).
//  Salve como: lib/agenda_screen.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'main.dart'; // supabase, AppColors, UserRole

class AgendaScreen extends StatefulWidget {
  final UserRole role;
  const AgendaScreen({super.key, required this.role});

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  List<Map<String, dynamic>> _itens = [];
  List<Map<String, dynamic>> _clientes = [];
  List<Map<String, dynamic>> _tecnicos = [];
  bool _carregando = true;
  String? _erro;
  String _busca = '';

  static const _meses = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];

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
          .from('agendamentos')
          .select('id, data_visita, observacao, status, usuario_id, clientes!inner(nome, municipio)')
          .order('data_visita');
      _clientes = List<Map<String, dynamic>>.from(await supabase.from('clientes').select('id, nome').order('nome'));
      // Gestor e vendedor podem atribuir a rota a um técnico.
      if (widget.role == UserRole.gestor || widget.role == UserRole.vendedor) {
        try {
          final tecs = await supabase.rpc('listar_tecnicos');
          _tecnicos = List<Map<String, dynamic>>.from((tecs as List?) ?? []);
        } catch (_) {
          _tecnicos = [];
        }
      }
      setState(() {
        _itens = List<Map<String, dynamic>>.from(data);
        _carregando = false;
      });
    } catch (e) {
      setState(() {
        _erro = '$e';
        _carregando = false;
      });
    }
  }

  String _diaChave(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _tituloDia(DateTime d) {
    final hoje = DateTime.now();
    final amanha = hoje.add(const Duration(days: 1));
    if (d.year == hoje.year && d.month == hoje.month && d.day == hoje.day) return 'Hoje';
    if (d.year == amanha.year && d.month == amanha.month && d.day == amanha.day) return 'Amanhã';
    return '${d.day} de ${_meses[d.month - 1]} de ${d.year}';
  }

  String _hora(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Future<void> _marcar(Map<String, dynamic> a, String status) async {
    try {
      final r = await supabase.from('agendamentos').update({'status': status}).eq('id', a['id']).select('id');
      if (r.isEmpty) throw 'Sem permissão.';
      _carregar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível atualizar: $e')));
    }
  }

  Future<void> _apagar(Map<String, dynamic> a) async {
    try {
      await supabase.from('agendamentos').delete().eq('id', a['id']);
      _carregar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível apagar: $e')));
    }
  }

  Future<void> _novo() async {
    String? clienteId;
    String? clienteNome;
    String? tecnicoId;
    DateTime data = DateTime.now().add(const Duration(days: 1));
    TimeOfDay hora = const TimeOfDay(hour: 8, minute: 0);
    final obs = TextEditingController();
    final buscaCli = TextEditingController();
    bool salvando = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Agendar visita', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
              const SizedBox(height: 16),
              // Cliente com busca
              if (clienteId != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: AppColors.teal500.withOpacity(.10), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.teal500.withOpacity(.4))),
                  child: Row(children: [
                    const Icon(Icons.person, color: AppColors.teal700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(clienteNome ?? '', style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink))),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.close, color: AppColors.muted),
                      onPressed: () => setSheet(() {
                        clienteId = null;
                        clienteNome = null;
                      }),
                    ),
                  ]),
                )
              else ...[
                TextField(
                  controller: buscaCli,
                  decoration: const InputDecoration(labelText: 'Cliente *', hintText: 'Digite o nome...', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
                  onChanged: (_) => setSheet(() {}),
                ),
                const SizedBox(height: 6),
                Builder(builder: (_) {
                  final q = buscaCli.text.trim().toLowerCase();
                  final lista = q.isEmpty
                      ? _clientes
                      : _clientes.where((c) => (c['nome'] ?? '').toString().toLowerCase().contains(q)).toList();
                  return Container(
                    constraints: const BoxConstraints(maxHeight: 190),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.fieldBorder)),
                    child: lista.isEmpty
                        ? const Padding(padding: EdgeInsets.all(14), child: Text('Nenhum cliente encontrado.', style: TextStyle(color: AppColors.muted)))
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: lista.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final c = lista[i];
                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.person_outline, color: AppColors.muted, size: 20),
                                title: Text(c['nome'] ?? '', overflow: TextOverflow.ellipsis),
                                onTap: () => setSheet(() {
                                  clienteId = c['id'] as String;
                                  clienteNome = c['nome'] as String?;
                                  buscaCli.clear();
                                }),
                              );
                            },
                          ),
                  );
                }),
              ],
              if (widget.role == UserRole.gestor || widget.role == UserRole.vendedor) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: tecnicoId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: widget.role == UserRole.vendedor ? 'Mandar a rota para o técnico' : 'Técnico responsável (opcional)', border: const OutlineInputBorder()),
                  items: [
                    DropdownMenuItem(value: null, child: Text(widget.role == UserRole.vendedor ? 'Escolha um técnico...' : 'Eu mesmo')),
                    ..._tecnicos.map((t) => DropdownMenuItem(value: t['id'] as String, child: Text(t['nome'] ?? ''))),
                  ],
                  onChanged: (v) => setSheet(() => tecnicoId = v),
                ),
              ],
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final d = await showDatePicker(context: ctx, initialDate: data, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 365)));
                      if (d != null) setSheet(() => data = DateTime(d.year, d.month, d.day, data.hour, data.minute));
                    },
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text('${data.day}/${data.month}/${data.year}'),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.teal700, side: const BorderSide(color: AppColors.teal500), padding: const EdgeInsets.symmetric(vertical: 13)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final t = await showTimePicker(context: ctx, initialTime: hora);
                      if (t != null) setSheet(() => hora = t);
                    },
                    icon: const Icon(Icons.schedule_outlined, size: 18),
                    label: Text(hora.format(ctx)),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.teal700, side: const BorderSide(color: AppColors.teal500), padding: const EdgeInsets.symmetric(vertical: 13)),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(controller: obs, maxLines: 2, decoration: const InputDecoration(labelText: 'Observação (opcional)', border: OutlineInputBorder(), alignLabelWithHint: true)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: salvando
                      ? null
                      : () async {
                          if (clienteId == null) {
                            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Escolha o cliente.')));
                            return;
                          }
                          setSheet(() => salvando = true);
                          final uid = supabase.auth.currentUser!.id;
                          final quando = DateTime(data.year, data.month, data.day, hora.hour, hora.minute);
                          try {
                            await supabase.from('agendamentos').insert({
                              'cliente_id': clienteId,
                              'usuario_id': tecnicoId ?? uid, // vai pra rota do técnico escolhido
                              'data_visita': quando.toIso8601String(),
                              'observacao': obs.text.trim(),
                              'criado_por': uid,
                            });
                            if (ctx.mounted) Navigator.pop(ctx);
                            _carregar();
                          } catch (e) {
                            setSheet(() => salvando = false);
                            if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Não foi possível agendar: $e')));
                          }
                        },
                  icon: salvando ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check),
                  label: Text(salvando ? 'Salvando...' : 'Agendar'),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.teal700, padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Filtra pelo nome do cliente e agrupa por dia
    final filtrados = _itens.where((a) {
      final nome = ((a['clientes'] as Map<String, dynamic>?)?['nome'] ?? '').toString().toLowerCase();
      return nome.contains(_busca.toLowerCase());
    }).toList();
    final Map<String, List<Map<String, dynamic>>> grupos = {};
    for (final a in filtrados) {
      final d = DateTime.tryParse('${a['data_visita']}')?.toLocal();
      if (d == null) continue;
      grupos.putIfAbsent(_diaChave(d), () => []).add(a);
    }
    final chaves = grupos.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.teal700, foregroundColor: Colors.white, title: const Text('Agenda')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.coral,
        foregroundColor: Colors.white,
        onPressed: _novo,
        icon: const Icon(Icons.add),
        label: const Text('Agendar'),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator(color: AppColors.teal500))
          : _erro != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Erro: $_erro', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFC23A2B)))))
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: TextField(
                      onChanged: (v) => setState(() => _busca = v),
                      decoration: InputDecoration(
                        hintText: 'Buscar por cliente...',
                        prefixIcon: const Icon(Icons.search),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: _itens.isEmpty
                        ? const Center(child: Text('Nenhuma visita agendada.\nToque em "Agendar".', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)))
                        : chaves.isEmpty
                            ? Center(child: Text('Nenhuma visita para "$_busca".', style: const TextStyle(color: AppColors.muted)))
                            : ListView(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                                children: [
                                  for (final k in chaves) ...[
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8, bottom: 8),
                                      child: Text(_tituloDia(DateTime.parse('${k}T00:00:00')), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.teal700, fontSize: 15)),
                                    ),
                                    ...grupos[k]!.map(_cartao),
                                  ],
                                ],
                              ),
                  ),
                ]),
    );
  }

  Widget _cartao(Map<String, dynamic> a) {
    final cli = a['clientes'] as Map<String, dynamic>?;
    final d = DateTime.tryParse('${a['data_visita']}')?.toLocal();
    final status = (a['status'] ?? 'agendada').toString();
    final feito = status == 'concluida';
    final cancelado = status == 'cancelada';
    final cor = feito ? AppColors.teal500 : (cancelado ? AppColors.muted : AppColors.coral);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.fieldBorder)),
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Container(
          width: 52,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(color: cor.withOpacity(.12), borderRadius: BorderRadius.circular(10)),
          child: Column(children: [
            Icon(feito ? Icons.check_circle : (cancelado ? Icons.cancel_outlined : Icons.schedule), color: cor, size: 20),
            const SizedBox(height: 2),
            Text(d != null ? _hora(d) : '--', style: TextStyle(color: cor, fontWeight: FontWeight.w700, fontSize: 12)),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(cli?['nome'] ?? 'Cliente', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, decoration: cancelado ? TextDecoration.lineThrough : null)),
            if ((cli?['municipio'] as String?)?.isNotEmpty == true) Text(cli!['municipio'], style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            if ((a['observacao'] as String?)?.isNotEmpty == true) Padding(padding: const EdgeInsets.only(top: 2), child: Text(a['observacao'], style: const TextStyle(color: AppColors.muted, fontSize: 12))),
            if (feito) const Padding(padding: EdgeInsets.only(top: 2), child: Text('Concluída', style: TextStyle(color: AppColors.teal700, fontSize: 11, fontWeight: FontWeight.w700))),
          ]),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: AppColors.muted),
          onSelected: (v) {
            if (v == 'feita') _marcar(a, 'concluida');
            if (v == 'reabrir') _marcar(a, 'agendada');
            if (v == 'cancelar') _marcar(a, 'cancelada');
            if (v == 'apagar') _apagar(a);
          },
          itemBuilder: (_) => [
            if (!feito) const PopupMenuItem(value: 'feita', child: Text('Marcar como feita')),
            if (feito || cancelado) const PopupMenuItem(value: 'reabrir', child: Text('Reabrir')),
            if (!cancelado && !feito) const PopupMenuItem(value: 'cancelar', child: Text('Cancelar')),
            const PopupMenuItem(value: 'apagar', child: Text('Apagar')),
          ],
        ),
      ]),
    );
  }
}