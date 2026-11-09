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
String _mensagemPrescricao(String nome, String problema, List recs, [List crono = const []]) {
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
      final jaTem = r['origem'] == 'propriedade' ? ' (já tem na propriedade)' : '';
      b.writeln('- $prod${dose.isNotEmpty ? ' — $dose' : ''}$jaTem');
    }
    b.writeln();
  }
  if (crono.isNotEmpty) {
    b.writeln('Cronograma de aplicação:');
    for (var i = 0; i < crono.length; i++) {
      final e = crono[i];
      final quando = (e['quando'] ?? '').toString();
      final dose = (e['dose'] ?? '').toString();
      final obs = (e['obs'] ?? '').toString();
      final linha = [if (quando.isNotEmpty) quando, '${e['produto'] ?? ''}', if (dose.isNotEmpty) '($dose)'].join(' - ');
      b.writeln('${i + 1}. $linha${obs.isNotEmpty ? ' — $obs' : ''}');
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
          .select('id, descricao, cultura, alvo, praga, doenca, pragas, doencas, culturas, criado_em, fotos, praga_fotos, doenca_fotos, recomendacoes, estoque, cronograma, clientes!inner(nome, municipio, telefone, vendedor_id)');

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

  // Apagar prescrição (só gestor) — usa a função apagar_prescricao no banco
  Future<void> _apagarPrescricao(Map<String, dynamic> p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar prescrição'),
        content: Text('Apagar a prescrição de ${_nomeCliente(p)}? Essa ação não pode ser desfeita.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC23A2B)), child: const Text('Apagar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await supabase.rpc('apagar_prescricao', params: {'p_id': p['id']});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Prescrição apagada.'), backgroundColor: AppColors.teal700));
      _carregar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível apagar: $e')));
    }
  }

  // Galeria de fotos em tela cheia, deslizando entre elas
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
            child: IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 28), onPressed: () => Navigator.of(context).pop()),
          ),
        ]),
      ),
    );
  }

  Widget _chip(String txt) => _chipCor(txt, AppColors.teal700);

  Widget _chipCor(String txt, Color cor) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: cor.withOpacity(.12), borderRadius: BorderRadius.circular(999)),
        child: Text(txt, style: TextStyle(color: cor, fontWeight: FontWeight.w600, fontSize: 11)),
      );

  List<String> _todasFotos(Map<String, dynamic> p) => <String>[
        ...((p['fotos'] as List?) ?? []).whereType<String>(),
        ...((p['praga_fotos'] as List?) ?? []).whereType<String>(),
        ...((p['doenca_fotos'] as List?) ?? []).whereType<String>(),
      ];

  // Resumo compacto mostrado no card da lista
  Widget _resumoChips(Map<String, dynamic> p) {
    final chips = <Widget>[];
    final culturasArr = (p['culturas'] as List?) ?? [];
    if (culturasArr.isNotEmpty) {
      final n = (culturasArr.first['cultura'] ?? '').toString();
      if (n.isNotEmpty) chips.add(_chip(n));
    } else if ((p['cultura'] as String?)?.isNotEmpty == true) {
      chips.add(_chip('${p['cultura']}'));
    }
    final prag = (p['pragas'] as List?) ?? [];
    final doen = (p['doencas'] as List?) ?? [];
    if (prag.isNotEmpty && (prag.first['nome'] ?? '').toString().isNotEmpty) {
      chips.add(_chipCor('Praga: ${prag.first['nome']}', AppColors.coral));
    } else if ((p['praga'] as String?)?.isNotEmpty == true) {
      chips.add(_chipCor('Praga: ${p['praga']}', AppColors.coral));
    }
    if (doen.isNotEmpty && (doen.first['nome'] ?? '').toString().isNotEmpty) {
      chips.add(_chipCor('Doença: ${doen.first['nome']}', const Color(0xFFB8860B)));
    } else if ((p['doenca'] as String?)?.isNotEmpty == true) {
      chips.add(_chipCor('Doença: ${p['doenca']}', const Color(0xFFB8860B)));
    }
    final recN = ((p['recomendacoes'] as List?) ?? []).length;
    if (recN > 0) chips.add(_chip('$recN produto${recN > 1 ? 's' : ''}'));
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 6, runSpacing: 4, children: chips);
  }

  // Abre a prescrição completa num painel deslizante
  void _abrirPrescricao(Map<String, dynamic> p) {
    final c = p['clientes'] as Map<String, dynamic>?;
    final todasFotos = _todasFotos(p);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .85,
        minChildSize: .5,
        maxChildSize: .95,
        builder: (ctx, scroll) => SingleChildScrollView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.description_outlined, color: AppColors.teal700),
              const SizedBox(width: 8),
              Expanded(child: Text(c?['nome'] ?? 'Cliente', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink))),
              if (widget.role == UserRole.tecnico)
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: AppColors.teal700),
                  tooltip: 'Editar',
                  onPressed: () {
                    Navigator.pop(ctx);
                    _editar(p);
                  },
                ),
              IconButton(
                icon: const Icon(Icons.chat, color: Color(0xFF128C7E)),
                tooltip: 'Enviar no WhatsApp',
                onPressed: () async {
                  final tel = (c?['telefone'] as String?) ?? '';
                  final msg = _mensagemPrescricao(c?['nome'] ?? 'cliente', p['descricao'] ?? '', (p['recomendacoes'] as List?) ?? [], (p['cronograma'] as List?) ?? []);
                  final ok = await abrirWhatsApp(tel, msg);
                  if (!ok && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cliente sem telefone cadastrado.')));
                },
              ),
              if (widget.role == UserRole.gestor)
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Color(0xFFC23A2B)),
                  tooltip: 'Apagar prescrição',
                  onPressed: () {
                    Navigator.pop(ctx);
                    _apagarPrescricao(p);
                  },
                ),
            ]),
            Text(formatarData(p['criado_em'] as String?), style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            const SizedBox(height: 10),
            ..._conteudoDetalhe(p, todasFotos),
          ]),
        ),
      ),
    );
  }

  // Conteúdo completo da prescrição (culturas, pragas/doenças, produtos, estoque, cronograma, fotos)
  List<Widget> _conteudoDetalhe(Map<String, dynamic> p, List<String> todasFotos) {
    return [
      Builder(builder: (_) {
        final chips = <Widget>[];
        for (final cu in (p['culturas'] as List?) ?? []) {
          final nome = (cu['cultura'] ?? '').toString();
          if (nome.isEmpty) continue;
          final pl = cu['plantas'];
          chips.add(_chip(pl != null ? '$nome · $pl plantas' : nome));
        }
        if (chips.isEmpty && (p['cultura'] as String?)?.isNotEmpty == true) chips.add(_chip('Cultura: ${p['cultura']}'));
        for (final a in (p['pragas'] as List?) ?? []) {
          final n = (a['nome'] ?? '').toString();
          if (n.isNotEmpty) chips.add(_chipCor('Praga: $n', AppColors.coral));
        }
        if (((p['pragas'] as List?) ?? []).isEmpty && (p['praga'] as String?)?.isNotEmpty == true) chips.add(_chipCor('Praga: ${p['praga']}', AppColors.coral));
        for (final a in (p['doencas'] as List?) ?? []) {
          final n = (a['nome'] ?? '').toString();
          if (n.isNotEmpty) chips.add(_chipCor('Doença: $n', const Color(0xFFB8860B)));
        }
        if (((p['doencas'] as List?) ?? []).isEmpty && (p['doenca'] as String?)?.isNotEmpty == true) chips.add(_chipCor('Doença: ${p['doenca']}', const Color(0xFFB8860B)));
        if (chips.isEmpty) return const SizedBox.shrink();
        return Padding(padding: const EdgeInsets.only(bottom: 4), child: Wrap(spacing: 6, runSpacing: 4, children: chips));
      }),
      const SizedBox(height: 8),
      if ((p['descricao'] ?? '').toString().isNotEmpty) Text(p['descricao'], style: const TextStyle(color: AppColors.ink, height: 1.4)),
      if ((p['recomendacoes'] as List?)?.isNotEmpty == true) ...[
        const SizedBox(height: 10),
        const Text('Recomendações', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
        ...(p['recomendacoes'] as List).map((r) {
          final extra = [
            if ((r['principio'] ?? '').toString().isNotEmpty) '${r['principio']}',
            if ((r['modalidade'] ?? '').toString().isNotEmpty) 'Aplicação: ${r['modalidade']}',
            if ((r['carencia'] ?? '').toString().isNotEmpty) 'Carência: ${r['carencia']} dias',
          ].join(' • ');
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.medication_outlined, size: 16, color: AppColors.teal700),
              const SizedBox(width: 6),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text('${r['produto']}${(r['dosagem'] ?? '').toString().isNotEmpty ? ' — ${r['dosagem']}' : ''}', style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600))),
                    if (r['origem'] == 'propriedade') ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: AppColors.teal500.withOpacity(.14), borderRadius: BorderRadius.circular(999)),
                        child: const Text('já tem', style: TextStyle(color: AppColors.teal700, fontSize: 10, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ]),
                  if (extra.isNotEmpty) Text(extra, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                ]),
              ),
            ]),
          );
        }),
      ],
      if ((p['estoque'] as List?)?.isNotEmpty == true) ...[
        const SizedBox(height: 10),
        Row(children: const [
          Icon(Icons.inventory_2_outlined, size: 16, color: AppColors.muted),
          SizedBox(width: 6),
          Text('Já tem na propriedade', style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 12)),
        ]),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 4, children: [
          ...(p['estoque'] as List).map((e) {
            final prod = (e['produto'] ?? '').toString();
            final qtd = (e['quantidade'] ?? '').toString();
            final un = (e['unidade'] ?? '').toString();
            final txt = qtd.isNotEmpty ? '$prod — $qtd $un'.trim() : prod;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(999), border: Border.all(color: AppColors.fieldBorder)),
              child: Text(txt, style: const TextStyle(color: AppColors.ink, fontSize: 11, fontWeight: FontWeight.w500)),
            );
          }),
        ]),
      ],
      if ((p['cronograma'] as List?)?.isNotEmpty == true) ...[
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AppColors.teal500.withOpacity(.07), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.teal500.withOpacity(.25))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: const [
              Icon(Icons.event_note_outlined, size: 16, color: AppColors.teal700),
              SizedBox(width: 6),
              Text('Cronograma de aplicação', style: TextStyle(color: AppColors.teal700, fontWeight: FontWeight.w700, fontSize: 12)),
            ]),
            const SizedBox(height: 6),
            ...List.generate((p['cronograma'] as List).length, (k) {
              final e = (p['cronograma'] as List)[k] as Map<String, dynamic>;
              final quando = (e['quando'] ?? '').toString();
              final dose = (e['dose'] ?? '').toString();
              final obs = (e['obs'] ?? '').toString();
              final linha = [
                if (quando.isNotEmpty) quando,
                '${e['produto'] ?? ''}',
                if (dose.isNotEmpty) '($dose)',
              ].join(' · ');
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(width: 20, height: 20, alignment: Alignment.center, margin: const EdgeInsets.only(top: 1), decoration: const BoxDecoration(color: AppColors.teal700, shape: BoxShape.circle), child: Text('${k + 1}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(linha, style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600, fontSize: 13)),
                      if (obs.isNotEmpty) Text(obs, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                    ]),
                  ),
                ]),
              );
            }),
          ]),
        ),
      ],
      if (todasFotos.isNotEmpty) ...[
        const SizedBox(height: 12),
        const Text('Fotos', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
        const SizedBox(height: 6),
        SizedBox(
          height: 90,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: todasFotos.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, k) {
              final url = todasFotos[k];
              return GestureDetector(
                onTap: () => _abrirGaleria(todasFotos, k),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(url, width: 90, height: 90, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(width: 90, height: 90, color: AppColors.field, child: const Icon(Icons.broken_image, color: AppColors.muted))),
                ),
              );
            },
          ),
        ),
      ],
    ];
  }

  // Editar a prescrição (só o técnico que criou — garantido pela RLS).
  Future<void> _editar(Map<String, dynamic> p) async {
    final problema = TextEditingController(text: (p['descricao'] ?? '').toString());
    final recsData = (p['recomendacoes'] as List?) ?? [];
    final List<Map<String, TextEditingController>> recs = recsData.isEmpty
        ? [
            {'produto': TextEditingController(), 'dosagem': TextEditingController()}
          ]
        : recsData
            .map<Map<String, TextEditingController>>((r) => {
                  'produto': TextEditingController(text: (r['produto'] ?? '').toString()),
                  'dosagem': TextEditingController(text: (r['dosagem'] ?? '').toString()),
                })
            .toList();
    bool salvando = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Editar prescrição — ${_nomeCliente(p)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
                const SizedBox(height: 16),
                TextField(controller: problema, maxLines: 2, decoration: const InputDecoration(labelText: 'Problema encontrado', border: OutlineInputBorder(), alignLabelWithHint: true)),
                const SizedBox(height: 18),
                const Text('Recomendações (produto + dosagem)', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                const SizedBox(height: 8),
                ...List.generate(recs.length, (i) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(children: [
                        Expanded(flex: 3, child: TextField(controller: recs[i]['produto'], decoration: const InputDecoration(labelText: 'Produto', border: OutlineInputBorder(), isDense: true))),
                        const SizedBox(width: 8),
                        Expanded(flex: 2, child: TextField(controller: recs[i]['dosagem'], decoration: const InputDecoration(labelText: 'Dosagem', border: OutlineInputBorder(), isDense: true))),
                        IconButton(icon: const Icon(Icons.remove_circle_outline, color: AppColors.muted), onPressed: recs.length == 1 ? null : () => setSheet(() => recs.removeAt(i))),
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
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: salvando
                        ? null
                        : () async {
                            setSheet(() => salvando = true);
                            final recsList = recs
                                .map((r) => {'produto': r['produto']!.text.trim(), 'dosagem': r['dosagem']!.text.trim()})
                                .where((r) => (r['produto'] as String).isNotEmpty)
                                .toList();
                            try {
                              final res = await supabase
                                  .from('prescricoes')
                                  .update({'descricao': problema.text.trim(), 'recomendacoes': recsList})
                                  .eq('id', p['id'])
                                  .select('id'); // .select() revela se a RLS bloqueou
                              if (res.isEmpty) throw 'Sem permissão para editar (apenas o técnico que criou).';
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Prescrição atualizada!'), backgroundColor: AppColors.teal700));
                                _carregar();
                              }
                            } catch (e) {
                              setSheet(() => salvando = false);
                              if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Não foi possível salvar: $e')));
                            }
                          },
                    icon: salvando ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_outlined),
                    label: Text(salvando ? 'Salvando...' : 'Salvar alterações'),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.teal700, padding: const EdgeInsets.symmetric(vertical: 14)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

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
                                return InkWell(
                                  onTap: () => _abrirPrescricao(p),
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.fieldBorder)),
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        const Icon(Icons.description_outlined, color: AppColors.teal700, size: 20),
                                        const SizedBox(width: 8),
                                        Expanded(child: Text(c?['nome'] ?? 'Cliente', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink))),
                                        if (widget.role == UserRole.tecnico)
                                          IconButton(
                                            icon: const Icon(Icons.edit_outlined, color: AppColors.teal700),
                                            tooltip: 'Editar prescrição',
                                            onPressed: () => _editar(p),
                                          ),
                                        IconButton(
                                          icon: const Icon(Icons.chat, color: Color(0xFF128C7E)),
                                          tooltip: 'Enviar no WhatsApp',
                                          onPressed: () async {
                                            final tel = (c?['telefone'] as String?) ?? '';
                                            final msg = _mensagemPrescricao(c?['nome'] ?? 'cliente', p['descricao'] ?? '', (p['recomendacoes'] as List?) ?? [], (p['cronograma'] as List?) ?? []);
                                            final ok = await abrirWhatsApp(tel, msg);
                                            if (!ok && mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cliente sem telefone cadastrado.')));
                                            }
                                          },
                                        ),
                                      ]),
                                      const SizedBox(height: 4),
                                      Text(formatarData(p['criado_em'] as String?), style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                                      const SizedBox(height: 6),
                                      _resumoChips(p),
                                      const SizedBox(height: 10),
                                      Row(children: const [
                                        Icon(Icons.open_in_full, size: 14, color: AppColors.teal700),
                                        SizedBox(width: 6),
                                        Text('Toque para abrir a prescrição', style: TextStyle(color: AppColors.teal700, fontSize: 12, fontWeight: FontWeight.w600)),
                                      ]),
                                    ],
                                  ),
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