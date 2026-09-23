// ============================================================================
//  RotaCampo — Executar rota (problema + vários produtos/dosagens + fotos)
//  Pacotes: image_picker, connectivity_plus, shared_preferences
//  Salve como: lib/rota_execucao_screen.dart
// ============================================================================

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'main.dart'; // supabase, AppColors
import 'acoes.dart'; // navegação
import 'offline.dart'; // fila offline

class RotaExecucaoScreen extends StatefulWidget {
  final List<Map<String, dynamic>> paradas;
  const RotaExecucaoScreen({super.key, required this.paradas});

  @override
  State<RotaExecucaoScreen> createState() => _RotaExecucaoScreenState();
}

class _RotaExecucaoScreenState extends State<RotaExecucaoScreen> {
  final Set<dynamic> _feitos = {};

  @override
  void initState() {
    super.initState();
    sincronizar();
  }

  int get _total => widget.paradas.length;
  int get _visitadas => _feitos.length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.teal700, foregroundColor: Colors.white, title: const Text('Executar rota')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: AppColors.teal700,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$_visitadas de $_total paradas visitadas', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(value: _total == 0 ? 0 : _visitadas / _total, minHeight: 8, backgroundColor: Colors.white24, valueColor: const AlwaysStoppedAnimation(AppColors.coral)),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: widget.paradas.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _cardParada(i, widget.paradas[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardParada(int i, Map<String, dynamic> c) {
    final feito = _feitos.contains(c['id']);
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: feito ? AppColors.teal500 : AppColors.fieldBorder)),
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(color: feito ? AppColors.teal500 : AppColors.teal500.withOpacity(.12), shape: BoxShape.circle),
          alignment: Alignment.center,
          child: feito ? const Icon(Icons.check, color: Colors.white, size: 18) : Text('${i + 1}', style: const TextStyle(color: AppColors.teal700, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c['nome'] ?? 'Cliente', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: AppColors.ink)),
            Text(feito ? 'Visita registrada' : (c['municipio'] ?? 'Pendente'), style: TextStyle(color: feito ? AppColors.teal700 : AppColors.muted, fontSize: 13)),
          ]),
        ),
        IconButton(
          tooltip: 'Navegar',
          icon: const Icon(Icons.navigation_outlined, color: AppColors.teal700),
          onPressed: () => abrirNavegacao((c['latitude'] as num).toDouble(), (c['longitude'] as num).toDouble()),
        ),
        if (!feito) FilledButton(onPressed: () => _registrarVisita(c), style: FilledButton.styleFrom(backgroundColor: AppColors.coral), child: const Text('Visita')),
      ]),
    );
  }

  Future<void> _registrarVisita(Map<String, dynamic> c) async {
    final problema = TextEditingController();
    // lista de recomendações (começa com uma vazia)
    final List<Map<String, TextEditingController>> recs = [
      {'produto': TextEditingController(), 'dosagem': TextEditingController()},
    ];
    final List<Uint8List> fotos = [];
    bool enviando = false;
    final picker = ImagePicker();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> pegarFoto(ImageSource origem) async {
            final x = await picker.pickImage(source: origem, imageQuality: 55, maxWidth: 1280);
            if (x != null) {
              final b = await x.readAsBytes();
              setSheet(() => fotos.add(b));
            }
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Visita: ${c['nome']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
                  const SizedBox(height: 16),
                  TextField(controller: problema, maxLines: 2, decoration: const InputDecoration(labelText: 'Problema encontrado', border: OutlineInputBorder(), alignLabelWithHint: true)),

                  const SizedBox(height: 18),
                  const Text('Recomendações (produto + dosagem)', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                  const SizedBox(height: 8),
                  // uma linha por produto
                  ...List.generate(recs.length, (i) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(children: [
                          Expanded(
                            flex: 3,
                            child: TextField(controller: recs[i]['produto'], decoration: const InputDecoration(labelText: 'Produto', border: OutlineInputBorder(), isDense: true)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextField(controller: recs[i]['dosagem'], decoration: const InputDecoration(labelText: 'Dosagem', border: OutlineInputBorder(), isDense: true)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: AppColors.muted),
                            onPressed: recs.length == 1 ? null : () => setSheet(() => recs.removeAt(i)),
                          ),
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

                  const SizedBox(height: 12),
                  const Text('Fotos do problema', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: OutlinedButton.icon(onPressed: () => pegarFoto(ImageSource.camera), icon: const Icon(Icons.photo_camera_outlined, size: 18), label: const Text('Câmera'), style: OutlinedButton.styleFrom(foregroundColor: AppColors.teal700, side: const BorderSide(color: AppColors.teal500)))),
                    const SizedBox(width: 12),
                    Expanded(child: OutlinedButton.icon(onPressed: () => pegarFoto(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined, size: 18), label: const Text('Galeria'), style: OutlinedButton.styleFrom(foregroundColor: AppColors.teal700, side: const BorderSide(color: AppColors.teal500)))),
                  ]),
                  if (fotos.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 84,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: fotos.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) => Stack(children: [
                          ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(fotos[i], width: 84, height: 84, fit: BoxFit.cover)),
                          Positioned(right: 2, top: 2, child: GestureDetector(onTap: () => setSheet(() => fotos.removeAt(i)), child: Container(decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle), child: const Icon(Icons.close, color: Colors.white, size: 18)))),
                        ]),
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: enviando
                          ? null
                          : () async {
                              setSheet(() => enviando = true);
                              final recsList = recs
                                  .map((r) => {'produto': r['produto']!.text.trim(), 'dosagem': r['dosagem']!.text.trim()})
                                  .where((r) => (r['produto'] as String).isNotEmpty)
                                  .toList();
                              final ok = await _salvar(c, problema.text.trim(), recsList, fotos);
                              if (ok && ctx.mounted) Navigator.pop(ctx);
                              if (!ok) setSheet(() => enviando = false);
                            },
                      icon: enviando ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check_circle_outline),
                      label: Text(enviando ? 'Enviando...' : 'Registrar check-in e visita'),
                      style: FilledButton.styleFrom(backgroundColor: AppColors.teal700, padding: const EdgeInsets.symmetric(vertical: 14)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<bool> _salvar(Map<String, dynamic> c, String problema, List<Map<String, dynamic>> recomendacoes, List<Uint8List> fotos) async {
    try {
      final uid = supabase.auth.currentUser!.id;
      final checkin = {'usuario_id': uid, 'cliente_id': c['id'], 'latitude': c['latitude'], 'longitude': c['longitude'], 'observacao': problema};
      final prescricao = {'cliente_id': c['id'], 'tecnico_id': uid, 'descricao': problema, 'recomendacoes': recomendacoes};

      if (await estaOnline()) {
        final List<String> urls = [];
        for (var i = 0; i < fotos.length; i++) {
          final caminho = '$uid/${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
          await supabase.storage.from('fotos').uploadBinary(caminho, fotos[i]);
          urls.add(supabase.storage.from('fotos').getPublicUrl(caminho));
        }
        await supabase.from('checkins').insert(checkin);
        final presc = Map<String, dynamic>.from(prescricao);
        if (urls.isNotEmpty) presc['fotos'] = urls;
        await supabase.from('prescricoes').insert(presc);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Visita registrada!'), backgroundColor: AppColors.teal700));
      } else {
        final fotosB64 = fotos.map((b) => base64Encode(b)).toList();
        await enfileirar({'tipo': 'visita', 'checkin': checkin, 'prescricao': prescricao, 'fotos': fotosB64});
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sem internet — visita salva offline.'), backgroundColor: Color(0xFFB8860B)));
      }

      setState(() => _feitos.add(c['id']));
      return true;
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível registrar: $e')));
      return false;
    }
  }
}