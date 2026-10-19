// ============================================================================
//  RotaCampo — Histórico do cliente (linha do tempo)
//  Mostra visitas (check-ins) e prescrições em ordem, com fotos.
//  Salve como: lib/cliente_historico_screen.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'main.dart'; // supabase, AppColors
import 'acoes.dart'; // WhatsApp e navegação
import 'visitas_screen.dart' show formatarData;
import 'pdf_cliente.dart'; // gerar PDF

class ClienteHistoricoScreen extends StatefulWidget {
  final Map<String, dynamic> cliente;
  const ClienteHistoricoScreen({super.key, required this.cliente});

  @override
  State<ClienteHistoricoScreen> createState() => _ClienteHistoricoScreenState();
}

class _ClienteHistoricoScreenState extends State<ClienteHistoricoScreen> {
  Map<String, dynamic> _cliente = {};
  List<Map<String, dynamic>> _eventos = [];
  bool _carregando = true;
  String? _erro;
  bool _gerandoPdf = false;

  Future<void> _gerarPdf() async {
    setState(() => _gerandoPdf = true);
    try {
      await gerarPdfCliente(_cliente, _eventos);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível gerar o PDF: $e')));
    } finally {
      if (mounted) setState(() => _gerandoPdf = false);
    }
  }

  Future<void> _editar() async {
    final nome = TextEditingController(text: _cliente['nome'] ?? '');
    final tel = TextEditingController(text: _cliente['telefone'] ?? '');
    final lat = TextEditingController(text: (_cliente['latitude'] ?? '').toString());
    final lng = TextEditingController(text: (_cliente['longitude'] ?? '').toString());

    final salvar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar cliente'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nome, decoration: const InputDecoration(labelText: 'Nome')),
            const SizedBox(height: 10),
            TextField(controller: tel, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Telefone')),
            const SizedBox(height: 10),
            TextField(controller: lat, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'Latitude')),
            const SizedBox(height: 10),
            TextField(controller: lng, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'Longitude')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
        ],
      ),
    );
    if (salvar != true) return;

    try {
      // .select() no fim: se vier vazio, a permissão bloqueou (edição silenciosa)
      final res = await supabase.from('clientes').update({
        'nome': nome.text.trim(),
        'telefone': tel.text.trim(),
        'latitude': double.tryParse(lat.text.trim()),
        'longitude': double.tryParse(lng.text.trim()),
      }).eq('id', _cliente['id']).select();

      if (!mounted) return;
      if ((res as List).isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Você não tem permissão pra editar este cliente. Entre como Gestor, ou adicione-o à sua carteira.'),
          backgroundColor: Color(0xFFC23A2B),
        ));
      } else {
        await _carregar();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cliente atualizado!'), backgroundColor: AppColors.teal700));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
    }
  }

  @override
  void initState() {
    super.initState();
    _cliente = Map<String, dynamic>.from(widget.cliente);
    _carregar();
  }

  Future<void> _carregar() async {
    final id = widget.cliente['id'];
    try {
      // dados completos do cliente (pra ter telefone e coordenadas)
      final c = await supabase.from('clientes').select('id, nome, telefone, municipio, endereco, latitude, longitude').eq('id', id).single();

      final visitas = await supabase.from('checkins').select('feito_em, observacao').eq('cliente_id', id).order('feito_em', ascending: false);
      final presc = await supabase.from('prescricoes').select('criado_em, descricao, fotos, recomendacoes').eq('cliente_id', id).order('criado_em', ascending: false);

      final eventos = <Map<String, dynamic>>[];
      for (final v in (visitas as List)) {
        eventos.add({'tipo': 'visita', 'quando': v['feito_em'], 'texto': v['observacao'] ?? ''});
      }
      for (final p in (presc as List)) {
        eventos.add({'tipo': 'prescricao', 'quando': p['criado_em'], 'texto': p['descricao'] ?? '', 'fotos': p['fotos'], 'recomendacoes': p['recomendacoes']});
      }
      // ordena do mais recente pro mais antigo
      eventos.sort((a, b) => (DateTime.tryParse(b['quando'] ?? '') ?? DateTime(0)).compareTo(DateTime.tryParse(a['quando'] ?? '') ?? DateTime(0)));

      setState(() {
        _cliente = Map<String, dynamic>.from(c);
        _eventos = eventos;
        _carregando = false;
      });
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
      appBar: AppBar(
        backgroundColor: AppColors.teal700,
        foregroundColor: Colors.white,
        title: Text(_cliente['nome'] ?? 'Cliente'),
        actions: [
          IconButton(
            tooltip: 'Editar cliente',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _carregando ? null : _editar,
          ),
          IconButton(
            tooltip: 'Gerar PDF',
            icon: _gerandoPdf
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.picture_as_pdf_outlined),
            onPressed: (_carregando || _gerandoPdf) ? null : _gerarPdf,
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator(color: AppColors.teal500))
          : _erro != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Erro: $_erro', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFC23A2B)))))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _cabecalho(),
                    const SizedBox(height: 20),
                    const Text('Linha do tempo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
                    const SizedBox(height: 12),
                    if (_eventos.isEmpty)
                      const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Text('Nenhuma visita ou prescrição ainda.', style: TextStyle(color: AppColors.muted)))
                    else
                      ...List.generate(_eventos.length, (i) => _itemLinha(_eventos[i], i == _eventos.length - 1)),
                  ],
                ),
    );
  }

  Widget _cabecalho() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.fieldBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((_cliente['municipio'] as String?)?.isNotEmpty == true) _linhaInfo(Icons.map_outlined, _cliente['municipio']),
          if ((_cliente['telefone'] as String?)?.isNotEmpty == true) _linhaInfo(Icons.phone_outlined, _cliente['telefone']),
          if ((_cliente['endereco'] as String?)?.isNotEmpty == true) _linhaInfo(Icons.place_outlined, _cliente['endereco']),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final ok = await abrirWhatsApp(_cliente['telefone'], 'Olá ${_cliente['nome']}!');
                  if (!ok && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cliente sem telefone.')));
                },
                icon: const Icon(Icons.chat, size: 18),
                label: const Text('WhatsApp'),
                style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF128C7E), side: const BorderSide(color: Color(0xFF128C7E))),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  final la = _cliente['latitude'], ln = _cliente['longitude'];
                  if (la != null && ln != null) abrirNavegacao((la as num).toDouble(), (ln as num).toDouble());
                },
                icon: const Icon(Icons.navigation_outlined, size: 18),
                label: const Text('Navegar'),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.teal700, side: const BorderSide(color: AppColors.teal500)),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _linhaInfo(IconData icon, String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: AppColors.muted),
          const SizedBox(width: 8),
          Expanded(child: Text(texto, style: const TextStyle(color: AppColors.ink))),
        ]),
      );

  Widget _itemLinha(Map<String, dynamic> e, bool ultimo) {
    final visita = e['tipo'] == 'visita';
    final cor = visita ? const Color(0xFF2E7D5B) : AppColors.teal700;
    final icone = visita ? Icons.check_circle : Icons.description_outlined;
    final fotos = (e['fotos'] as List?) ?? [];

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // trilho da linha do tempo (bolinha + linha)
          Column(children: [
            Container(width: 28, height: 28, decoration: BoxDecoration(color: cor.withOpacity(.12), shape: BoxShape.circle), child: Icon(icone, size: 16, color: cor)),
            if (!ultimo) Expanded(child: Container(width: 2, color: AppColors.fieldBorder)),
          ]),
          const SizedBox(width: 12),
          // conteúdo
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.fieldBorder)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(visita ? 'Visita' : 'Prescrição', style: TextStyle(fontWeight: FontWeight.w700, color: cor, fontSize: 13)),
                      const Spacer(),
                      Text(formatarData(e['quando']), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                    ]),
                    if ((e['texto'] as String).isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(e['texto'], style: const TextStyle(color: AppColors.ink, height: 1.4)),
                    ],
                    if ((e['recomendacoes'] as List?)?.isNotEmpty == true) ...[
                      const SizedBox(height: 6),
                      ...(e['recomendacoes'] as List).map((r) => Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Icon(Icons.medication_outlined, size: 15, color: AppColors.teal700),
                              const SizedBox(width: 6),
                              Expanded(child: Text('${r['produto']}${(r['dosagem'] ?? '').toString().isNotEmpty ? ' — ${r['dosagem']}' : ''}', style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w500))),
                            ]),
                          )),
                    ],
                    if (fotos.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 68,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: fotos.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, k) {
                            final url = fotos[k] as String;
                            return GestureDetector(
                              onTap: () => showDialog(context: context, builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(url)))),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(url, width: 68, height: 68, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 68, height: 68, color: AppColors.field, child: const Icon(Icons.broken_image, color: AppColors.muted))),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}