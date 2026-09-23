// ============================================================================
//  RotaCampo — Relatórios / Dashboard
//  Gestor: painel da equipe (Técnicos e Vendedores separados).
//  Vendedor/Técnico: resumo pessoal (parcial).
//  Salve como: lib/relatorios_screen.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'main.dart'; // supabase, AppColors, UserRole

class RelatoriosScreen extends StatefulWidget {
  final UserRole role;
  const RelatoriosScreen({super.key, required this.role});

  @override
  State<RelatoriosScreen> createState() => _RelatoriosScreenState();
}

class _RelatoriosScreenState extends State<RelatoriosScreen> {
  bool _carregando = true;
  String? _erro;

  // Totais
  int _totClientes = 0, _totVisitas = 0, _totPresc = 0;
  // Por pessoa
  List<Map<String, dynamic>> _tecnicos = [];
  List<Map<String, dynamic>> _vendedores = [];
  // Resumo pessoal
  final Map<String, int> _meu = {};

  @override
  void initState() {
    super.initState();
    widget.role == UserRole.gestor ? _carregarGestor() : _carregarPessoal();
  }

  // -------- Dashboard do gestor --------
  Future<void> _carregarGestor() async {
    try {
      final usuarios = List<Map<String, dynamic>>.from(await supabase.from('usuarios').select('id, nome, perfil'));
      final clientes = List<Map<String, dynamic>>.from(await supabase.from('clientes').select('id, vendedor_id'));
      final checkins = List<Map<String, dynamic>>.from(await supabase.from('checkins').select('usuario_id, cliente_id'));
      final prescricoes = List<Map<String, dynamic>>.from(await supabase.from('prescricoes').select('tecnico_id'));

      // mapa cliente -> vendedor
      final clienteVendedor = {for (final c in clientes) c['id']: c['vendedor_id']};

      // contagens
      int contaOnde(List l, String campo, dynamic valor) => l.where((x) => x[campo] == valor).length;

      final tecnicos = usuarios.where((u) => u['perfil'] == 'tecnico').map((u) {
        return {
          'nome': u['nome'],
          'visitas': contaOnde(checkins, 'usuario_id', u['id']),
          'prescricoes': contaOnde(prescricoes, 'tecnico_id', u['id']),
        };
      }).toList();

      final vendedores = usuarios.where((u) => u['perfil'] == 'vendedor').map((u) {
        final carteira = contaOnde(clientes, 'vendedor_id', u['id']);
        final visitasCarteira = checkins.where((ck) => clienteVendedor[ck['cliente_id']] == u['id']).length;
        return {'nome': u['nome'], 'carteira': carteira, 'visitas': visitasCarteira};
      }).toList();

      setState(() {
        _totClientes = clientes.length;
        _totVisitas = checkins.length;
        _totPresc = prescricoes.length;
        _tecnicos = tecnicos;
        _vendedores = vendedores;
        _carregando = false;
      });
    } catch (e) {
      setState(() {
        _erro = '$e';
        _carregando = false;
      });
    }
  }

  // -------- Resumo pessoal (vendedor/técnico) --------
  Future<void> _carregarPessoal() async {
    final uid = supabase.auth.currentUser!.id;
    try {
      if (widget.role == UserRole.tecnico) {
        final visitas = await supabase.from('checkins').select('id').eq('usuario_id', uid);
        final presc = await supabase.from('prescricoes').select('id').eq('tecnico_id', uid);
        _meu['Visitas realizadas'] = (visitas as List).length;
        _meu['Prescrições feitas'] = (presc as List).length;
      } else {
        // vendedor
        final carteira = await supabase.from('clientes').select('id').eq('vendedor_id', uid);
        final ids = (carteira as List).map((c) => c['id']).toList();
        _meu['Clientes na carteira'] = ids.length;
        int visitas = 0;
        if (ids.isNotEmpty) {
          final ck = await supabase.from('checkins').select('id').inFilter('cliente_id', ids);
          visitas = (ck as List).length;
        }
        _meu['Visitas na carteira'] = visitas;
      }
      setState(() => _carregando = false);
    } catch (e) {
      setState(() {
        _erro = '$e';
        _carregando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.teal700, foregroundColor: Colors.white, title: const Text('Relatórios')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator(color: AppColors.teal500))
          : _erro != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Erro: $_erro', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFC23A2B)))))
              : widget.role == UserRole.gestor
                  ? _dashboardGestor()
                  : _resumoPessoal(),
    );
  }

  // ---------- UI: dashboard do gestor ----------
  Widget _dashboardGestor() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(spacing: 12, runSpacing: 12, children: [
          _cardTotal('Clientes', _totClientes, Icons.people_outline),
          _cardTotal('Visitas', _totVisitas, Icons.check_circle_outline),
          _cardTotal('Prescrições', _totPresc, Icons.description_outlined),
          _cardTotal('Equipe', _tecnicos.length + _vendedores.length, Icons.groups_outlined),
        ]),
        const SizedBox(height: 24),
        _titulo('Técnicos', Icons.engineering_outlined),
        const SizedBox(height: 8),
        if (_tecnicos.isEmpty) _semDados() else ..._tecnicos.map(_linhaTecnico),
        const SizedBox(height: 24),
        _titulo('Vendedores', Icons.badge_outlined),
        const SizedBox(height: 8),
        if (_vendedores.isEmpty) _semDados() else ..._vendedores.map(_linhaVendedor),
      ],
    );
  }

  Widget _cardTotal(String label, int valor, IconData icon) => Container(
        width: 158,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.fieldBorder)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: AppColors.teal700),
          const SizedBox(height: 10),
          Text('$valor', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.ink)),
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
        ]),
      );

  Widget _titulo(String t, IconData i) => Row(children: [
        Icon(i, color: AppColors.teal700, size: 20),
        const SizedBox(width: 8),
        Text(t, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink)),
      ]);

  Widget _linhaTecnico(Map<String, dynamic> t) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.fieldBorder)),
        child: Row(children: [
          Expanded(child: Text(t['nome'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink))),
          _pillNum('${t['visitas']} visitas', const Color(0xFF2E7D5B)),
          const SizedBox(width: 8),
          _pillNum('${t['prescricoes']} presc.', AppColors.teal700),
        ]),
      );

  Widget _linhaVendedor(Map<String, dynamic> v) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.fieldBorder)),
        child: Row(children: [
          Expanded(child: Text(v['nome'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink))),
          _pillNum('${v['carteira']} clientes', const Color(0xFFB8860B)),
          const SizedBox(width: 8),
          _pillNum('${v['visitas']} visitas', const Color(0xFF2E7D5B)),
        ]),
      );

  Widget _pillNum(String t, Color cor) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: cor.withOpacity(.12), borderRadius: BorderRadius.circular(999)),
        child: Text(t, style: TextStyle(color: cor, fontWeight: FontWeight.w600, fontSize: 12)),
      );

  Widget _semDados() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('Ninguém cadastrado ainda.', style: TextStyle(color: AppColors.muted)),
      );

  // ---------- UI: resumo pessoal ----------
  Widget _resumoPessoal() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Seu resumo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
        const SizedBox(height: 16),
        Wrap(spacing: 12, runSpacing: 12, children: _meu.entries.map((e) => _cardTotal(e.key, e.value, Icons.insights_outlined)).toList()),
      ],
    );
  }
}
