// ============================================================================
//  RotaCampo — Relatórios / Dashboard
//  Gestor: painel da equipe (Técnicos e Vendedores separados).
//  Vendedor/Técnico: resumo pessoal (parcial).
//  Salve como: lib/relatorios_screen.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart'; // gráficos
import 'main.dart'; // supabase, AppColors, UserRole
import 'mapa_dados.dart'; // lojaResponsavel (decide a loja de cada cliente)

// Nomes fixos das duas lojas (iguais aos que lojaResponsavel devolve)
const String _lojaPiata = 'Loja de Piatã';
const String _lojaBarra = 'Loja de Barra da Estiva';

// Decide a loja de um cliente sem erro quando faltam coordenadas.
String? _lojaDoCliente(Map<String, dynamic> c) {
  final mun = (c['municipio'] ?? '').toString().trim();
  final lat = (c['latitude'] as num?)?.toDouble();
  final lng = (c['longitude'] as num?)?.toDouble();
  if (mun.isEmpty && (lat == null || lng == null)) return null; // sem base pra decidir
  return lojaResponsavel(mun, lat ?? 0, lng ?? 0);
}

// ---------------------------------------------------------------------------
//  Agrupamento "tolerante a erro de digitação" para os relatórios.
//  Normaliza (minúsculas, sem acento), casa com o catálogo quando possível e
//  junta palavras parecidas (distância de edição pequena). Ex.: "Ferugem",
//  "ferrugem" e "Ferrugem " contam como o mesmo item.
// ---------------------------------------------------------------------------
String _normTxt(String s) {
  s = s.toLowerCase().trim();
  const acc = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c', 'ñ': 'n',
  };
  final b = StringBuffer();
  for (final ch in s.split('')) {
    b.write(acc[ch] ?? ch);
  }
  return b.toString().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

int _lev(String a, String b) {
  final m = a.length, n = b.length;
  if (m == 0) return n;
  if (n == 0) return m;
  var prev = List<int>.generate(n + 1, (i) => i);
  var cur = List<int>.filled(n + 1, 0);
  for (var i = 1; i <= m; i++) {
    cur[0] = i;
    for (var j = 1; j <= n; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      final del = prev[j] + 1, ins = cur[j - 1] + 1, sub = prev[j - 1] + cost;
      cur[j] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
    }
    final tmp = prev;
    prev = cur;
    cur = tmp;
  }
  return prev[n];
}

// Quantos erros tolerar conforme o tamanho da palavra
int _limiar(int len) => len <= 4 ? 1 : (len <= 8 ? 2 : 3);

class _Canon {
  final List<String> _catDisp = []; // nomes do catálogo (fonte da verdade)
  final List<String> _catNorm = [];
  final List<String> _disp = []; // grupos descobertos no caminho
  final List<String> _norm = [];
  _Canon(List<String> catalogo) {
    for (final c in catalogo) {
      final n = _normTxt(c);
      if (n.isEmpty) continue;
      _catDisp.add(c.trim());
      _catNorm.add(n);
    }
  }

