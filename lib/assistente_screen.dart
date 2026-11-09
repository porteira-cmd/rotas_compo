// ============================================================================
//  RotaCampo — Menino da Porteira IA (assistente de campo)
//  Chat que responde com os dados reais: quem falta visitar, montar rota do
//  dia, quem visitar primeiro e resumo. Tudo calculado localmente (grátis).
//  Salve como: lib/assistente_screen.dart
// ============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart'; // tipo LatLng
import 'main.dart'; // supabase, AppColors, UserRole
import 'rota_mapa_screen.dart'; // abrir rota sugerida
import 'acoes.dart'; // posicaoAtual (GPS)

class AssistenteScreen extends StatefulWidget {
  final UserRole role;
  const AssistenteScreen({super.key, required this.role});

  @override
  State<AssistenteScreen> createState() => _AssistenteScreenState();
}

class _Msg {
  final bool me;
  final Widget child;
  _Msg(this.me, this.child);
}

class _AssistenteScreenState extends State<AssistenteScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _msgs = [];

  List<Map<String, dynamic>> _clientes = [];
  List<Map<String, dynamic>> _usuarios = []; // equipe (nome, perfil)
  int _qtdPresc = 0;
  String _etapa = ''; // passo do cadastro por conversa ('' = nenhum)
  final Map<String, dynamic> _novoCli = {}; // dados do cliente sendo cadastrado
  final Map<dynamic, int?> _dias = {}; // clienteId -> dias sem visita (null = nunca)
  final Set<dynamic> _visit15 = {}; // visitados nos últimos 15 dias
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final cli = List<Map<String, dynamic>>.from(await supabase
          .from('clientes')
          .select('id, nome, municipio, latitude, longitude')
          .not('latitude', 'is', null)
          .not('longitude', 'is', null));
      final checks = List<Map<String, dynamic>>.from(await supabase.from('checkins').select('cliente_id, feito_em'));

      // equipe e contagem de prescrições (o que a permissão deixar ver)
      List<Map<String, dynamic>> users = [];
      int presc = 0;
      try {
        users = List<Map<String, dynamic>>.from(await supabase.from('usuarios').select('nome, perfil'));
      } catch (_) {}
      try {
        final p = await supabase.from('prescricoes').select('id');
        presc = (p as List).length;
      } catch (_) {}

      final Map<dynamic, DateTime> ultima = {};
      for (final ck in checks) {
        final d = DateTime.tryParse(ck['feito_em'] ?? '');
        if (d == null) continue;
        final id = ck['cliente_id'];
        if (!ultima.containsKey(id) || d.isAfter(ultima[id]!)) ultima[id] = d;
      }
      final agora = DateTime.now();
      for (final c in cli) {
        final u = ultima[c['id']];
        final dias = u == null ? null : agora.difference(u).inDays;
        _dias[c['id']] = dias;
        if (dias != null && dias <= 15) _visit15.add(c['id']);
      }
      setState(() {
        _clientes = cli;
        _usuarios = users;
        _qtdPresc = presc;
        _carregando = false;
      });
      _falarIA(_saudacao());
    } catch (e) {
      setState(() => _carregando = false);
      _falarIA(_texto('Tive um problema pra carregar seus dados 😕\n$e'));
    }
  }

  // -------- utilidades --------
  String _norm(String s) {
    s = s.toLowerCase();
    const de = 'áàâãäéèêëíìîïóòôõöúùûüç';
    const pa = 'aaaaaeeeeiiiiooooouuuuc';
    for (var i = 0; i < de.length; i++) {
      s = s.replaceAll(de[i], pa[i]);
    }
    return s;
  }

  double _dist(Map a, Map b) {
    final dx = (a['latitude'] as num).toDouble() - (b['latitude'] as num).toDouble();
    final dy = (a['longitude'] as num).toDouble() - (b['longitude'] as num).toDouble();
    return math.sqrt(dx * dx + dy * dy);
  }

  List<Map<String, dynamic>> _pendentes() {
    final lista = _clientes.where((c) => !_visit15.contains(c['id'])).toList();
    lista.sort((a, b) {
      final da = _dias[a['id']] ?? (1 << 30);
      final db = _dias[b['id']] ?? (1 << 30);
      return db.compareTo(da); // nunca e mais antigos primeiro
    });
    return lista;
  }

  List<Map<String, dynamic>> _ordenarPorProximidade(List<Map<String, dynamic>> pts) {
    if (pts.length <= 2) return pts;
    final restantes = List<Map<String, dynamic>>.from(pts);
    final rota = <Map<String, dynamic>>[restantes.removeAt(0)];
    while (restantes.isNotEmpty) {
      final ultimo = rota.last;
      restantes.sort((a, b) => _dist(ultimo, a).compareTo(_dist(ultimo, b)));
      rota.add(restantes.removeAt(0));
    }
    return rota;
  }

  String _desc(Map c) {
    final d = _dias[c['id']];
    final quando = d == null ? 'nunca visitado' : 'há $d dias';
    final mun = (c['municipio'] as String?)?.isNotEmpty == true ? ' · ${c['municipio']}' : '';
    return '${c['nome']} ($quando)$mun';
  }

  List<String> _porPerfil(String perfil) =>
      _usuarios.where((u) => u['perfil'] == perfil).map((u) => (u['nome'] ?? '').toString()).where((n) => n.isNotEmpty).toList();

  // Monta a resposta de uma lista da equipe (vendedores/técnicos/gestores)
  void _respEquipe(String perfil, String plural) {
    final nomes = _porPerfil(perfil);
    if (nomes.isEmpty) {
      final soEu = _usuarios.length <= 1;
      _falarIA(_texto('Não encontrei $plural${soEu ? ' — como você não é gestor, só consigo ver seu próprio cadastro aqui. Entre como gestor pra ver a equipe toda.' : '.'}'));
    } else {
      _falarIA(_texto('$plural (${nomes.length}):\n• ${nomes.join('\n• ')}'));
    }
  }

  // Visão geral do app, destacando o perfil de quem está logado
  String _visaoGeral() {
    final b = StringBuffer();
    b.writeln('O app Porteira sem fronteiras organiza o trabalho de campo da Porteira. Em resumo, dá pra:');
    b.writeln('• Cadastrar clientes com localização no mapa');
    b.writeln('• Ver todos no mapa (ruas/satélite) e por loja');
    b.writeln('• Montar rotas e executar (check-in + prescrição + fotos)');
    b.writeln('• Prioridade: quem está há +15 dias sem visita');
    b.writeln('• Catálogo de produtos e prescrições técnicas');
    b.writeln('• Relatórios e gráficos da equipe');
    b.writeln('• Avisar clientes no WhatsApp e gerar PDF');
    b.writeln();
    switch (widget.role) {
      case UserRole.gestor:
        b.write('Como *gestor*, você ainda cadastra a equipe (Equipe), envia a rota do dia pro técnico e vê o painel geral. Pergunte "como cadastro um técnico" ou "como envio rota pro técnico".');
        break;
      case UserRole.tecnico:
        b.write('Como *técnico*, seu dia é: abrir "Minhas rotas" → Executar → check-in de cada cliente. Pergunte "como faço um check-in" ou "como monto uma rota".');
        break;
      case UserRole.vendedor:
        b.write('Como *vendedor*, você cuida da sua carteira de clientes. Pergunte "como adiciono um cliente à carteira" ou "o que é a carteira".');
        break;
    }
    return b.toString();
  }

  // Explica como fazer cada coisa (t já vem normalizado, sem acentos)
  String? _comoFazer(String t) {
    bool has(List<String> ps) => ps.any((p) => t.contains(p));

    if (has(['cliente']) && has(['apagar', 'excluir', 'deletar', 'remover'])) {
      return 'Para apagar um cliente: abra o cliente (na lista ou tocando no pino do mapa) e toque na lixeira "Apagar cliente". Só o *gestor* pode apagar. Clientes com visitas/rotas ficam protegidos.';
    }
    if (has(['cliente']) && has(['cadastr', 'novo', 'adicion', 'criar', 'registr'])) {
      return 'Cadastrar cliente: Menu › Clientes › botão "Novo". Preencha nome, telefone, município e a *localização* (latitude/longitude) — dá pra usar a localização atual. Salve e o cliente já aparece no mapa.';
    }
    if (has(['rota', 'roteiro'])) {
      return 'Montar rota: Menu › Rotas. Marque os clientes na ordem (ou use "10 mais próximos"), e escolha abrir no Google Maps, Iniciar no app ou (gestor) Enviar pro técnico. Dica: peça pra mim "montar rota de hoje" que eu já monto a melhor ordem.';
    }
    if (has(['check', 'visita'])) {
      return 'Fazer check-in: abra "Minhas rotas" (ou monte uma rota) › Executar. Em cada parada você registra o problema, a prescrição (produto + dose) e fotos. O app avança sozinho pro próximo cliente até concluir a rota.';
    }
    if (has(['prescri', 'receita', 'recomenda'])) {
      return 'Prescrição: acontece no check-in. Informe Cultura e Alvo, selecione o *produto* do catálogo (a unidade/carência vêm sozinhas), ajuste a dose e a aplicação. Tudo fica salvo em Prescrições e no histórico do cliente.';
    }
    if (has(['produto'])) {
      return 'Produtos: Menu › Produtos (gestor/técnico). Cadastre nome, princípio ativo, categoria, unidade da dose e carência. Depois, no check-in, é só *selecionar* da lista e ajustar a dose.';
    }
    if (has(['carteira'])) {
      return 'Carteira: é o conjunto de clientes de cada vendedor. Menu › Carteira mostra os seus. Um cliente entra na carteira quando é vinculado a você no cadastro.';
    }
    if (has(['relatorio', 'dashboard', 'grafico', 'painel'])) {
      return 'Relatórios: Menu › Relatórios. O gestor vê o painel da equipe com gráficos (visitas por técnico, carteira por vendedor) e totais. Vendedor/técnico veem o resumo pessoal.';
    }
    if (has(['mapa', 'satelite', 'camada'])) {
      return 'Mapa: Menu › Mapa. Dá pra arrastar, zoom pela rodinha/botões, ligar satélite e camadas (municípios, áreas das lojas), ver a divisão por loja (cores) e montar rota tocando nos clientes.';
    }
    if (has(['equipe', 'funcionario', 'usuario']) || (has(['cadastr', 'novo', 'adicion']) && has(['tecnico', 'vendedor', 'gestor']))) {
      return 'Equipe: Menu › Equipe (só gestor). Toque em adicionar, preencha nome, e-mail e senha, escolha o perfil (vendedor, técnico ou gestor) e salve. A pessoa já entra com esse login.';
    }
    if (has(['enviar rota', 'rota pro tecnico', 'rota do dia', 'mandar rota'])) {
      return 'Enviar rota pro técnico (gestor): Menu › Rotas, selecione os clientes, toque em "Enviar para técnico", escolha o técnico e a data. Ela aparece em "Minhas rotas" do técnico como a rota do dia.';
    }
    if (has(['perfil', 'foto', 'senha'])) {
      return 'Meu perfil: Menu › Meu perfil. Dá pra trocar a foto (ela vira seu "boneco" no mapa), editar o nome e mudar a senha.';
    }
    if (has(['whats'])) {
      return 'WhatsApp: no mapa, nos detalhes do cliente ou na rota, toque em "Avisar clientes no WhatsApp". Abre a conversa com a mensagem pronta (um cliente por vez).';
    }
    if (has(['offline', 'internet', 'sem sinal', 'sem rede'])) {
      return 'Offline: o check-in funciona sem internet. A visita fica salva no celular e sobe sozinha quando a conexão voltar.';
    }
    if (has(['pdf'])) {
      return 'PDF: abra um cliente e toque no ícone de PDF pra gerar o histórico dele (visitas e prescrições) pra imprimir ou compartilhar.';
    }
    if (has(['prioridade', '15 dias', 'precisa de visita', 'urgente'])) {
      return 'Prioridade: Menu › Prioridade mostra quem está há mais tempo sem visita (regra dos 15 dias). Vendedor vê só a carteira; gestor e técnico veem todos. Eu também respondo "quem falta visitar".';
    }
    return null;
  }

  // -------- "cérebro" (interpreta o texto) --------
  void _responder(String txtOriginal) {
    // Se estiver no meio de um cadastro por conversa, trata aqui
    if (_etapa.isNotEmpty) {
      _fluxoCadastro(txtOriginal);
      return;
    }

    final t = _norm(txtOriginal);

    bool tem(List<String> ps) => ps.any((p) => t.contains(p));

    if (_carregando) {
      _falarIA(_texto('Peraí que ainda tô carregando os dados...'));
      return;
    }

    // Link de localização (WhatsApp/Google Maps) ou coordenadas coladas no chat
    if (_pareceLocalizacao(txtOriginal)) {
      _lerLocalizacao(txtOriginal);
      return;
    }

    // iniciar cadastro de cliente (mas não quando é pergunta "como...")
    if (!tem(['como', 'onde', 'ensina', 'tutorial', 'passo a passo']) &&
        tem(['cliente']) &&
        tem(['cadastr', 'adicion', 'criar', 'novo', 'registr'])) {
      _novoCli.clear();
      _etapa = 'nome';
      _falarIA(_texto('Bora cadastrar um cliente! 📝\nQual o *nome* dele? (escreva "cancelar" a qualquer momento pra parar)'));
      return;
    }

    // montar rota do dia
    if (tem(['rota', 'montar', 'roteiro'])) {
      final pend = _pendentes().where((c) => c['latitude'] != null).toList();
      if (pend.isEmpty) {
        _falarIA(_texto('Tá tudo visitado! 🎉 Não achei cliente pendente pra montar rota.'));
        return;
      }
      final top = pend.take(10).toList();
      final rota = _ordenarPorProximidade(top);
      final linhas = <Widget>[
        _texto('Montei uma rota com ${rota.length} clientes, priorizando quem está há mais tempo sem visita e na ordem mais curta:'),
        const SizedBox(height: 6),
        ...List.generate(rota.length, (i) => Text('${i + 1}. ${_desc(rota[i])}', style: const TextStyle(fontSize: 13, color: AppColors.ink))),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RotaMapaScreen(paradas: rota))),
            icon: const Icon(Icons.map_outlined, size: 18),
            label: const Text('Abrir essa rota no mapa'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.teal700),
          ),
        ),
      ];
      _falarIA(Column(crossAxisAlignment: CrossAxisAlignment.start, children: linhas));
      return;
    }

    // qual visitar primeiro
    if (tem(['primeiro', 'prioridade', 'urgente', 'mais importante'])) {
      final pend = _pendentes();
      if (pend.isEmpty) {
        _falarIA(_texto('Nenhum cliente pendente — tá tudo em dia! 👏'));
        return;
      }
      final p = pend.first;
      _falarIA(_texto('O mais urgente é:\n\n⭐ ${_desc(p)}\n\nÉ o que está há mais tempo sem visita. Quer que eu monte a rota do dia a partir dele? É só dizer "montar rota".'));
      return;
    }

    // quem falta visitar
    if (tem(['falta', 'pendente', 'nao visit', 'quem visit', 'resta'])) {
      final pend = _pendentes();
      if (pend.isEmpty) {
        _falarIA(_texto('Zero pendentes! Todos os clientes já foram visitados nos últimos 15 dias. 🎉'));
        return;
      }
      final mostra = pend.take(8).toList();
      _falarIA(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _texto('Faltam *${pend.length}* clientes sem visita (regra dos 15 dias). Os mais urgentes:'),
        const SizedBox(height: 6),
        ...mostra.map((c) => Text('• ${_desc(c)}', style: const TextStyle(fontSize: 13, color: AppColors.ink))),
        if (pend.length > mostra.length) Text('...e mais ${pend.length - mostra.length}.', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
      ]));
      return;
    }

    // visitados / resumo
    if (tem(['resumo', 'como estou', 'como ta', 'relatorio', 'ja visit', 'visitei', 'feitos'])) {
      final total = _clientes.length;
      final visit = _visit15.length;
      final pend = total - visit;
      _falarIA(_texto('📊 Resumo (últimos 15 dias):\n\n• Clientes no total: $total\n• Visitados: $visit\n• Faltam: $pend\n\nQuer que eu monte a rota do dia com os pendentes?'));
      return;
    }

    // equipe
    if (tem(['vendedor', 'vendedores'])) {
      _respEquipe('vendedor', 'Vendedores');
      return;
    }
    if (tem(['tecnico', 'tecnicos'])) {
      _respEquipe('tecnico', 'Técnicos');
      return;
    }
    if (tem(['gestor', 'gestores'])) {
      _respEquipe('gestor', 'Gestores');
      return;
    }
    if (tem(['equipe', 'time', 'quem trabalha', 'pessoal'])) {
      final g = _porPerfil('gestor').length, v = _porPerfil('vendedor').length, te = _porPerfil('tecnico').length;
      _falarIA(_texto('👥 Equipe:\n• Gestores: $g\n• Vendedores: $v\n• Técnicos: $te\n\nQuer a lista de nomes? Peça "vendedores", "técnicos" ou "gestores".'));
      return;
    }

    // prescrições
    if (tem(['prescri', 'receita', 'recomenda'])) {
      _falarIA(_texto('Foram $_qtdPresc prescrições registradas${widget.role == UserRole.tecnico ? ' por você' : ''}.'));
      return;
    }

    // quantos clientes
    if (tem(['quantos cliente', 'quantas cliente', 'total de cliente', 'numero de cliente'])) {
      _falarIA(_texto('Você tem ${_clientes.length} clientes com localização cadastrada.'));
      return;
    }

    // visão geral do app (por perfil)
    if (tem(['o que o app', 'o que esse app', 'o que da pra fazer', 'o que voce faz', 'o que voce sabe', 'funcoes', 'funcionalidades', 'recursos', 'o que esse sistema', 'pra que serve', 'me explica o app'])) {
      _falarIA(_texto(_visaoGeral()));
      return;
    }

    // "como faço / onde fica X" — guia passo a passo
    if (tem(['como', 'onde', 'ensina', 'tutorial', 'passo a passo', 'ajuda com', 'nao sei', 'me ensina'])) {
      final h = _comoFazer(t);
      if (h != null) {
        _falarIA(_texto(h));
        return;
      }
    }

    // saudação / ajuda
    if (tem(['oi', 'ola', 'bom dia', 'boa tarde', 'boa noite', 'ajuda', 'menino', 'ei'])) {
      _falarIA(_saudacao());
      return;
    }

    // não entendi
    _falarIA(_texto('Ainda não entendi essa 🤔. Eu ajudo com:\n\n• Dados: "quem falta visitar", "montar rota", "qual visitar primeiro", "resumo"\n• Equipe: "vendedores", "técnicos", "gestores", "equipe"\n• Como usar: "o que o app faz", "como cadastro um cliente", "como faço check-in", "como monto uma rota"...\n\nÉ só perguntar ou tocar num atalho.'));
  }

  // -------- cadastro de cliente por conversa --------
  Future<void> _fluxoCadastro(String texto) async {
    final t = _norm(texto).trim();
    if (['cancelar', 'parar', 'sair', 'cancela'].contains(t)) {
      _etapa = '';
      _novoCli.clear();
      _falarIA(_texto('Cadastro cancelado. 👍'));
      return;
    }
    switch (_etapa) {
      case 'nome':
        _novoCli['nome'] = texto.trim();
        _etapa = 'municipio';
        _falarIA(_texto('Qual o *município* (cidade) do cliente?'));
        break;
      case 'municipio':
        _novoCli['municipio'] = texto.trim();
        _etapa = 'telefone';
        _falarIA(_texto('*Telefone* com DDD? (ou escreva "pular")'));
        break;
      case 'telefone':
        if (!['pular', 'nao', 'sem', 'n'].contains(t)) _novoCli['telefone'] = texto.trim();
        // Se a localização já veio de um link/coordenada, salva direto.
        if (_novoCli['latitude'] != null && _novoCli['longitude'] != null) {
          await _salvarCliente();
        } else {
          _etapa = 'local';
          _falarIA(_texto('Agora a *localização*:\n• Cole o *link* do Google Maps/WhatsApp, ou\n• Escreva "minha localização" pra usar o GPS, ou\n• Digite: latitude, longitude  (ex.: -13.512, -41.585)'));
        }
        break;
      case 'local':
        await _resolverLocal(texto);
        break;
    }
  }

  // Tem um link (http) no texto?
  bool _temLink(String s) => RegExp(r'https?://', caseSensitive: false).hasMatch(s);
  // Pega o primeiro link do texto
  String? _primeiroLink(String s) => RegExp(r'https?://\S+', caseSensitive: false).firstMatch(s)?.group(0);
  // O texto parece uma localização (link do mapa ou coordenadas)?
  bool _pareceLocalizacao(String s) => _temLink(s) || extrairCoordenadas(s) != null;

  // Lê um link de localização (ou coordenadas) colado no chat e oferece ações
  Future<void> _lerLocalizacao(String texto) async {
    LatLng? pos = extrairCoordenadas(texto);
    if (pos == null && _temLink(texto)) {
      _falarIA(_texto('Lendo o link da localização... 📍'));
      final url = _primeiroLink(texto);
      if (url != null) pos = await resolverLocalizacaoLink(url);
    }
    if (pos == null) {
      _falarIA(_texto('Não consegui ler essa localização 😕.\nCole o link do Google Maps/WhatsApp de novo, ou mande as coordenadas assim: -13.512, -41.585.'));
      return;
    }
    final lat = pos.latitude, lng = pos.longitude;
    _falarIA(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _texto('Localização lida! 📍\nLatitude: ${lat.toStringAsFixed(6)}\nLongitude: ${lng.toStringAsFixed(6)}'),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => _cadastrarAqui(lat, lng),
          icon: const Icon(Icons.person_add_alt_1, size: 18),
          label: const Text('Cadastrar cliente aqui'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.teal700),
        ),
      ),
      const SizedBox(height: 6),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => abrirNavegacao(lat, lng),
          icon: const Icon(Icons.map_outlined, size: 18),
          label: const Text('Abrir no mapa'),
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.teal700, side: const BorderSide(color: AppColors.teal500)),
        ),
      ),
    ]));
  }

  // Começa o cadastro já com a localização preenchida
  void _cadastrarAqui(double lat, double lng) {
    _novoCli.clear();
    _novoCli['latitude'] = lat;
    _novoCli['longitude'] = lng;
    _etapa = 'nome';
    _falarIA(_texto('Boa! Vou cadastrar um cliente nessa localização. 📍\nQual o *nome* dele? (escreva "cancelar" pra parar)'));
  }

  Future<void> _resolverLocal(String texto) async {
    final t = _norm(texto);
    double? lat, lng;
    if (t.contains('minha') || t.contains('gps') || t.contains('atual') || t.contains('aqui')) {
      _falarIA(_texto('Pegando sua localização... 📍'));
      final LatLng? pos = await posicaoAtual();
      if (pos == null) {
        _falarIA(_texto('Não consegui o GPS (permissão?). Pode digitar as coordenadas ou colar o link do mapa.'));
        return;
      }
      lat = pos.latitude;
      lng = pos.longitude;
    } else {
      // tenta coordenadas digitadas ou um link de localização
      LatLng? pos = extrairCoordenadas(texto);
      if (pos == null && _temLink(texto)) {
        _falarIA(_texto('Lendo o link da localização... 📍'));
        final url = _primeiroLink(texto);
        if (url != null) pos = await resolverLocalizacaoLink(url);
      }
      if (pos == null) {
        _falarIA(_texto('Não entendi a localização 😕. Você pode:\n• Colar o *link* do Google Maps/WhatsApp\n• Mandar as coordenadas: -13.512, -41.585\n• Escrever "minha localização" pra usar o GPS'));
        return;
      }
      lat = pos.latitude;
      lng = pos.longitude;
    }
    _novoCli['latitude'] = lat;
    _novoCli['longitude'] = lng;
    await _salvarCliente();
  }

  Future<void> _salvarCliente() async {
    final nome = _novoCli['nome'];
    try {
      final dados = Map<String, dynamic>.from(_novoCli);
      if (widget.role == UserRole.vendedor) dados['vendedor_id'] = supabase.auth.currentUser!.id;
      final r = await supabase.from('clientes').insert(dados).select('id, nome, municipio, latitude, longitude');
      if ((r as List).isEmpty) throw 'sem permissão';
      final novo = Map<String, dynamic>.from(r.first);
      _clientes.add(novo);
      _dias[novo['id']] = null; // nunca visitado
      _etapa = '';
      _novoCli.clear();
      _falarIA(_texto('Cliente "$nome" cadastrado com sucesso! ✅\nJá aparece no mapa e na lista.'));
    } catch (e) {
      _etapa = '';
      _novoCli.clear();
      _falarIA(_texto('Não consegui salvar 😕: $e\nTente de novo dizendo "cadastrar cliente".'));
    }
  }

  Widget _saudacao() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _texto('Opa! Sou o Menino da Porteira 🤠\nTô de olho nos seus clientes. Posso te ajudar com:'),
        const SizedBox(height: 6),
        const Text('• Quem falta visitar\n• Montar a rota do dia\n• Qual visitar primeiro\n• Resumo da semana\n• A equipe (vendedores, técnicos, gestores)\n• Cadastrar um cliente (é só pedir!)\n• Ler um link de localização (cole o link do Maps/WhatsApp aqui)\n• Como usar qualquer parte do app', style: TextStyle(fontSize: 13, color: AppColors.ink)),
        const SizedBox(height: 6),
        const Text('Toca num atalho abaixo ou me pergunta. 👇', style: TextStyle(fontSize: 12, color: AppColors.muted)),
      ]);

  Widget _texto(String s) => Text(s, style: const TextStyle(fontSize: 14, color: AppColors.ink, height: 1.35));

  void _falarIA(Widget child) {
    setState(() => _msgs.add(_Msg(false, child)));
    _rolar();
  }

  void _enviar(String txt) {
    final t = txt.trim();
    if (t.isEmpty) return;
    setState(() => _msgs.add(_Msg(true, Text(t, style: const TextStyle(fontSize: 14, color: Colors.white, height: 1.35)))));
    _ctrl.clear();
    _rolar();
    Future.delayed(const Duration(milliseconds: 250), () => _responder(t));
  }

  void _rolar() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent + 120, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.teal700,
        foregroundColor: Colors.white,
        title: Row(children: [
          _avatarIA(16),
          const SizedBox(width: 10),
          const Text('Menino da Porteira IA'),
        ]),
      ),
      body: Column(children: [
        Expanded(
          child: _carregando
              ? const Center(child: CircularProgressIndicator(color: AppColors.teal500))
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: _msgs.length,
                  itemBuilder: (_, i) => _bolha(_msgs[i]),
                ),
        ),
        _atalhos(),
        _barraInput(),
      ]),
    );
  }

  // Foto do Menino da Porteira (boneco)
  Widget _avatarIA(double r) => CircleAvatar(
        radius: r,
        backgroundColor: Colors.white,
        backgroundImage: const AssetImage('assets/menino_ia.png'),
      );

  Widget _bolha(_Msg m) {
    final balao = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * (m.me ? 0.82 : 0.72)),
      decoration: BoxDecoration(
        color: m.me ? AppColors.teal700 : Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(m.me ? 16 : 4),
          bottomRight: Radius.circular(m.me ? 4 : 16),
        ),
        border: m.me ? null : Border.all(color: AppColors.fieldBorder),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.05), blurRadius: 6)],
      ),
      child: m.child,
    );
    if (m.me) {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        alignment: Alignment.centerRight,
        child: balao,
      );
    }
    // Mensagem da IA: boneco à esquerda + balão
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _avatarIA(15),
        const SizedBox(width: 8),
        Flexible(child: balao),
      ]),
    );
  }

  Widget _atalhos() {
    final itens = [
      ('Quem falta', 'Quem falta visitar'),
      ('Rota de hoje', 'Montar rota de hoje'),
      ('Visitar 1º', 'Qual visitar primeiro'),
      ('Resumo', 'Resumo'),
      ('O que o app faz', 'O que o app faz'),
      ('Equipe', 'Equipe'),
      ('Cadastrar cliente', 'Cadastrar cliente'),
    ];
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: itens
            .map((e) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    label: Text(e.$1),
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: AppColors.teal500),
                    labelStyle: const TextStyle(color: AppColors.teal700, fontWeight: FontWeight.w600, fontSize: 13),
                    onPressed: () => _enviar(e.$2),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _barraInput() {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 6, 12, 10 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.fieldBorder))),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            onSubmitted: _enviar,
            textInputAction: TextInputAction.send,
            decoration: InputDecoration(
              hintText: 'Pergunte ao Menino da Porteira...',
              filled: true,
              fillColor: AppColors.field,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(width: 8),
        CircleAvatar(
          radius: 24,
          backgroundColor: AppColors.coral,
          child: IconButton(icon: const Icon(Icons.send, color: Colors.white), onPressed: () => _enviar(_ctrl.text)),
        ),
      ]),
    );
  }
}