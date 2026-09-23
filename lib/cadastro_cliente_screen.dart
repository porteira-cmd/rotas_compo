// ============================================================================
//  RotaCampo — Cadastro completo de cliente
//  Toque no mapa para definir a localização (lat/lng), escolha município,
//  e atribua o vendedor (por perfil). Salve como: lib/cadastro_cliente_screen.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'main.dart'; // supabase, AppColors, UserRole
import 'offline.dart'; // fila offline e sincronização

const List<String> kMunicipios = [
  'Abaíra', 'Barra da Estiva', 'Boninal', 'Bonito', 'Contendas do Sincorá',
  'Ibicoara', 'Iramaia', 'Ituaçu', 'Jussiape', 'Mucugê', 'Piatã',
];

class CadastroClienteScreen extends StatefulWidget {
  final UserRole role;
  const CadastroClienteScreen({super.key, required this.role});

  @override
  State<CadastroClienteScreen> createState() => _CadastroClienteScreenState();
}

class _CadastroClienteScreenState extends State<CadastroClienteScreen> {
  final _nome = TextEditingController();
  final _telefone = TextEditingController();
  final _endereco = TextEditingController();
  final _obs = TextEditingController();
  final _lat = TextEditingController();
  final _lng = TextEditingController();

  String? _municipio;
  bool _addCarteira = true; // vendedor: adicionar à própria carteira
  String? _vendedorId; // gestor: vendedor escolhido
  List<Map<String, dynamic>> _vendedores = [];
  bool _salvando = false;

  final _mapCtrl = MapController();

  @override
  void initState() {
    super.initState();
    if (widget.role == UserRole.gestor) _carregarVendedores();
    _sincronizarPendentes();
  }

  Future<void> _sincronizarPendentes() async {
    final n = await sincronizar();
    if (n > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$n registro(s) offline enviado(s).'), backgroundColor: AppColors.teal700),
      );
    }
  }

  Future<void> _carregarVendedores() async {
    try {
      final data = await supabase.from('usuarios').select('id, nome').eq('perfil', 'vendedor').order('nome');
      setState(() => _vendedores = List<Map<String, dynamic>>.from(data));
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final c in [_nome, _telefone, _endereco, _obs, _lat, _lng]) {
      c.dispose();
    }
    super.dispose();
  }

  LatLng? get _ponto {
    final la = double.tryParse(_lat.text);
    final ln = double.tryParse(_lng.text);
    return (la != null && ln != null) ? LatLng(la, ln) : null;
  }

  void _definirPonto(LatLng p) {
    setState(() {
      _lat.text = p.latitude.toStringAsFixed(6);
      _lng.text = p.longitude.toStringAsFixed(6);
    });
  }

  Future<void> _salvar() async {
    if (_nome.text.trim().isEmpty) {
      _aviso('Informe o nome do cliente.');
      return;
    }
    if (_ponto == null) {
      _aviso('Toque no mapa para marcar a localização.');
      return;
    }
    setState(() => _salvando = true);
    try {
      final dados = <String, dynamic>{
        'nome': _nome.text.trim(),
        'telefone': _telefone.text.trim(),
        'municipio': _municipio,
        'endereco': _endereco.text.trim(),
        'observacoes': _obs.text.trim(),
        'latitude': double.parse(_lat.text),
        'longitude': double.parse(_lng.text),
      };
      // Atribuição de vendedor conforme o perfil de quem cadastra
      if (widget.role == UserRole.vendedor && _addCarteira) {
        dados['vendedor_id'] = supabase.auth.currentUser!.id;
      } else if (widget.role == UserRole.gestor && _vendedorId != null) {
        dados['vendedor_id'] = _vendedorId;
      }

      if (await estaOnline()) {
        await supabase.from('clientes').insert(dados);
      } else {
        await enfileirar({'tipo': 'cliente', 'dados': dados});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sem internet — cliente salvo offline. Será enviado quando houver sinal.'), backgroundColor: Color(0xFFB8860B)),
          );
        }
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _aviso('Não foi possível salvar: $e');
      setState(() => _salvando = false);
    }
  }

  void _aviso(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.teal700,
        foregroundColor: Colors.white,
        title: const Text('Novo cliente'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _campo(_nome, 'Nome *', Icons.person_outline),
          _campo(_telefone, 'Telefone', Icons.phone_outlined, teclado: TextInputType.phone),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: _municipio,
            decoration: _deco('Município', Icons.location_city_outlined),
            items: kMunicipios.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
            onChanged: (v) => setState(() => _municipio = v),
          ),
          const SizedBox(height: 14),
          _campo(_endereco, 'Endereço', Icons.place_outlined),
          _campo(_obs, 'Observações', Icons.notes_outlined, linhas: 2),

          const SizedBox(height: 20),
          const Text('Localização', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 4),
          const Text('Toque no mapa onde fica o cliente.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 260,
              child: FlutterMap(
                mapController: _mapCtrl,
                options: MapOptions(
                  initialCenter: LatLng(-13.4, -41.5),
                  initialZoom: 8.5,
                  onTap: (_, p) => _definirPonto(p),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.rotacampo.app',
                  ),
                  if (_ponto != null)
                    MarkerLayer(markers: [
                      Marker(point: _ponto!, width: 44, height: 44, child: const Icon(Icons.location_on, color: AppColors.coral, size: 40)),
                    ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _campo(_lat, 'Latitude', Icons.my_location, teclado: const TextInputType.numberWithOptions(decimal: true, signed: true), aoMudar: () => setState(() {}))),
            const SizedBox(width: 12),
            Expanded(child: _campo(_lng, 'Longitude', Icons.my_location, teclado: const TextInputType.numberWithOptions(decimal: true, signed: true), aoMudar: () => setState(() {}))),
          ]),

          const SizedBox(height: 8),
          _atribuicaoVendedor(),

          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _salvando ? null : _salvar,
              icon: _salvando
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_outlined),
              label: const Text('Salvar cliente'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.coral),
            ),
          ),
        ],
      ),
    );
  }

  // Atribuição de vendedor muda conforme o perfil
  Widget _atribuicaoVendedor() {
    if (widget.role == UserRole.vendedor) {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        activeColor: AppColors.teal500,
        title: const Text('Adicionar à minha carteira'),
        value: _addCarteira,
        onChanged: (v) => setState(() => _addCarteira = v),
      );
    }
    if (widget.role == UserRole.gestor) {
      return DropdownButtonFormField<String>(
        value: _vendedorId,
        decoration: _deco('Vendedor responsável (opcional)', Icons.badge_outlined),
        items: [
          const DropdownMenuItem(value: null, child: Text('Sem vendedor')),
          ..._vendedores.map((v) => DropdownMenuItem(value: v['id'] as String, child: Text(v['nome'] ?? ''))),
        ],
        onChanged: (v) => setState(() => _vendedorId = v),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _campo(TextEditingController c, String label, IconData icon,
      {TextInputType? teclado, int linhas = 1, VoidCallback? aoMudar}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: c,
        keyboardType: teclado,
        maxLines: linhas,
        onChanged: aoMudar == null ? null : (_) => aoMudar(),
        decoration: _deco(label, icon),
      ),
    );
  }

  InputDecoration _deco(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.muted, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );
}