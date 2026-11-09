// ============================================================================
//  RotaCampo — Catálogo de pragas / doenças / culturas
//  Fichas com foto de referência para ajudar a identificar no campo.
//  Todos veem; gestor e técnico cadastram/editam/apagam.
//  Precisa da tabela 'catalogo_pragas' (rode perfil_agenda_catalogo.sql).
//  Salve como: lib/catalogo_pragas_screen.dart
// ============================================================================

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'main.dart'; // supabase, AppColors, UserRole

const List<String> kTiposFicha = ['Praga', 'Doença', 'Planta daninha', 'Cultura'];

class CatalogoPragasScreen extends StatefulWidget {
  final UserRole role;
  const CatalogoPragasScreen({super.key, required this.role});

  @override
  State<CatalogoPragasScreen> createState() => _CatalogoPragasScreenState();
}

class _CatalogoPragasScreenState extends State<CatalogoPragasScreen> {
  List<Map<String, dynamic>> _lista = [];
  List<Map<String, dynamic>> _campo = []; // problemas/fotos registrados no campo
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
      final data = await supabase.from('catalogo_pragas').select('id, nome, tipo, culturas, descricao, sintomas, foto_url').order('nome');
      // Ocorrências do campo: problemas e fotos registrados nas visitas (prescrições)
      List<Map<String, dynamic>> campo = [];
      try {
        final pres = await supabase
            .from('prescricoes')
            .select('descricao, cultura, alvo, fotos, criado_em, clientes(nome, municipio)')
            .order('criado_em', ascending: false)
            .limit(300);
        campo = List<Map<String, dynamic>>.from(pres).where((p) {
          final temProblema = (p['descricao'] ?? '').toString().trim().isNotEmpty || (p['alvo'] ?? '').toString().trim().isNotEmpty;
          final temFoto = (p['fotos'] as List?)?.isNotEmpty == true;
          return temProblema || temFoto;
        }).toList();
      } catch (_) {}
      setState(() {
        _lista = List<Map<String, dynamic>>.from(data);
        _campo = campo;
        _carregando = false;
      });
    } catch (e) {
      setState(() {
        _erro = '$e';
        _carregando = false;
      });
    }
  }

  Color _corTipo(String? t) => switch (t) {
        'Praga' => const Color(0xFFC0392B),
        'Doença' => const Color(0xFFB8860B),
        'Planta daninha' => const Color(0xFF6D4C41),
        _ => AppColors.teal700,
      };

  // ---- ver ficha ----
  void _verFicha(Map<String, dynamic> p) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if ((p['foto_url'] as String?)?.isNotEmpty == true)
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(p['foto_url'], height: 200, width: double.infinity, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(height: 200, color: AppColors.field, child: const Icon(Icons.broken_image, color: AppColors.muted))),
              ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: Text(p['nome'] ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink))),
              if ((p['tipo'] as String?)?.isNotEmpty == true) _pill(p['tipo'], _corTipo(p['tipo'])),
            ]),
            if ((p['culturas'] as String?)?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              _linhaInfo(Icons.grass_outlined, 'Culturas', p['culturas']),
            ],
            if ((p['sintomas'] as String?)?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              _linhaInfo(Icons.visibility_outlined, 'Sintomas / como identificar', p['sintomas']),
            ],
            if ((p['descricao'] as String?)?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              _linhaInfo(Icons.notes_outlined, 'Descrição', p['descricao']),
            ],
            if (_podeEditar) ...[
              const SizedBox(height: 18),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _editar(p);
                    },
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Editar'),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.teal700, side: const BorderSide(color: AppColors.teal500)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _apagar(p);
                    },
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Apagar'),
                    style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFC23A2B), side: const BorderSide(color: Color(0xFFC23A2B))),
                  ),
                ),
              ]),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _linhaInfo(IconData i, String titulo, String texto) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(i, size: 16, color: AppColors.teal700), const SizedBox(width: 6), Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 13))]),
        const SizedBox(height: 2),
        Padding(padding: const EdgeInsets.only(left: 22), child: Text(texto, style: const TextStyle(color: AppColors.ink, height: 1.35))),
      ]);

  Widget _pill(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: c.withOpacity(.12), borderRadius: BorderRadius.circular(999)),
        child: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 11)),
      );

  // ---- cadastrar / editar ----
  Future<void> _editar([Map<String, dynamic>? existente]) async {
    final nome = TextEditingController(text: existente?['nome'] ?? '');
    final culturas = TextEditingController(text: existente?['culturas'] ?? '');
    final sintomas = TextEditingController(text: existente?['sintomas'] ?? '');
    final descricao = TextEditingController(text: existente?['descricao'] ?? '');
    String tipo = existente?['tipo'] ?? kTiposFicha.first;
    String? fotoUrl = existente?['foto_url'];
    Uint8List? novaFoto;
    final picker = ImagePicker();
    bool salvando = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> pegar(ImageSource origem) async {
            final x = await picker.pickImage(source: origem, imageQuality: 60, maxWidth: 1280);
            if (x != null) {
              final b = await x.readAsBytes();
              setSheet(() => novaFoto = b);
            }
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(existente == null ? 'Nova ficha' : 'Editar ficha', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
                const SizedBox(height: 16),
                TextField(controller: nome, decoration: const InputDecoration(labelText: 'Nome *', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: tipo,
                  decoration: const InputDecoration(labelText: 'Tipo', border: OutlineInputBorder()),
                  items: kTiposFicha.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) => setSheet(() => tipo = v!),
                ),
                const SizedBox(height: 12),
                TextField(controller: culturas, decoration: const InputDecoration(labelText: 'Culturas afetadas (ex.: café, tomate)', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: sintomas, maxLines: 2, decoration: const InputDecoration(labelText: 'Sintomas / como identificar', border: OutlineInputBorder(), alignLabelWithHint: true)),
                const SizedBox(height: 12),
                TextField(controller: descricao, maxLines: 3, decoration: const InputDecoration(labelText: 'Descrição / manejo', border: OutlineInputBorder(), alignLabelWithHint: true)),
                const SizedBox(height: 14),
                const Text('Foto de referência', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                const SizedBox(height: 8),
                if (novaFoto != null)
                  ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(novaFoto!, height: 140, width: double.infinity, fit: BoxFit.cover))
                else if ((fotoUrl ?? '').isNotEmpty)
                  ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(fotoUrl!, height: 140, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox())),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: OutlinedButton.icon(onPressed: () => pegar(ImageSource.camera), icon: const Icon(Icons.photo_camera_outlined, size: 18), label: const Text('Câmera'), style: OutlinedButton.styleFrom(foregroundColor: AppColors.teal700, side: const BorderSide(color: AppColors.teal500)))),
                  const SizedBox(width: 12),
                  Expanded(child: OutlinedButton.icon(onPressed: () => pegar(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined, size: 18), label: const Text('Galeria'), style: OutlinedButton.styleFrom(foregroundColor: AppColors.teal700, side: const BorderSide(color: AppColors.teal500)))),
                ]),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: salvando
                        ? null
                        : () async {
                            if (nome.text.trim().isEmpty) {
                              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Informe o nome.')));
                              return;
                            }
                            setSheet(() => salvando = true);
                            try {
                              final uid = supabase.auth.currentUser!.id;
                              if (novaFoto != null) {
                                final caminho = '$uid/praga_${DateTime.now().millisecondsSinceEpoch}.jpg';
                                await supabase.storage.from('fotos').uploadBinary(caminho, novaFoto!);
                                fotoUrl = supabase.storage.from('fotos').getPublicUrl(caminho);
                              }
                              final dados = {
                                'nome': nome.text.trim(),
                                'tipo': tipo,
                                'culturas': culturas.text.trim(),
                                'sintomas': sintomas.text.trim(),
                                'descricao': descricao.text.trim(),
                                'foto_url': fotoUrl,
                              };
                              if (existente == null) {
                                dados['criado_por'] = uid;
                                final r = await supabase.from('catalogo_pragas').insert(dados).select('id');
                                if (r.isEmpty) throw 'Sem permissão (apenas gestor/técnico).';
                              } else {
                                final r = await supabase.from('catalogo_pragas').update(dados).eq('id', existente['id']).select('id');
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
                    label: Text(salvando ? 'Salvando...' : 'Salvar ficha'),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.teal700, padding: const EdgeInsets.symmetric(vertical: 14)),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _apagar(Map<String, dynamic> p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar ficha'),
        content: Text('Apagar "${p['nome']}" do catálogo?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC23A2B)), child: const Text('Apagar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await supabase.from('catalogo_pragas').delete().eq('id', p['id']);
      _carregar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível apagar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.teal700,
          foregroundColor: Colors.white,
          title: const Text('Catálogo de pragas'),
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [Tab(text: 'Fichas'), Tab(text: 'No campo')],
          ),
        ),
        floatingActionButton: _podeEditar
            ? FloatingActionButton.extended(backgroundColor: AppColors.coral, foregroundColor: Colors.white, onPressed: () => _editar(), icon: const Icon(Icons.add), label: const Text('Nova ficha'))
            : null,
        body: _carregando
            ? const Center(child: CircularProgressIndicator(color: AppColors.teal500))
            : _erro != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Erro: $_erro', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFC23A2B)))))
                : TabBarView(children: [_abaFichas(), _abaCampo()]),
      ),
    );
  }

  // ---- Aba 1: fichas cadastradas ----
  Widget _abaFichas() {
    final q = _busca.toLowerCase();
    final filtrados = _lista.where((p) {
      return (p['nome'] ?? '').toString().toLowerCase().contains(q) || (p['culturas'] ?? '').toString().toLowerCase().contains(q);
    }).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          onChanged: (v) => setState(() => _busca = v),
          decoration: InputDecoration(hintText: 'Buscar praga, doença ou cultura...', prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
        ),
      ),
      Expanded(
        child: filtrados.isEmpty
            ? const Center(child: Text('Nenhuma ficha ainda.', style: TextStyle(color: AppColors.muted)))
            : GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: .82),
                itemCount: filtrados.length,
                itemBuilder: (_, i) {
                  final p = filtrados[i];
                  final foto = (p['foto_url'] as String?) ?? '';
                  return InkWell(
                    onTap: () => _verFicha(p),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.fieldBorder)),
                      clipBehavior: Clip.antiAlias,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: foto.isNotEmpty
                              ? Image.network(foto, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _semFoto())
                              : _semFoto(),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(p['nome'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                            const SizedBox(height: 4),
                            if ((p['tipo'] as String?)?.isNotEmpty == true) _pill(p['tipo'], _corTipo(p['tipo'])),
                          ]),
                        ),
                      ]),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  // ---- Aba 2: problemas e fotos registrados no campo ----
  Widget _abaCampo() {
    final q = _busca.toLowerCase();
    final itens = _campo.where((p) {
      final cli = ((p['clientes'] as Map<String, dynamic>?)?['nome'] ?? '').toString().toLowerCase();
      return (p['alvo'] ?? '').toString().toLowerCase().contains(q) ||
          (p['descricao'] ?? '').toString().toLowerCase().contains(q) ||
          (p['cultura'] ?? '').toString().toLowerCase().contains(q) ||
          cli.contains(q);
    }).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          onChanged: (v) => setState(() => _busca = v),
          decoration: InputDecoration(hintText: 'Buscar problema, cultura ou cliente...', prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
        ),
      ),
      Expanded(
        child: itens.isEmpty
            ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Ainda não há problemas registrados no campo.\nEles aparecem aqui conforme os técnicos fazem check-in.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted))))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                itemCount: itens.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final p = itens[i];
                  final cli = p['clientes'] as Map<String, dynamic>?;
                  final fotos = (p['fotos'] as List?) ?? [];
                  return Container(
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.fieldBorder)),
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const Icon(Icons.bug_report_outlined, color: AppColors.coral, size: 18),
                        const SizedBox(width: 6),
                        Expanded(child: Text((p['alvo'] ?? '').toString().isNotEmpty ? p['alvo'] : 'Problema registrado', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink))),
                        Text(_dataCurta(p['criado_em'] as String?), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                      ]),
                      const SizedBox(height: 4),
                      Wrap(spacing: 6, runSpacing: 4, children: [
                        if (cli?['nome'] != null) _pill(cli!['nome'], AppColors.teal700),
                        if ((p['cultura'] ?? '').toString().isNotEmpty) _pill('Cultura: ${p['cultura']}', const Color(0xFF2E7D5B)),
                      ]),
                      if ((p['descricao'] ?? '').toString().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(p['descricao'], style: const TextStyle(color: AppColors.ink, height: 1.35)),
                      ],
                      if (fotos.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 80,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: fotos.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                            itemBuilder: (_, k) {
                              final url = fotos[k] as String;
                              return GestureDetector(
                                onTap: () => _abrirGaleria(List<String>.from(fotos.whereType<String>()), k),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(url, width: 80, height: 80, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 80, height: 80, color: AppColors.field, child: const Icon(Icons.broken_image, color: AppColors.muted))),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ]),
                  );
                },
              ),
      ),
    ]);
  }

  String _dataCurta(String? iso) {
    final d = DateTime.tryParse('$iso')?.toLocal();
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  // Galeria de fotos em tela cheia, deslizando
  void _abrirGaleria(List<String> urls, int inicial) {
    if (urls.isEmpty) return;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(8),
        child: Stack(children: [
          PageView.builder(
            controller: PageController(initialPage: inicial),
            itemCount: urls.length,
            itemBuilder: (_, i) => InteractiveViewer(child: Center(child: Image.network(urls[i], fit: BoxFit.contain))),
          ),
          Positioned(
            right: 8,
            top: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _semFoto() => Container(
        color: AppColors.field,
        alignment: Alignment.center,
        child: const Icon(Icons.pest_control_outlined, color: AppColors.muted, size: 40),
      );
}