// ============================================================================
//  RotaCampo — Catálogo de produtos
//  Gestor e Técnico cadastram/editam/apagam produtos usados nas prescrições.
//  Precisa da tabela 'produtos' (rode produtos.sql).
//  Salve como: lib/produtos_screen.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'main.dart'; // supabase, AppColors, UserRole

const List<String> kCategorias = ['Fungicida', 'Inseticida', 'Herbicida', 'Acaricida', 'Fertilizante', 'Adjuvante', 'Outro'];
const List<String> kUnidades = ['L/ha', 'kg/ha', 'mL/20L', 'g/20L', 'mL/planta', 'g/planta', 'L/100L', '%'];

class ProdutosScreen extends StatefulWidget {
  final UserRole role;
  const ProdutosScreen({super.key, required this.role});

  @override
  State<ProdutosScreen> createState() => _ProdutosScreenState();
}

class _ProdutosScreenState extends State<ProdutosScreen> {
  List<Map<String, dynamic>> _lista = [];
  bool _carregando = true;
  String? _erro;
  String _busca = '';

  bool get _podeEditar => widget.role == UserRole.gestor || widget.role == UserRole.tecnico;

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
      final data = await supabase.from('produtos').select('id, nome, principio_ativo, categoria, unidade, carencia, dose_recomendada').order('nome');
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

  Future<void> _editar([Map<String, dynamic>? existente]) async {
    final nome = TextEditingController(text: existente?['nome'] ?? '');
    final principio = TextEditingController(text: existente?['principio_ativo'] ?? '');
    final carencia = TextEditingController(text: (existente?['carencia'] ?? '').toString());
    final doseRec = TextEditingController(text: (existente?['dose_recomendada'] ?? '').toString());
    String categoria = existente?['categoria'] ?? kCategorias.last;
    String unidade = existente?['unidade'] ?? kUnidades.first;
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
              Text(existente == null ? 'Novo produto' : 'Editar produto', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
              const SizedBox(height: 16),
              TextField(controller: nome, decoration: const InputDecoration(labelText: 'Nome do produto *', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: principio, decoration: const InputDecoration(labelText: 'Princípio ativo', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: categoria,
                decoration: const InputDecoration(labelText: 'Categoria', border: OutlineInputBorder()),
                items: kCategorias.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => setSheet(() => categoria = v!),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: kUnidades.contains(unidade) ? unidade : kUnidades.first,
                    decoration: const InputDecoration(labelText: 'Unidade da dose', border: OutlineInputBorder()),
                    items: kUnidades.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                    onChanged: (v) => setSheet(() => unidade = v!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(controller: carencia, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Carência (dias)', border: OutlineInputBorder())),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(controller: doseRec, decoration: const InputDecoration(labelText: 'Dose recomendada (ex.: 2 L/ha)', border: OutlineInputBorder(), helperText: 'Aparece pronta no check-in')),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: salvando
                      ? null
                      : () async {
                          if (nome.text.trim().isEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Informe o nome do produto.')));
                            return;
                          }
                          setSheet(() => salvando = true);
                          final dados = {
                            'nome': nome.text.trim(),
                            'principio_ativo': principio.text.trim(),
                            'categoria': categoria,
                            'unidade': unidade,
                            'carencia': int.tryParse(carencia.text.trim()),
                            'dose_recomendada': doseRec.text.trim(),
                          };
                          try {
                            if (existente == null) {
                              dados['criado_por'] = supabase.auth.currentUser!.id;
                              final r = await supabase.from('produtos').insert(dados).select('id');
                              if (r.isEmpty) throw 'Sem permissão (apenas gestor/técnico).';
                            } else {
                              final r = await supabase.from('produtos').update(dados).eq('id', existente['id']).select('id');
                              if (r.isEmpty) throw 'Sem permissão (apenas gestor/técnico).';
                            }
                            if (ctx.mounted) Navigator.pop(ctx);
                            _carregar();
                          } catch (e) {
                            setSheet(() => salvando = false);
                            if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Não foi possível salvar: $e')));
                          }
                        },
                  icon: salvando ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_outlined),
                  label: Text(salvando ? 'Salvando...' : 'Salvar produto'),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.teal700, padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _apagar(Map<String, dynamic> p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar produto'),
        content: Text('Apagar "${p['nome']}" do catálogo?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC23A2B)), child: const Text('Apagar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await supabase.from('produtos').delete().eq('id', p['id']);
      _carregar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível apagar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _lista.where((p) => (p['nome'] as String).toLowerCase().contains(_busca.toLowerCase())).toList();
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.teal700, foregroundColor: Colors.white, title: const Text('Produtos')),
      floatingActionButton: _podeEditar
          ? FloatingActionButton.extended(backgroundColor: AppColors.coral, foregroundColor: Colors.white, onPressed: () => _editar(), icon: const Icon(Icons.add), label: const Text('Novo'))
          : null,
      body: _carregando
          ? const Center(child: CircularProgressIndicator(color: AppColors.teal500))
          : _erro != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Erro: $_erro', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFC23A2B)))))
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      onChanged: (v) => setState(() => _busca = v),
                      decoration: InputDecoration(hintText: 'Buscar produto...', prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                    ),
                  ),
                  Expanded(
                    child: filtrados.isEmpty
                        ? const Center(child: Text('Nenhum produto cadastrado.\nToque em "Novo" para começar.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)))
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            itemCount: filtrados.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (_, i) {
                              final p = filtrados[i];
                              return Container(
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.fieldBorder)),
                                child: ListTile(
                                  onTap: _podeEditar ? () => _editar(p) : null,
                                  leading: CircleAvatar(backgroundColor: AppColors.teal500.withOpacity(.12), child: const Icon(Icons.inventory_2_outlined, color: AppColors.teal700)),
                                  title: Text(p['nome'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                                  subtitle: Text([
                                    if ((p['principio_ativo'] as String?)?.isNotEmpty == true) p['principio_ativo'],
                                    if ((p['categoria'] as String?)?.isNotEmpty == true) p['categoria'],
                                    if ((p['dose_recomendada'] as String?)?.isNotEmpty == true) 'Dose rec.: ${p['dose_recomendada']}' else 'Dose em ${p['unidade'] ?? '-'}',
                                    if (p['carencia'] != null) 'carência ${p['carencia']}d',
                                  ].join(' • ')),
                                  trailing: _podeEditar
                                      ? IconButton(icon: const Icon(Icons.delete_outline, color: AppColors.muted), onPressed: () => _apagar(p))
                                      : null,
                                ),
                              );
                            },
                          ),
                  ),
                ]),
    );
  }
}