  String key(String raw) {
    final n = _normTxt(raw);
    if (n.isEmpty) return '';
    // 1) tenta casar com o catálogo
    var best = -1, bestD = 1 << 30;
    for (var i = 0; i < _catNorm.length; i++) {
      final d = _lev(n, _catNorm[i]);
      if (d < bestD) { bestD = d; best = i; }
    }
    if (best >= 0) {
      final menor = n.length < _catNorm[best].length ? n.length : _catNorm[best].length;
      if (bestD <= _limiar(menor)) return _catDisp[best];
    }
    // 2) junta com algo parecido já visto
    var b2 = -1, bD2 = 1 << 30;
    for (var i = 0; i < _norm.length; i++) {
      final d = _lev(n, _norm[i]);
      if (d < bD2) { bD2 = d; b2 = i; }
    }
    if (b2 >= 0) {
      final menor = n.length < _norm[b2].length ? n.length : _norm[b2].length;
      if (bD2 <= _limiar(menor)) return _disp[b2];
    }
    // 3) item novo
    _norm.add(n);
    _disp.add(raw.trim());
    return raw.trim();
  }
}

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
  int _totClientes = 0, _totVisitas = 0, _totPresc = 0, _totPlantas = 0;
  // Por pessoa
  List<Map<String, dynamic>> _tecnicos = [];
  List<Map<String, dynamic>> _vendedores = [];
  // Plantas por cultura, ranking de produtos e problemas mais frequentes
  List<MapEntry<String, int>> _porCultura = [];
  List<MapEntry<String, int>> _rankProdutos = [];
  List<MapEntry<String, int>> _rankProblemas = [];
  int _plantasVisita = 0;
  List<MapEntry<String, int>> _porCulturaVisita = [];
  // Crescimento por loja (atendimentos: últimos 30 dias x 30 dias anteriores)
  final Map<String, int> _lojaAtual = {_lojaPiata: 0, _lojaBarra: 0};
  final Map<String, int> _lojaAnterior = {_lojaPiata: 0, _lojaBarra: 0};
  // Novos cadastros por loja (últimos 30 dias) e produtos que mais saem por loja
  final Map<String, int> _novosLoja = {_lojaPiata: 0, _lojaBarra: 0};
  Map<String, List<MapEntry<String, int>>> _prodLoja = {_lojaPiata: [], _lojaBarra: []};
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
      final clientes = List<Map<String, dynamic>>.from(await supabase.from('clientes').select('id, vendedor_id, municipio, latitude, longitude, criado_em'));
      final checkins = List<Map<String, dynamic>>.from(await supabase.from('checkins').select('usuario_id, cliente_id, feito_em'));
      final prescricoes = List<Map<String, dynamic>>.from(await supabase.from('prescricoes').select('tecnico_id, cliente_id, recomendacoes, alvo, descricao, praga, doenca, pragas, doencas, culturas'));
      final culturas = List<Map<String, dynamic>>.from(await supabase.from('cliente_culturas').select('cultura, plantas'));

      // Catálogos para corrigir digitação (produtos e pragas/doenças)
      final produtosCat = List<Map<String, dynamic>>.from(await supabase.from('produtos').select('nome'));
      List<Map<String, dynamic>> pragasCat = [];
      try {
        pragasCat = List<Map<String, dynamic>>.from(await supabase.from('catalogo_pragas').select('nome'));
      } catch (_) {}
      final canonProd = _Canon(produtosCat.map((e) => (e['nome'] ?? '').toString()).toList());
      final canonProb = _Canon(pragasCat.map((e) => (e['nome'] ?? '').toString()).toList());

      // Plantas: total e por cultura
      int totPlantas = 0;
      final Map<String, int> porCultura = {};
      for (final c in culturas) {
        final n = (c['plantas'] as num?)?.toInt() ?? 0;
        totPlantas += n;
        final nome = (c['cultura'] ?? 'Outra').toString();
        porCultura[nome] = (porCultura[nome] ?? 0) + n;
      }
      final porCulturaOrd = porCultura.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

      // Ranking de produtos mais recomendados
      final Map<String, int> contagemProd = {};
      for (final p in prescricoes) {
        for (final r in (p['recomendacoes'] as List?) ?? []) {
          final prod = canonProd.key((r['produto'] ?? '').toString());
          if (prod.isEmpty) continue;
          contagemProd[prod] = (contagemProd[prod] ?? 0) + 1;
        }
      }
      final rankProd = contagemProd.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

      // Problemas mais frequentes (praga e doença contadas separadamente)
      final Map<String, int> contagemProb = {};
      void addProb(String v) {
        final k = canonProb.key(v);
        if (k.isEmpty) return;
        contagemProb[k] = (contagemProb[k] ?? 0) + 1;
      }
      for (final p in prescricoes) {
        var algum = false;
        for (final a in (p['pragas'] as List?) ?? []) {
          final n = (a['nome'] ?? '').toString().trim();
          if (n.isNotEmpty) { addProb(n); algum = true; }
        }
        for (final a in (p['doencas'] as List?) ?? []) {
          final n = (a['nome'] ?? '').toString().trim();
          if (n.isNotEmpty) { addProb(n); algum = true; }
        }
        if (!algum) {
          // compatibilidade: praga/doenca em texto (pode ter vários separados por vírgula)
          for (final n in (p['praga'] ?? '').toString().split(',')) {
            if (n.trim().isNotEmpty) { addProb(n.trim()); algum = true; }
          }
          for (final n in (p['doenca'] ?? '').toString().split(',')) {
            if (n.trim().isNotEmpty) { addProb(n.trim()); algum = true; }
          }
        }
        if (!algum) {
          final alvo = (p['alvo'] ?? '').toString().trim();
          if (alvo.isNotEmpty) {
            addProb(alvo);
          } else {
            final desc = (p['descricao'] ?? '').toString().trim();
            if (desc.isNotEmpty) addProb(desc.split(' ').take(4).join(' '));
          }
        }
      }
      final rankProb = contagemProb.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

      // Plantas atendidas nas visitas (soma das culturas registradas no check-in)
      int totPlantasVisita = 0;
      final Map<String, int> plantasVisita = {};
      for (final p in prescricoes) {
        for (final cu in (p['culturas'] as List?) ?? []) {
          final n = (cu['plantas'] as num?)?.toInt() ?? 0;
          final nome = (cu['cultura'] ?? 'Outra').toString();
          if (n == 0 && nome.trim().isEmpty) continue;
          totPlantasVisita += n;
          plantasVisita[nome] = (plantasVisita[nome] ?? 0) + n;
        }
      }
      final plantasVisitaOrd = plantasVisita.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

      // mapa cliente -> vendedor
      final clienteVendedor = {for (final c in clientes) c['id']: c['vendedor_id']};

      // mapa cliente -> loja responsável (pra medir crescimento por loja)
      final clienteLoja = {for (final c in clientes) c['id']: _lojaDoCliente(c)};

      // Crescimento por loja: conta atendimentos (check-ins) em duas janelas
      //   atual   = últimos 30 dias
      //   anterior= os 30 dias antes desses
      final agora = DateTime.now();
      final inicioAtual = agora.subtract(const Duration(days: 30));
      final inicioAnterior = agora.subtract(const Duration(days: 60));
      final lojaAtual = {_lojaPiata: 0, _lojaBarra: 0};
      final lojaAnterior = {_lojaPiata: 0, _lojaBarra: 0};
      for (final ck in checkins) {
        final loja = clienteLoja[ck['cliente_id']];
        if (loja == null || !lojaAtual.containsKey(loja)) continue;
        final quando = DateTime.tryParse('${ck['feito_em']}')?.toLocal();
        if (quando == null) continue;
        if (quando.isAfter(inicioAtual)) {
          lojaAtual[loja] = lojaAtual[loja]! + 1;
        } else if (quando.isAfter(inicioAnterior)) {
          lojaAnterior[loja] = lojaAnterior[loja]! + 1;
        }
      }

      // Novos cadastros por loja (clientes criados nos últimos 30 dias)
      final novosLoja = {_lojaPiata: 0, _lojaBarra: 0};
      for (final c in clientes) {
        final loja = clienteLoja[c['id']];
        if (loja == null || !novosLoja.containsKey(loja)) continue;
        final quando = DateTime.tryParse('${c['criado_em']}')?.toLocal();
        if (quando != null && quando.isAfter(inicioAtual)) {
          novosLoja[loja] = novosLoja[loja]! + 1;
        }
      }

      // Produtos que mais saem por loja (contagem de recomendações)
      final prodPorLoja = {_lojaPiata: <String, int>{}, _lojaBarra: <String, int>{}};
      for (final p in prescricoes) {
        final loja = clienteLoja[p['cliente_id']];
        if (loja == null || !prodPorLoja.containsKey(loja)) continue;
        for (final r in (p['recomendacoes'] as List?) ?? []) {
          final prod = canonProd.key((r['produto'] ?? '').toString());
          if (prod.isEmpty) continue;
          prodPorLoja[loja]![prod] = (prodPorLoja[loja]![prod] ?? 0) + 1;
        }
      }
      List<MapEntry<String, int>> topProd(String loja) {
        final l = prodPorLoja[loja]!.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        return l.take(5).toList();
      }

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
        _totPlantas = totPlantas;
        _porCultura = porCulturaOrd;
        _rankProdutos = rankProd.take(8).toList();
        _rankProblemas = rankProb.take(8).toList();
        _plantasVisita = totPlantasVisita;
        _porCulturaVisita = plantasVisitaOrd.take(8).toList();
        _lojaAtual
          ..[_lojaPiata] = lojaAtual[_lojaPiata]!
          ..[_lojaBarra] = lojaAtual[_lojaBarra]!;
        _lojaAnterior
          ..[_lojaPiata] = lojaAnterior[_lojaPiata]!
          ..[_lojaBarra] = lojaAnterior[_lojaBarra]!;
        _novosLoja
          ..[_lojaPiata] = novosLoja[_lojaPiata]!
          ..[_lojaBarra] = novosLoja[_lojaBarra]!;
        _prodLoja = {_lojaPiata: topProd(_lojaPiata), _lojaBarra: topProd(_lojaBarra)};
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

  // Cabeçalho com a logo da empresa
  Widget _bannerLogo() => Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.teal700, AppColors.teal800, AppColors.teal900]),
          boxShadow: [BoxShadow(color: AppColors.teal900.withOpacity(.22), blurRadius: 14, offset: const Offset(0, 6))],
        ),
        child: Row(children: [
          Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            padding: const EdgeInsets.all(3),
            child: ClipOval(
              child: Image.asset(
                'assets/logo.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  decoration: const BoxDecoration(color: AppColors.coral, shape: BoxShape.circle),
                  child: const Icon(Icons.agriculture, color: Colors.white, size: 28),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Grupo Porteira Agrocomercial', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800, height: 1.15)),
              const SizedBox(height: 2),
              Text('A serviço do campo e da cidade', style: TextStyle(color: Colors.white.withOpacity(.82), fontSize: 12)),
            ]),
          ),
        ]),
      );

  // ---------- UI: dashboard do gestor ----------
  Widget _dashboardGestor() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _bannerLogo(),
        Wrap(spacing: 12, runSpacing: 12, children: [
          _cardTotal('Clientes', _totClientes, Icons.people_outline),
          _cardTotal('Visitas', _totVisitas, Icons.check_circle_outline),
          _cardTotal('Prescrições', _totPresc, Icons.description_outlined),
          _cardTotal('Plantas', _totPlantas, Icons.spa_outlined),
          _cardTotal('Equipe', _tecnicos.length + _vendedores.length, Icons.groups_outlined),
        ]),
        const SizedBox(height: 24),
        _titulo('Qual loja está crescendo mais', Icons.trending_up),
        const SizedBox(height: 4),
        const Text('Atendimentos nos últimos 30 dias x os 30 dias anteriores.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
        const SizedBox(height: 8),
        _cardCrescimentoLojas(),
        const SizedBox(height: 24),
        _titulo('Novos cadastros por loja', Icons.person_add_alt_1),
        const SizedBox(height: 4),
        const Text('Clientes cadastrados nos últimos 30 dias.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
        const SizedBox(height: 8),
        _cardNovosLojas(),
        const SizedBox(height: 24),
        _titulo('Produtos que mais saem por loja', Icons.local_shipping_outlined),
        const SizedBox(height: 4),
        const Text('Mais recomendados em cada loja (pela localização do cliente).', style: TextStyle(color: AppColors.muted, fontSize: 13)),
        const SizedBox(height: 8),
        _blocoProdutosLoja(),
        const SizedBox(height: 24),
        _titulo('Técnicos', Icons.engineering_outlined),
        const SizedBox(height: 8),
        if (_tecnicos.isEmpty)
          _semDados()
        else ...[
          _graficoBarras(_tecnicos, 'visitas', AppColors.teal700),
          const SizedBox(height: 12),
          ..._tecnicos.map(_linhaTecnico),
        ],
        const SizedBox(height: 24),
        _titulo('Vendedores', Icons.badge_outlined),
        const SizedBox(height: 8),
        if (_vendedores.isEmpty)
          _semDados()
        else ...[
          _graficoBarras(_vendedores, 'carteira', const Color(0xFFB8860B)),
          const SizedBox(height: 12),
          ..._vendedores.map(_linhaVendedor),
        ],
        const SizedBox(height: 24),
        _titulo('Plantas em acompanhamento', Icons.spa_outlined),
        const SizedBox(height: 4),
        Text('Total que a empresa trabalha no momento: $_totPlantas plantas', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
        const SizedBox(height: 8),
        _porCultura.isEmpty ? _semDados() : _cartaoBarras(_porCultura, AppColors.teal700, ' plantas'),
        const SizedBox(height: 24),
        _titulo('Plantas atendidas em visitas', Icons.local_florist_outlined),
        const SizedBox(height: 4),
        Text('Somadas nos check-ins: $_plantasVisita plantas', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
        const SizedBox(height: 8),
        _porCulturaVisita.isEmpty ? _semDados() : _cartaoBarras(_porCulturaVisita, const Color(0xFF2E7D5B), ' plantas'),
        const SizedBox(height: 24),
        _titulo('Produtos mais recomendados', Icons.medication_outlined),
        const SizedBox(height: 8),
        _rankProdutos.isEmpty ? _semDados() : _cartaoBarras(_rankProdutos, const Color(0xFF2E7D5B), 'x'),
        const SizedBox(height: 24),
        _titulo('Problemas mais frequentes', Icons.bug_report_outlined),
        const SizedBox(height: 4),
        const Text('Pragas e doenças mais registradas no campo.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
        const SizedBox(height: 8),
        _rankProblemas.isEmpty ? _semDados() : _cartaoBarras(_rankProblemas, AppColors.coral, 'x'),
      ],
    );
  }

  // ---------- Card: crescimento das lojas ----------
  // Retorna a variação %: null = "novo" (tinha 0 antes e passou a ter), senão o %.
  double? _pct(int atual, int anterior) {
    if (anterior == 0) return atual > 0 ? null : 0;
    return (atual - anterior) / anterior * 100;
  }

  // Pontuação só pra decidir quem cresceu mais (null = crescimento do zero = topo)
  double _score(int atual, int anterior) {
    final p = _pct(atual, anterior);
    if (p == null) return 100000 + atual.toDouble();
    return p;
  }

  Widget _cardCrescimentoLojas() {
    final pA = _lojaAtual[_lojaPiata]!, pB = _lojaAnterior[_lojaPiata]!;
    final bA = _lojaAtual[_lojaBarra]!, bB = _lojaAnterior[_lojaBarra]!;
    final totalAtual = pA + bA, totalAnterior = pB + bB;

    if (totalAtual == 0 && totalAnterior == 0) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.fieldBorder)),
        child: const Row(children: [
          Icon(Icons.info_outline, color: AppColors.muted, size: 20),
          SizedBox(width: 10),
          Expanded(child: Text('Ainda não há atendimentos suficientes para comparar as lojas.', style: TextStyle(color: AppColors.muted, fontSize: 13))),
        ]),
      );
    }

    final scorePiata = _score(pA, pB);
    final scoreBarra = _score(bA, bB);
    final lider = scorePiata >= scoreBarra ? _lojaPiata : _lojaBarra;
    final liderA = lider == _lojaPiata ? pA : bA;
    final liderB = lider == _lojaPiata ? pB : bB;
    final pctLider = _pct(liderA, liderB);

    String frase;
    if (pctLider == null) {
      frase = '$lider é a que mais cresceu — começou a ser atendida agora.';
    } else if (pctLider > 0) {
      frase = '$lider é a que mais cresceu: +${pctLider.toStringAsFixed(0)}% em atendimentos.';
    } else if (pctLider == 0) {
      frase = 'As duas lojas estão estáveis no período.';
    } else {
      frase = 'Nenhuma loja cresceu no período — $lider é a que caiu menos (${pctLider.toStringAsFixed(0)}%).';
    }

    return Column(children: [
      // Faixa com o destaque
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.teal700, AppColors.teal800]),
        ),
        child: Row(children: [
          const Icon(Icons.emoji_events_outlined, color: Colors.white, size: 26),
          const SizedBox(width: 12),
          Expanded(child: Text(frase, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14, height: 1.25))),
        ]),
      ),
      const SizedBox(height: 10),
      _linhaLoja('Piatã', pA, pB),
      const SizedBox(height: 8),
      _linhaLoja('Barra da Estiva', bA, bB),
    ]);
  }

  Widget _linhaLoja(String nome, int atual, int anterior) {
    final pct = _pct(atual, anterior);
    late final Color cor;
    late final String texto;
    late final IconData icone;
    if (pct == null) {
      cor = AppColors.teal700;
      texto = 'novo';
      icone = Icons.fiber_new_outlined;
    } else if (pct > 0) {
      cor = const Color(0xFF2E7D5B);
      texto = '+${pct.toStringAsFixed(0)}%';
      icone = Icons.arrow_upward;
    } else if (pct < 0) {
      cor = AppColors.coral;
      texto = '${pct.toStringAsFixed(0)}%';
      icone = Icons.arrow_downward;
    } else {
      cor = AppColors.muted;
      texto = '0%';
      icone = Icons.remove;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.fieldBorder)),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(color: AppColors.teal700.withOpacity(.10), shape: BoxShape.circle),
          child: const Icon(Icons.store_mall_directory_outlined, color: AppColors.teal700, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(nome, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 15)),
            const SizedBox(height: 2),
            Text('$atual atendimentos agora · $anterior antes', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ]),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: cor.withOpacity(.12), borderRadius: BorderRadius.circular(999)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icone, color: cor, size: 15),
            const SizedBox(width: 4),
            Text(texto, style: TextStyle(color: cor, fontWeight: FontWeight.w800, fontSize: 13)),
          ]),
        ),
      ]),
    );
  }

  String _nomeCurto(String loja) => loja.replaceFirst('Loja de ', '');

  // Card: novos cadastros por loja (duas linhas)
  Widget _cardNovosLojas() {
    Widget linha(String loja) {
      final n = _novosLoja[loja] ?? 0;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: AppColors.teal700.withOpacity(.10), shape: BoxShape.circle),
            child: const Icon(Icons.store_mall_directory_outlined, color: AppColors.teal700, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(_nomeCurto(loja), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 15))),
          Text('$n', style: const TextStyle(color: AppColors.teal700, fontWeight: FontWeight.w800, fontSize: 20)),
          const SizedBox(width: 4),
          const Text('novos', style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ]),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.fieldBorder)),
      child: Column(children: [linha(_lojaPiata), const Divider(height: 1, color: AppColors.fieldBorder), linha(_lojaBarra)]),
    );
  }

  // Bloco: produtos que mais saem, em cada loja
  Widget _blocoProdutosLoja() {
    Widget daLoja(String loja) {
      final itens = _prodLoja[loja] ?? const <MapEntry<String, int>>[];
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.store_mall_directory_outlined, size: 16, color: AppColors.teal700),
          const SizedBox(width: 6),
          Text(_nomeCurto(loja), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink, fontSize: 14)),
        ]),
        const SizedBox(height: 8),
        itens.isEmpty
            ? _semDados()
            : _cartaoBarras(itens, const Color(0xFF2E7D5B), 'x'),
      ]);
    }

    return Column(children: [
      daLoja(_lojaPiata),
      const SizedBox(height: 16),
      daLoja(_lojaBarra),
    ]);
  }

  // Lista de barras proporcionais (label à esquerda, barra + valor)
  Widget _cartaoBarras(List<MapEntry<String, int>> itens, Color cor, String sufixo) {
    final maxV = itens.map((e) => e.value).fold<int>(0, (a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.fieldBorder)),
      child: Column(children: [
        for (final e in itens)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              SizedBox(width: 92, child: Text(e.key, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600, fontSize: 13))),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: maxV == 0 ? 0 : e.value / maxV,
                    minHeight: 14,
                    backgroundColor: cor.withOpacity(.10),
                    valueColor: AlwaysStoppedAnimation(cor),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(width: 58, child: Text('${e.value}$sufixo', textAlign: TextAlign.right, style: TextStyle(color: cor, fontWeight: FontWeight.w700, fontSize: 12))),
            ]),
          ),
      ]),
    );
  }

  // Gráfico de barras: usa o campo (ex.: 'visitas' / 'carteira') de cada pessoa
  Widget _graficoBarras(List<Map<String, dynamic>> pessoas, String campo, Color cor) {
    final valores = pessoas.map((p) => (p[campo] as int?) ?? 0).toList();
    final maxV = (valores.isEmpty ? 0 : valores.reduce((a, b) => a > b ? a : b)).toDouble();
    final double topo = maxV < 4 ? 4.0 : maxV * 1.2;
    final double intervalo = (topo / 4).clamp(1, double.infinity).toDouble();

    String primeiroNome(String? n) {
      final s = (n ?? '').trim();
      if (s.isEmpty) return '-';
      final p = s.split(' ').first;
      return p.length > 8 ? '${p.substring(0, 8)}…' : p;
    }

    return Container(
      height: 220,
      padding: const EdgeInsets.fromLTRB(8, 18, 12, 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.fieldBorder)),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: topo,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: intervalo),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28, interval: intervalo)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 34,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= pessoas.length) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(primeiroNome(pessoas[i]['nome'] as String?), style: const TextStyle(fontSize: 10, color: AppColors.muted, fontWeight: FontWeight.w600)),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < pessoas.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(toY: valores[i].toDouble(), color: cor, width: 18, borderRadius: const BorderRadius.vertical(top: Radius.circular(6))),
              ]),
          ],
        ),
      ),
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
        _bannerLogo(),
        const Text('Seu resumo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
        const SizedBox(height: 16),
        Wrap(spacing: 12, runSpacing: 12, children: _meu.entries.map((e) => _cardTotal(e.key, e.value, Icons.insights_outlined)).toList()),
      ],
    );
  }
}