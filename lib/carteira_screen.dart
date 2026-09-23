// ============================================================================
//  RotaCampo — Carteira do Vendedor
//  Lista os clientes do vendedor (vendedor_id = ele) e permite adicionar.
//  Salve como: lib/carteira_screen.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'main.dart'; // supabase, AppColors, UserRole
import 'acoes.dart'; // WhatsApp e navegação

class CarteiraScreen extends StatefulWidget {
  final UserRole role;
  const CarteiraScreen({super.key, required this.role});

  @override
  State<CarteiraScreen> createState() => _CarteiraScreenState();
}

class _CarteiraScreenState extends State<CarteiraScreen> {
  final String _uid = supabase.auth.currentUser!.id;
  List<Map<String, dynamic>> _carteira = [];
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
          .from('clientes')
          .select('id, nome, telefone, municipio, endereco, latitude, longitude')
          .eq('vendedor_id', _uid)
          .order('nome');
      setState(() {
        _carteira = List<Map<String, dynamic>>.from(data);
        _carregando = false;
      });
    } catch (e) {
      setState(() {
        _erro = '$e';
        _carregando = false;
      });
    }
  }

  Future<void> _abrirAdicionar() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _AdicionarClientesScreen(uid: _uid)),
    );
    _carregar(); // recarrega ao voltar
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.teal700,
        foregroundColor: Colors.white,
        title: const Text('Minha carteira'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.coral,
        foregroundColor: Colors.white,
        onPressed: _abrirAdicionar,
        icon: const Icon(Icons.add),
        label: const Text('Adicionar'),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator(color: AppColors.teal500))
          : _erro != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Erro: $_erro', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFC23A2B)))))
              : _carteira.isEmpty
                  ? _vazio()
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _carteira.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _card(_carteira[i]),
                    ),
    );
  }

  Widget _vazio() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.folder_shared_outlined, size: 56, color: AppColors.muted),
            const SizedBox(height: 12),
            const Text('Sua carteira está vazia',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: 6),
            const Text('Toque em "Adicionar" para incluir clientes na sua carteira.',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
          ]),
        ),
      );

  Widget _card(Map<String, dynamic> c) => Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.fieldBorder)),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: AppColors.teal500.withOpacity(.12),
            child: Text((c['nome'] as String).isNotEmpty ? (c['nome'] as String)[0].toUpperCase() : '?',
                style: const TextStyle(color: AppColors.teal700, fontWeight: FontWeight.w700)),
          ),
          title: Text(c['nome'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text((c['municipio'] as String?)?.isNotEmpty == true ? c['municipio'] : 'Sem município'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              icon: const Icon(Icons.chat, color: Color(0xFF128C7E)),
              tooltip: 'WhatsApp',
              onPressed: () async {
                final ok = await abrirWhatsApp(c['telefone'], mensagemVisita(c['nome'] ?? 'cliente'));
                if (!ok && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cliente sem telefone.')));
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.navigation_outlined, color: AppColors.teal700),
              tooltip: 'Navegar',
              onPressed: () => abrirNavegacao((c['latitude'] as num).toDouble(), (c['longitude'] as num).toDouble()),
            ),
          ]),
        ),
      );
}

// ============================================================================
//  Tela pra adicionar clientes (sem dono) à carteira
// ============================================================================
class _AdicionarClientesScreen extends StatefulWidget {
  final String uid;
  const _AdicionarClientesScreen({required this.uid});

  @override
  State<_AdicionarClientesScreen> createState() => _AdicionarClientesScreenState();
}

class _AdicionarClientesScreenState extends State<_AdicionarClientesScreen> {
  List<Map<String, dynamic>> _disponiveis = [];
  bool _carregando = true;
  String _busca = '';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      // Clientes ainda sem dono (vendedor_id nulo)
      final data = await supabase
          .from('clientes')
          .select('id, nome, municipio')
          .filter('vendedor_id', 'is', null)
          .order('nome');
      setState(() {
        _disponiveis = List<Map<String, dynamic>>.from(data);
        _carregando = false;
      });
    } catch (_) {
      setState(() => _carregando = false);
    }
  }

  Future<void> _adicionar(Map<String, dynamic> c) async {
    try {
      await supabase.from('clientes').update({'vendedor_id': widget.uid}).eq('id', c['id']);
      setState(() => _disponiveis.removeWhere((x) => x['id'] == c['id']));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${c['nome']} adicionado à sua carteira.'), backgroundColor: AppColors.teal700),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível adicionar: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _disponiveis
        .where((c) => (c['nome'] as String).toLowerCase().contains(_busca.toLowerCase()))
        .toList();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.teal700,
        foregroundColor: Colors.white,
        title: const Text('Adicionar à carteira'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              onChanged: (v) => setState(() => _busca = v),
              decoration: InputDecoration(
                hintText: 'Buscar cliente...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator(color: AppColors.teal500))
                : filtrados.isEmpty
                    ? const Center(child: Text('Nenhum cliente disponível.', style: TextStyle(color: AppColors.muted)))
                    : ListView.builder(
                        itemCount: filtrados.length,
                        itemBuilder: (_, i) {
                          final c = filtrados[i];
                          return ListTile(
                            title: Text(c['nome'] ?? ''),
                            subtitle: Text(c['municipio'] ?? ''),
                            trailing: IconButton(
                              icon: const Icon(Icons.add_circle, color: AppColors.coral),
                              onPressed: () => _adicionar(c),
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
