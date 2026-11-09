// ============================================================================
//  RotaCampo — Cadastro completo de cliente
//  Toque no mapa para definir a localização (lat/lng), escolha município,
//  e atribua o vendedor (por perfil). Salve como: lib/cadastro_cliente_screen.dart
// ============================================================================

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';
import 'main.dart'; // supabase, AppColors, UserRole
import 'offline.dart'; // fila offline e sincronização
import 'acoes.dart'; // buscarEnderecos (geocodificação)

const List<String> kCulturasComuns = [
  'Café', 'Banana', 'Tomate', 'Batata', 'Cenoura', 'Alho', 'Cebola',
  'Feijão', 'Milho', 'Mandioca', 'Laranja', 'Maracujá', 'Uva', 'Outra',
];

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
  final _areaHa = TextEditingController();

  // Culturas do cliente (cada uma: cultura, nº de plantas, área, talhão)
  final List<Map<String, dynamic>> _culturas = [];
  Map<String, dynamic> _novaCultura() => {
        'cultura': null,
        'plantas': TextEditingController(),
        'area': TextEditingController(),
        'talhao': TextEditingController(),
      };

  Uint8List? _foto; // foto da propriedade
  final _picker = ImagePicker();

  // Mapa: satélite + busca por ponto de referência
  bool _satelite = false;
  final _busca = TextEditingController();
  List<Map<String, dynamic>> _resultados = [];
  bool _buscando = false;
  // Importar localização enviada pelo cliente (link do Maps ou coordenadas)
  final _colar = TextEditingController();
  bool _importando = false;

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
    for (final c in [_nome, _telefone, _endereco, _obs, _lat, _lng, _areaHa, _busca, _colar]) {
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
        'area_ha': double.tryParse(_areaHa.text.trim().replaceAll(',', '.')),
      };
      // Atribuição de vendedor conforme o perfil de quem cadastra
      if (widget.role == UserRole.vendedor && _addCarteira) {
        dados['vendedor_id'] = supabase.auth.currentUser!.id;
      } else if (widget.role == UserRole.gestor && _vendedorId != null) {
        dados['vendedor_id'] = _vendedorId;
      }

      // Lista de culturas preenchidas (sem o cliente_id ainda)
      final culturas = _culturas
          .where((c) => (c['cultura'] as String?)?.isNotEmpty == true)
          .map((c) => {
                'cultura': c['cultura'],
                'plantas': int.tryParse((c['plantas'] as TextEditingController).text.trim()),
                'area_ha': double.tryParse((c['area'] as TextEditingController).text.trim().replaceAll(',', '.')),
                'talhao': (c['talhao'] as TextEditingController).text.trim(),
              })
          .toList();

      if (await estaOnline()) {
        // 1) foto da propriedade (se tiver)
        if (_foto != null) {
          final uid = supabase.auth.currentUser!.id;
          final caminho = '$uid/prop_${DateTime.now().millisecondsSinceEpoch}.jpg';
          await supabase.storage.from('fotos').uploadBinary(caminho, _foto!);
          dados['foto_url'] = supabase.storage.from('fotos').getPublicUrl(caminho);
        }
        // 2) cliente (retorna o id) + culturas
        final novo = await supabase.from('clientes').insert(dados).select('id').single();
        if (culturas.isNotEmpty) {
          final rows = culturas.map((c) => {...c, 'cliente_id': novo['id']}).toList();
          await supabase.from('cliente_culturas').insert(rows);
        }
      } else {
        await enfileirar({
          'tipo': 'cliente',
          'dados': dados,
          'culturas': culturas,
          if (_foto != null) 'fotoB64': base64Encode(_foto!),
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sem internet — cliente salvo offline. Será enviado quando houver sinal.'), backgroundColor: Color(0xFFB8860B)),
          );
        }
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('nesta loja')) {
        _aviso('Este cliente já está cadastrado nesta loja. (Pode existir em outra loja.)');
      } else {
        _aviso('Não foi possível salvar: $e');
      }
      setState(() => _salvando = false);
    }
  }

  void _aviso(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _pegarFoto(ImageSource origem) async {
    final x = await _picker.pickImage(source: origem, imageQuality: 55, maxWidth: 1280);
    if (x != null) {
      final b = await x.readAsBytes();
      setState(() => _foto = b);
    }
  }

  // Busca um ponto de referência pelo nome e lista os resultados
  Future<void> _buscarReferencia() async {
    final q = _busca.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _buscando = true);
    final res = await buscarEnderecos(q);
    if (!mounted) return;
    setState(() {
      _resultados = res;
      _buscando = false;
    });
    if (res.isEmpty) _aviso('Nada encontrado. Tente incluir a cidade (ex.: "Bar do João, Piatã") ou toque no mapa.');
  }

  // Usa as coordenadas do resultado escolhido
  void _usarResultado(Map<String, dynamic> r) {
    final la = r['lat'] as double;
    final ln = r['lng'] as double;
    setState(() {
      _lat.text = la.toStringAsFixed(6);
      _lng.text = ln.toStringAsFixed(6);
      _resultados = [];
      _busca.clear();
    });
    try {
      _mapCtrl.move(LatLng(la, ln), 15);
    } catch (_) {}
  }

  // Importa a localização que o cliente enviou (link do Maps ou coordenadas)
  Future<void> _importarLocalizacao() async {
    final t = _colar.text.trim();
    if (t.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _importando = true);
    LatLng? achado = extrairCoordenadas(t);
    if (achado == null && t.contains('http')) {
      achado = await resolverLocalizacaoLink(t);
    }
    if (!mounted) return;
    setState(() => _importando = false);
    final p = achado;
    if (p == null) {
      _aviso('Não consegui ler a localização. Cole o link do Google Maps que o cliente enviou, ou as coordenadas (ex.: -13.402, -41.604).');
      return;
    }
    setState(() {
      _lat.text = p.latitude.toStringAsFixed(6);
      _lng.text = p.longitude.toStringAsFixed(6);
      _colar.clear();
    });
    try {
      _mapCtrl.move(p, 16);
    } catch (_) {}
    _aviso('Localização importada!');
  }

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
          _campo(_areaHa, 'Área total (ha)', Icons.straighten_outlined, teclado: const TextInputType.numberWithOptions(decimal: true)),

          const SizedBox(height: 6),
          Row(children: const [
            Icon(Icons.grass_outlined, color: AppColors.teal700, size: 20),
            SizedBox(width: 8),
            Expanded(child: Text('Culturas e talhões', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink))),
          ]),
          const Padding(padding: EdgeInsets.only(top: 2, bottom: 8), child: Text('O que planta, nº de plantas, área e talhão.', style: TextStyle(color: AppColors.muted, fontSize: 13))),
          if (_culturas.isEmpty)
            const Padding(padding: EdgeInsets.only(bottom: 6), child: Text('Nenhuma cultura adicionada.', style: TextStyle(color: AppColors.muted, fontSize: 12))),
          ...List.generate(_culturas.length, (i) {
            final c = _culturas[i];
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: c['cultura'] as String?,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Cultura', border: OutlineInputBorder(), isDense: true, filled: true, fillColor: Colors.white),
                      items: kCulturasComuns.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                      onChanged: (v) => setState(() => c['cultura'] = v),
                    ),
                  ),
                  IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(), icon: const Icon(Icons.remove_circle_outline, color: AppColors.muted), onPressed: () => setState(() => _culturas.removeAt(i))),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextField(controller: c['plantas'] as TextEditingController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Nº de plantas', border: OutlineInputBorder(), isDense: true, filled: true, fillColor: Colors.white))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: c['area'] as TextEditingController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Área (ha)', border: OutlineInputBorder(), isDense: true, filled: true, fillColor: Colors.white))),
                ]),
                const SizedBox(height: 8),
                TextField(controller: c['talhao'] as TextEditingController, decoration: const InputDecoration(labelText: 'Talhão (ex.: Talhão 1)', border: OutlineInputBorder(), isDense: true, filled: true, fillColor: Colors.white)),
              ]),
            );
          }),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _culturas.add(_novaCultura())),
              icon: const Icon(Icons.add, size: 18, color: AppColors.teal700),
              label: const Text('Adicionar cultura', style: TextStyle(color: AppColors.teal700, fontWeight: FontWeight.w600)),
            ),
          ),

          const SizedBox(height: 14),
          const Text('Foto da propriedade', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 8),
          if (_foto != null) ...[
            Stack(children: [
              ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(_foto!, height: 150, width: double.infinity, fit: BoxFit.cover)),
              Positioned(right: 6, top: 6, child: GestureDetector(onTap: () => setState(() => _foto = null), child: Container(decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle), padding: const EdgeInsets.all(2), child: const Icon(Icons.close, color: Colors.white, size: 20)))),
            ]),
            const SizedBox(height: 8),
          ],
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () => _pegarFoto(ImageSource.camera), icon: const Icon(Icons.photo_camera_outlined, size: 18), label: const Text('Câmera'), style: OutlinedButton.styleFrom(foregroundColor: AppColors.teal700, side: const BorderSide(color: AppColors.teal500)))),
            const SizedBox(width: 12),
            Expanded(child: OutlinedButton.icon(onPressed: () => _pegarFoto(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined, size: 18), label: const Text('Galeria'), style: OutlinedButton.styleFrom(foregroundColor: AppColors.teal700, side: const BorderSide(color: AppColors.teal500)))),
          ]),

          const SizedBox(height: 20),
          const Text('Localização', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 4),
          const Text('Busque por um ponto de referência (ex.: "Bar do João, Piatã") ou toque no mapa.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _busca,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _buscarReferencia(),
                decoration: InputDecoration(hintText: 'Buscar no mapa...', prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _buscando ? null : _buscarReferencia,
                style: FilledButton.styleFrom(backgroundColor: AppColors.teal700),
                child: _buscando ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.search),
              ),
            ),
          ]),
          if (_resultados.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 8),
              constraints: const BoxConstraints(maxHeight: 180),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.fieldBorder)),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _resultados.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = _resultados[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.place_outlined, color: AppColors.teal700),
                    title: Text(r['nome'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
                    onTap: () => _usarResultado(r),
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _colar,
                decoration: InputDecoration(hintText: 'Colar localização do cliente (link ou -13.4, -41.6)', prefixIcon: const Icon(Icons.my_location_outlined), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 48,
              child: OutlinedButton(
                onPressed: _importando ? null : _importarLocalizacao,
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.teal700, side: const BorderSide(color: AppColors.teal500)),
                child: _importando ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal700)) : const Text('Importar'),
              ),
            ),
          ]),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () async {
                final ok = await abrirBuscaMaps(_busca.text.trim());
                if (!ok && mounted) _aviso('Não consegui abrir o Google Maps.');
              },
              icon: const Icon(Icons.travel_explore, size: 18, color: AppColors.teal700),
              label: const Text('Procurar comércio no Google Maps', style: TextStyle(color: AppColors.teal700, fontWeight: FontWeight.w600)),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.fieldBorder)),
            child: const Text(
              'Dica: achou o comércio no Google Maps? Toque em Compartilhar → Copiar link, volte aqui e cole em "Colar localização" acima. O app importa as coordenadas.',
              style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.35),
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 260,
              child: Stack(children: [
                FlutterMap(
                  mapController: _mapCtrl,
                  options: MapOptions(
                    initialCenter: LatLng(-13.4, -41.5),
                    initialZoom: 8.5,
                    onTap: (_, p) => _definirPonto(p),
                  ),
                  children: [
                    _satelite
                        ? TileLayer(urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', userAgentPackageName: 'com.rotacampo.app')
                        : TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.rotacampo.app'),
                    if (_ponto != null)
                      MarkerLayer(markers: [
                        Marker(point: _ponto!, width: 44, height: 44, child: const Icon(Icons.location_on, color: AppColors.coral, size: 40)),
                      ]),
                    RichAttributionWidget(attributions: [
                      TextSourceAttribution(_satelite ? 'Esri, Maxar, Earthstar Geographics' : 'OpenStreetMap contributors'),
                    ]),
                  ],
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    elevation: 3,
                    child: IconButton(
                      tooltip: _satelite ? 'Ver mapa de ruas' : 'Ver satélite',
                      icon: Icon(_satelite ? Icons.map_outlined : Icons.satellite_alt_outlined, color: AppColors.teal700),
                      onPressed: () => setState(() => _satelite = !_satelite),
                    ),
                  ),
                ),
              ]),
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