// ============================================================================
//  RotaCampo — Prescrições (com busca por cliente)
//  Gestor vê todas | Técnico vê as que fez | Vendedor vê as dos clientes DA
//  CARTEIRA dele. A busca no topo filtra pelo nome do cliente.
//  Salve como: lib/prescricoes_screen.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'main.dart'; // supabase, AppColors, UserRole
import 'visitas_screen.dart' show formatarData;
import 'acoes.dart'; // abrirWhatsApp

// Monta o texto da prescrição pro WhatsApp
String _mensagemPrescricao(String nome, String problema, List recs) {
  final b = StringBuffer();
  b.writeln('Olá $nome! Segue a recomendação da sua visita técnica (Porteira Agrocomercial):');
  b.writeln();
  if (problema.trim().isNotEmpty) {
    b.writeln('Problema: $problema');
    b.writeln();
  }
  if (recs.isNotEmpty) {
    b.writeln('Recomendações:');
    for (final r in recs) {
      final prod = r['produto'] ?? '';
      final dose = (r['dosagem'] ?? '').toString();
      b.writeln('- $prod${dose.isNotEmpty ? ' — $dose' : ''}');
    }
    b.writeln();
  }
  b.write('Qualquer dúvida, estamos à disposição!');
  return b.toString();
}

class PrescricoesScreen extends StatefulWidget {
  final UserRole role;
  const PrescricoesScreen({super.key, required this.role});

  @override
  State<PrescricoesScreen> createState() => _PrescricoesScreenState();
}

