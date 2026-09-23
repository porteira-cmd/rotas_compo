// ============================================================================
//  RotaCampo — Montar rota (escolher várias paradas e abrir no Google Maps)
//  Marque os clientes (na ordem que quiser), veja a contagem e abra tudo
//  no Google Maps de uma vez. Salve como: lib/rotas_screen.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'main.dart'; // supabase, AppColors, UserRole
import 'acoes.dart'; // abrirRotaNoMaps
import 'rota_execucao_screen.dart'; // executar rota no app
import 'avisar_clientes.dart'; // avisar clientes via WhatsApp

class RotasScreen extends StatefulWidget {
  final UserRole role;
  const RotasScreen({super.key, required this.role});

  @override
  State<RotasScreen> createState() => _RotasScreenState();
}

class _RotasScreenState extends State<RotasScreen> {
  List<Map<String, dynamic>> _clientes = [];
  final List<Map<String, dynamic>> _rota = []; // paradas escolhidas, em ordem
  bool _carregando = true;
  String? _erro;
  String _busca = '';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final data = await supabase
          .from('clientes')
          .select('id, nome, telefone, municipio, latitude, longitude')
          .not('latitude', 'is', null)
          .not('longitude', 'is', null)
          .order('nome');
      setState(() {
        _clientes = List<Map<String, dynamic>>.from(data);
        _carregando = false;
      });
    } catch (e) {
      setState(() {
        _erro = '$e';
        _carregando = false;
      });
    }
  }

  int _posicao(Map c) => _rota.indexWhere((r) => r['id'] == c['id']);
  bool _selecionado(Map c) => _posicao(c) >= 0;

  void _alternar(Map<String, dynamic> c) {
    setState(() {
      _selecionado(c) ? _rota.removeWhere((r) => r['id'] == c['id']) : _rota.add(c);
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _clientes.where((c) => (c['nome'] as String).toLowerCase().contains(_busca.toLowerCase())).toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.teal700,
        foregroundColor: Colors.white,
        title: const Text('Montar rota'),
        actions: [
          if (_rota.isNotEmpty)
            IconButton(icon: const Icon(Icons.clear_all), tooltip: 'Limpar', onPressed: () => setState(_rota.clear)),
        ],
      ),
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
                          hintText: 'Buscar cliente...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtrados.length,
                        itemBuilder: (_, i) {
                          final c = filtrados[i];
                          final pos = _posicao(c);
                          final sel = pos >= 0;
                          return ListTile(
                            onTap: () => _alternar(c),
                            leading: sel
                                ? CircleAvatar(
                                    backgroundColor: AppColors.teal700,
                                    radius: 16,
                                    child: Text('${pos + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                                  )
                                : const CircleAvatar(backgroundColor: AppColors.field, radius: 16, child: Icon(Icons.add, color: AppColors.muted, size: 18)),
                            title: Text(c['nome'] ?? '', style: TextStyle(fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
                            subtitle: Text(c['municipio'] ?? ''),
                            trailing: sel ? const Icon(Icons.check_circle, color: AppColors.teal500) : null,
                          );
                        },
                      ),
                    ),
                  ],
                ),
      bottomNavigationBar: _rota.isEmpty ? null : _barraInferior(),
    );
  }

  Widget _barraInferior() {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(.12), blurRadius: 10)]),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            const Icon(Icons.route, color: AppColors.teal700),
            const SizedBox(width: 8),
            Text('${_rota.length} paradas selecionadas', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => abrirRotaNoMaps(_rota.map((c) => [(c['latitude'] as num).toDouble(), (c['longitude'] as num).toDouble()]).toList()),
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('Google Maps'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.coral, padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RotaExecucaoScreen(paradas: List.from(_rota)))),
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Iniciar'),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.teal700, side: const BorderSide(color: AppColors.teal500), padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => mostrarAvisarClientes(context, _rota),
              icon: const Icon(Icons.chat, size: 18),
              label: const Text('Avisar clientes no WhatsApp'),
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF128C7E), side: const BorderSide(color: Color(0xFF128C7E)), padding: const EdgeInsets.symmetric(vertical: 12)),
            ),
          ),
        ],
      ),
    );
  }
}
