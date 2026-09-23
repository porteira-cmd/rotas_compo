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