class _PrescricoesScreenState extends State<PrescricoesScreen> {
  List<Map<String, dynamic>> _lista = [];
  bool _carregando = true;
  String? _erro;
  String _busca = '';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final uid = supabase.auth.currentUser!.id;
    try {
      var q = supabase
          .from('prescricoes')
          .select('id, descricao, criado_em, fotos, recomendacoes, clientes!inner(nome, municipio, telefone, vendedor_id)');

      if (widget.role == UserRole.tecnico) {
        q = q.eq('tecnico_id', uid);
      } else if (widget.role == UserRole.vendedor) {
        q = q.eq('clientes.vendedor_id', uid);
      }

      final data = await q.order('criado_em', ascending: false);
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

  String _nomeCliente(Map<String, dynamic> p) => (p['clientes'] as Map<String, dynamic>?)?['nome'] ?? 'Cliente';

  // Editar a prescrição (só o técnico que criou — garantido pela RLS).
  Future<void> _editar(Map<String, dynamic> p) async {
    final problema = TextEditingController(text: (p['descricao'] ?? '').toString());
    final recsData = (p['recomendacoes'] as List?) ?? [];
    final List<Map<String, TextEditingController>> recs = recsData.isEmpty
        ? [
            {'produto': TextEditingController(), 'dosagem': TextEditingController()}
          ]
        : recsData
            .map<Map<String, TextEditingController>>((r) => {
                  'produto': TextEditingController(text: (r['produto'] ?? '').toString()),
                  'dosagem': TextEditingController(text: (r['dosagem'] ?? '').toString()),
                })
            .toList();
    bool salvando = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Editar prescrição — ${_nomeCliente(p)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
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
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: salvando
                        ? null
                        : () async {
                            setSheet(() => salvando = true);
                            final recsList = recs
                                .map((r) => {'produto': r['produto']!.text.trim(), 'dosagem': r['dosagem']!.text.trim()})
                                .where((r) => (r['produto'] as String).isNotEmpty)
                                .toList();
                            try {
                              final res = await supabase
                                  .from('prescricoes')
                                  .update({'descricao': problema.text.trim(), 'recomendacoes': recsList})
                                  .eq('id', p['id'])
                                  .select('id'); // .select() revela se a RLS bloqueou
                              if (res.isEmpty) throw 'Sem permissão para editar (apenas o técnico que criou).';
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Prescrição atualizada!'), backgroundColor: AppColors.teal700));
                                _carregar();
                              }
                            } catch (e) {
                              setSheet(() => salvando = false);
                              if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Não foi possível salvar: $e')));
                            }
                          },
                    icon: salvando ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_outlined),
                    label: Text(salvando ? 'Salvando...' : 'Salvar alterações'),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.teal700, padding: const EdgeInsets.symmetric(vertical: 14)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _lista
        .where((p) => _nomeCliente(p).toLowerCase().contains(_busca.toLowerCase()))
        .toList();

    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.teal700, foregroundColor: Colors.white, title: const Text('Prescrições')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator(color: AppColors.teal500))
          : _erro != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Erro: $_erro', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFC23A2B)))))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        onChanged: (v) => setState(() => _busca = v),
                        decoration: InputDecoration(
                          hintText: 'Buscar por cliente...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    Expanded(
                      child: filtrados.isEmpty
                          ? Center(
                              child: Text(
                                _lista.isEmpty ? 'Nenhuma prescrição ainda.' : 'Nenhuma prescrição para "$_busca".',
                                style: const TextStyle(color: AppColors.muted),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              itemCount: filtrados.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (_, i) {
                                final p = filtrados[i];
                                final c = p['clientes'] as Map<String, dynamic>?;
                                return Container(
                                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.fieldBorder)),
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        const Icon(Icons.description_outlined, color: AppColors.teal700, size: 20),
                                        const SizedBox(width: 8),
                                        Expanded(child: Text(c?['nome'] ?? 'Cliente', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink))),
                                        if (widget.role == UserRole.tecnico)
                                          IconButton(
                                            icon: const Icon(Icons.edit_outlined, color: AppColors.teal700),
                                            tooltip: 'Editar prescrição',
                                            onPressed: () => _editar(p),
                                          ),
                                        IconButton(
                                          icon: const Icon(Icons.chat, color: Color(0xFF128C7E)),
                                          tooltip: 'Enviar no WhatsApp',
                                          onPressed: () async {
                                            final tel = (c?['telefone'] as String?) ?? '';
                                            final msg = _mensagemPrescricao(c?['nome'] ?? 'cliente', p['descricao'] ?? '', (p['recomendacoes'] as List?) ?? []);
                                            final ok = await abrirWhatsApp(tel, msg);
                                            if (!ok && mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cliente sem telefone cadastrado.')));
                                            }
                                          },
                                        ),
                                      ]),
                                      const SizedBox(height: 4),
                                      Text(formatarData(p['criado_em'] as String?), style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                                      const SizedBox(height: 8),
                                      Text(p['descricao'] ?? '', style: const TextStyle(color: AppColors.ink, height: 1.4)),
                                      if ((p['recomendacoes'] as List?)?.isNotEmpty == true) ...[
                                        const SizedBox(height: 8),
                                        ...(p['recomendacoes'] as List).map((r) => Padding(
                                              padding: const EdgeInsets.only(top: 4),
                                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                                const Icon(Icons.medication_outlined, size: 16, color: AppColors.teal700),
                                                const SizedBox(width: 6),
                                                Expanded(child: Text('${r['produto']}${(r['dosagem'] ?? '').toString().isNotEmpty ? ' — ${r['dosagem']}' : ''}', style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w500))),
                                              ]),
                                            )),
                                      ],
                                      if ((p['fotos'] as List?)?.isNotEmpty == true) ...[
                                        const SizedBox(height: 12),
                                        SizedBox(
                                          height: 76,
                                          child: ListView.separated(
                                            scrollDirection: Axis.horizontal,
                                            itemCount: (p['fotos'] as List).length,
                                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                                            itemBuilder: (_, k) {
                                              final url = (p['fotos'] as List)[k] as String;
                                              return GestureDetector(
                                                onTap: () => showDialog(
                                                  context: context,
                                                  builder: (_) => Dialog(
                                                    child: InteractiveViewer(child: Image.network(url)),
                                                  ),
                                                ),
                                                child: ClipRRect(
                                                  borderRadius: BorderRadius.circular(8),
                                                  child: Image.network(url, width: 76, height: 76, fit: BoxFit.cover,
                                                      errorBuilder: (_, __, ___) => Container(width: 76, height: 76, color: AppColors.field, child: const Icon(Icons.broken_image, color: AppColors.muted))),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}