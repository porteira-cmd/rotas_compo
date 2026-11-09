// ============================================================================
//  RotaCampo — main.dart (completo, com todos os imports)
//  Rodar: flutter run -d edge
// ============================================================================

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mapa_screen.dart';
import 'prioridade_screen.dart';
import 'equipe_screen.dart';
import 'carteira_screen.dart';
import 'cadastro_cliente_screen.dart';
import 'visitas_screen.dart';
import 'prescricoes_screen.dart';
import 'relatorios_screen.dart';
import 'rotas_screen.dart';
import 'minhas_rotas_screen.dart';
import 'cliente_historico_screen.dart';
import 'perfil_screen.dart';
import 'sobre_screen.dart';
import 'produtos_screen.dart';
import 'assistente_screen.dart';
import 'agenda_screen.dart';
import 'catalogo_pragas_screen.dart';
import 'splash_screen.dart';
import 'notificacoes_screen.dart';
import 'rotas_tecnicos_screen.dart';

const String supabaseUrl = 'https://nkefheoniufxuulspgrr.supabase.co';
const String supabaseAnonKey = 'sb_publishable_YKuENF9apMDo0wgcllgk-Q_B71-5jRN';

final supabase = Supabase.instance.client;

// ----------------------------------------------------------------------------
//  Lembrar quem logou (pra entrar offline, no campo, sem internet)
// ----------------------------------------------------------------------------
const String _kPerfilSalvo = 'sessao_perfil';
const String _kNomeSalvo = 'sessao_nome';

Future<void> salvarSessaoLocal(String perfil, String nome) async {
  try {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPerfilSalvo, perfil);
    await p.setString(_kNomeSalvo, nome);
  } catch (_) {}
}

Future<void> limparSessaoLocal() async {
  try {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kPerfilSalvo);
    await p.remove(_kNomeSalvo);
  } catch (_) {}
}

Future<Map<String, String>?> lerSessaoLocal() async {
  try {
    final p = await SharedPreferences.getInstance();
    final perfil = p.getString(_kPerfilSalvo);
    final nome = p.getString(_kNomeSalvo);
    if (perfil == null) return null;
    return {'perfil': perfil, 'nome': nome ?? 'Usuário'};
  } catch (_) {
    return null;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Se não houver internet, o initialize não pode derrubar o app (tela branca).
  try {
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  } catch (_) {
    // segue mesmo assim; a sessão salva no aparelho ainda permite entrar
  }
  runApp(const RotaCampoApp());
}

// Paleta inspirada na logo da Porteira Agrocomercial:
// verde forte da marca + vermelho tomate como destaque.
class AppColors {
  static const teal900 = Color(0xFF0C3B1E); // verde bem escuro
  static const teal800 = Color(0xFF115029);
  static const teal700 = Color(0xFF167A3C); // verde principal (da logo)
  static const teal500 = Color(0xFF2E9E54); // verde claro
  static const coral = Color(0xFFE23A2D); // vermelho tomate (destaque)
  static const ink = Color(0xFF14311E); // texto escuro esverdeado
  static const muted = Color(0xFF5C7365);
  static const field = Color(0xFFF2F7F3);
  static const fieldBorder = Color(0xFFD5E3D8);
  static const page = Color(0xFFEDF3EE);
}

enum UserRole { gestor, vendedor, tecnico }

UserRole perfilFromText(String s) => switch (s) {
      'gestor' => UserRole.gestor,
      'tecnico' => UserRole.tecnico,
      _ => UserRole.vendedor,
    };

String nomeDoPerfil(UserRole r) => switch (r) {
      UserRole.gestor => 'Gestor',
      UserRole.vendedor => 'Vendedor',
      UserRole.tecnico => 'Técnico',
    };

class RotaCampoApp extends StatelessWidget {
  const RotaCampoApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Porteira sem fronteiras',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.page,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.teal500),
        textTheme: GoogleFonts.interTextTheme(),
      ),
      home: const SplashScreen(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Future<Widget> _inicial = _decidir();

  Future<Widget> _decidir() async {
    final session = supabase.auth.currentSession;
    // Nunca logou neste aparelho → tela de login.
    if (session == null) return const LoginScreen();

    // Já logou antes aqui? Entra NA HORA com os dados salvos (funciona offline)
    // e confere o perfil na internet por trás, sem travar a tela.
    final salvo = await lerSessaoLocal();
    if (salvo != null) {
      _atualizarPerfilEmSegundoPlano(session.user.id);
      return HomeScreen(role: perfilFromText(salvo['perfil']!), nome: salvo['nome']!);
    }

    // Tem sessão mas nada salvo: precisa da internet só desta vez.
    try {
      final linha = await supabase
          .from('usuarios')
          .select('perfil, nome')
          .eq('id', session.user.id)
          .single()
          .timeout(const Duration(seconds: 8));
      final perfil = linha['perfil'] as String;
      final nome = (linha['nome'] as String?) ?? 'Usuário';
      await salvarSessaoLocal(perfil, nome);
      return HomeScreen(role: perfilFromText(perfil), nome: nome);
    } catch (_) {
      return const _SemConexaoScreen();
    }
  }

  // Atualiza perfil/nome salvos pra próxima abertura, sem segurar a tela.
  void _atualizarPerfilEmSegundoPlano(String uid) {
    supabase
        .from('usuarios')
        .select('perfil, nome')
        .eq('id', uid)
        .single()
        .timeout(const Duration(seconds: 8))
        .then((linha) {
      final perfil = linha['perfil'] as String?;
      final nome = linha['nome'] as String?;
      if (perfil != null) salvarSessaoLocal(perfil, nome ?? 'Usuário');
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _inicial,
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.teal500)));
        }
        return snap.data ?? const LoginScreen();
      },
    );
  }
}

// Mostrada só no caso raro de ter sessão mas nenhum perfil salvo e estar offline.
class _SemConexaoScreen extends StatelessWidget {
  const _SemConexaoScreen();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off_rounded, size: 64, color: AppColors.muted),
                const SizedBox(height: 16),
                Text('Sem internet', style: GoogleFonts.archivo(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ink)),
                const SizedBox(height: 8),
                const Text(
                  'Conecte-se à internet uma vez para liberar o acesso offline. Depois disso você consegue entrar mesmo sem sinal.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, fontSize: 14),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AuthGate())),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tentar de novo'),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.teal700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
//  LOGIN
// ============================================================================
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _senhaCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _senhaCtrl.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final res = await supabase.auth.signInWithPassword(email: _emailCtrl.text.trim(), password: _senhaCtrl.text);
      final linha = await supabase.from('usuarios').select('perfil, nome').eq('id', res.user!.id).single();
      final perfil = linha['perfil'] as String;
      final nome = (linha['nome'] as String?) ?? 'Usuário';
      await salvarSessaoLocal(perfil, nome); // libera o acesso offline no campo
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => HomeScreen(role: perfilFromText(perfil), nome: nome)));
    } on AuthException catch (e) {
      _erro('Não foi possível entrar: ${e.message}');
    } on PostgrestException catch (e) {
      _erro('Login ok, mas o perfil não foi encontrado. (${e.message})');
    } catch (_) {
      _erro('Algo deu errado. Tente de novo.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _erro(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: const Color(0xFFC23A2B)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > 820;
            if (wide) {
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Row(children: [
                    const Expanded(flex: 105, child: _BrandPanel()),
                    Expanded(flex: 100, child: _buildForm(compact: false)),
                  ]),
                ),
              );
            }
            return SingleChildScrollView(child: _buildForm(compact: true));
          },
        ),
      ),
    );
  }

  Widget _buildForm({required bool compact}) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.symmetric(horizontal: compact ? 24 : 40, vertical: 40),
      alignment: Alignment.center,
      constraints: BoxConstraints(minHeight: compact ? 0 : double.infinity),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (compact) ...[
                Row(children: [
                  _logoBox(),
                  const SizedBox(width: 12),
                  Text('Porteira sem fronteiras', style: GoogleFonts.archivo(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ink)),
                ]),
                const SizedBox(height: 32),
              ],
              Text('Bem-vindo de volta', style: const TextStyle(color: AppColors.teal500, fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              Text('Entrar', style: GoogleFonts.archivo(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.ink, letterSpacing: -.6)),
              const SizedBox(height: 6),
              const Text('Acesse com sua conta corporativa.', style: TextStyle(color: AppColors.muted, fontSize: 14)),
              const SizedBox(height: 28),
              _label('E-mail'),
              const SizedBox(height: 7),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: _inputDeco(hint: 'voce@empresa.com.br', icon: Icons.mail_outline),
                validator: (v) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch((v ?? '').trim()) ? null : 'Digite um e-mail válido.',
              ),
              const SizedBox(height: 16),
              _label('Senha'),
              const SizedBox(height: 7),
              TextFormField(
                controller: _senhaCtrl,
                obscureText: _obscure,
                decoration: _inputDeco(
                  hint: 'Sua senha',
                  icon: Icons.lock_outline,
                  suffix: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: AppColors.muted, size: 20),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) => (v ?? '').length < 4 ? 'A senha precisa de ao menos 4 caracteres.' : null,
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: () {}, child: const Text('Esqueci a senha', style: TextStyle(color: AppColors.teal500, fontWeight: FontWeight.w600))),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _entrar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.coral,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.coral.withOpacity(.7),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _loading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text('Entrar', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward, size: 18),
                        ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String t) => Text(t, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink));

  InputDecoration _inputDeco({required String hint, required IconData icon, Widget? suffix}) {
    OutlineInputBorder b(Color c, [double w = 1.5]) => OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c, width: w));
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.muted),
      prefixIcon: Icon(icon, color: AppColors.muted, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: AppColors.field,
      contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 14),
      enabledBorder: b(AppColors.fieldBorder),
      focusedBorder: b(AppColors.teal500, 1.8),
      errorBorder: b(const Color(0xFFC23A2B)),
      focusedErrorBorder: b(const Color(0xFFC23A2B), 1.8),
    );
  }
}

// Logo da empresa. Tenta carregar assets/logo.png; se não existir ainda,
// mostra um ícone de reserva pra não quebrar o app.
Widget _logoBox() => Container(
      width: 46,
      height: 46,
      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      padding: const EdgeInsets.all(2),
      child: ClipOval(
        child: Image.asset(
          'assets/logo.png',
          width: 42,
          height: 42,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            decoration: const BoxDecoration(color: AppColors.coral, shape: BoxShape.circle),
            child: const Icon(Icons.location_on, color: Colors.white, size: 22),
          ),
        ),
      ),
    );

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(52),
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.teal700, AppColors.teal800, AppColors.teal900]),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            _logoBox(),
            const SizedBox(width: 12),
            Text('Porteira sem fronteiras', style: GoogleFonts.archivo(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Sua equipe,\ndo escritório à estrada.', style: GoogleFonts.archivo(color: Colors.white, fontSize: 34, height: 1.1, fontWeight: FontWeight.w700, letterSpacing: -1)),
            const SizedBox(height: 16),
            const Text('Rotas, visitas e check-ins de campo em um só lugar — no celular e no navegador.', style: TextStyle(color: Color(0xFFBFE0DA), fontSize: 15, height: 1.6)),
          ]),
          Wrap(spacing: 10, runSpacing: 10, children: const [
            _RoleChip('Gestor', Color(0xFF6FE3CF)),
            _RoleChip('Vendedor', Color(0xFFFFCF6B)),
            _RoleChip('Técnico', Color(0xFFFF9D80)),
          ]),
        ],
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final String label;
  final Color dot;
  const _RoleChip(this.label, this.dot);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(color: Colors.white.withOpacity(.09), borderRadius: BorderRadius.circular(999), border: Border.all(color: Colors.white.withOpacity(.16))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: Color(0xFFE7F5F2), fontSize: 13, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ============================================================================
//  HOME — menu por perfil
// ============================================================================
class _MenuItem {
  final String label;
  final IconData icon;
  final Set<UserRole> perfis;
  final Widget Function(UserRole role) tela;
  final String? asset; // imagem no lugar do ícone (opcional)
  const _MenuItem(this.label, this.icon, this.perfis, this.tela, {this.asset});
}

final List<_MenuItem> _menu = [
  _MenuItem('Menino da Porteira IA', Icons.smart_toy_outlined, {UserRole.gestor, UserRole.vendedor, UserRole.tecnico}, (r) => AssistenteScreen(role: r), asset: 'assets/menino_ia.png'),
  _MenuItem('Clientes', Icons.people_outline, {UserRole.gestor, UserRole.vendedor, UserRole.tecnico}, (r) => ClientesScreen(role: r)),
  _MenuItem('Avisos', Icons.notifications_outlined, {UserRole.gestor, UserRole.vendedor}, (r) => NotificacoesScreen(role: r)),
  _MenuItem('Carteira', Icons.folder_shared_outlined, {UserRole.vendedor}, (r) => CarteiraScreen(role: r)),
  _MenuItem('Equipe', Icons.badge_outlined, {UserRole.gestor}, (r) => EquipeScreen(role: r)),
  _MenuItem('Prioridade', Icons.priority_high, {UserRole.gestor, UserRole.vendedor, UserRole.tecnico}, (r) => PrioridadeScreen(role: r)),
  _MenuItem('Rotas', Icons.route_outlined, {UserRole.gestor, UserRole.tecnico}, (r) => RotasScreen(role: r)),
  _MenuItem('Minhas rotas', Icons.assignment_outlined, {UserRole.tecnico}, (r) => MinhasRotasScreen(role: r)),
  _MenuItem('Rotas dos técnicos', Icons.groups_2_outlined, {UserRole.gestor, UserRole.tecnico, UserRole.vendedor}, (r) => RotasTecnicosScreen(role: r)),
  _MenuItem('Rotas da equipe', Icons.alt_route_outlined, {UserRole.gestor}, (r) => MinhasRotasScreen(role: r)),
  _MenuItem('Agenda', Icons.calendar_month_outlined, {UserRole.gestor, UserRole.vendedor, UserRole.tecnico}, (r) => AgendaScreen(role: r)),
  _MenuItem('Prescrições', Icons.description_outlined, {UserRole.gestor, UserRole.vendedor, UserRole.tecnico}, (r) => PrescricoesScreen(role: r)),
  _MenuItem('Produtos', Icons.inventory_2_outlined, {UserRole.gestor, UserRole.tecnico}, (r) => ProdutosScreen(role: r)),
  _MenuItem('Catálogo de pragas', Icons.pest_control_outlined, {UserRole.gestor, UserRole.vendedor, UserRole.tecnico}, (r) => CatalogoPragasScreen(role: r)),
  _MenuItem('Visitas', Icons.event_available_outlined, {UserRole.gestor, UserRole.vendedor, UserRole.tecnico}, (r) => VisitasScreen(role: r)),
  _MenuItem('Relatórios', Icons.bar_chart_outlined, {UserRole.gestor, UserRole.vendedor, UserRole.tecnico}, (r) => RelatoriosScreen(role: r)),
  _MenuItem('Mapa', Icons.map_outlined, {UserRole.gestor, UserRole.vendedor, UserRole.tecnico}, (r) => MapaScreen(role: r)),
  _MenuItem('Meu perfil', Icons.account_circle_outlined, {UserRole.gestor, UserRole.vendedor, UserRole.tecnico}, (_) => const PerfilScreen()),
  _MenuItem('Sobre', Icons.info_outline, {UserRole.gestor, UserRole.vendedor, UserRole.tecnico}, (_) => const SobreScreen()),
];

class HomeScreen extends StatefulWidget {
  final UserRole role;
  final String nome;
  const HomeScreen({super.key, required this.role, required this.nome});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PageController _pc = PageController(viewportFraction: 0.82);
  int _page = 0;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  Future<void> _sair() async {
    await limparSessaoLocal(); // esquece o perfil salvo neste aparelho
    try {
      await supabase.auth.signOut();
    } catch (_) {}
    if (mounted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final itens = _menu.where((m) => m.perfis.contains(widget.role)).toList();
    // Técnico entra já em "Minhas rotas" (primeira opção do carrossel)
    if (widget.role == UserRole.tecnico) {
      final idx = itens.indexWhere((m) => m.label == 'Minhas rotas');
      if (idx > 0) itens.insert(0, itens.removeAt(idx));
    }
    // Carrossel só no celular. Windows/web/desktop usam a grade de antes.
    final largura = MediaQuery.of(context).size.width;
    final desktopOuWeb = kIsWeb ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS;
    final usarCarrossel = !desktopOuWeb && largura < 700;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFF4F9F5), AppColors.page]),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: usarCarrossel ? 680 : 1100),
              child: usarCarrossel ? _carrossel(itens) : _grade(itens),
            ),
          ),
        ),
      ),
    );
  }

  // Grade de cards (Windows, web e telas largas) — como era antes.
  Widget _grade(List<_MenuItem> itens) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final cols = w >= 1000 ? 5 : w >= 820 ? 4 : w >= 560 ? 3 : 2;
        const gap = 14.0;
        const padH = 16.0;
        final cardW = (w - padH * 2 - gap * (cols - 1)) / cols;
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _hero(context),
              Padding(
                padding: const EdgeInsets.fromLTRB(padH, 4, padH, 28),
                child: Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: itens.map((m) => _MenuCard(item: m, role: widget.role, width: cardW)).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Carrossel deslizável (celular).
  Widget _carrossel(List<_MenuItem> itens) {
    return Column(
      children: [
        _hero(context),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
          child: Row(children: [
            const Icon(Icons.swipe, size: 16, color: AppColors.muted),
            const SizedBox(width: 6),
            Text('Deslize para os lados • ${itens.isEmpty ? 0 : _page + 1}/${itens.length}',
                style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ),
        Expanded(
          child: PageView.builder(
            controller: _pc,
            onPageChanged: (i) => setState(() => _page = i),
            itemCount: itens.length,
            itemBuilder: (_, i) => _cardCarrossel(itens[i], i == _page),
          ),
        ),
        _dots(itens.length),
        const SizedBox(height: 16),
      ],
    );
  }

  // Card grande do carrossel (um por "página")
  Widget _cardCarrossel(_MenuItem m, bool ativo) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => m.tela(widget.role))),
      child: AnimatedScale(
        scale: ativo ? 1 : 0.9,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
        child: Container(
          margin: const EdgeInsets.fromLTRB(10, 12, 10, 18),
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.white, Color(0xFFEFF5F0)]),
            border: Border.all(color: Colors.white, width: 1),
            boxShadow: [
              BoxShadow(color: AppColors.teal900.withOpacity(.16), blurRadius: 26, offset: const Offset(0, 16)),
              const BoxShadow(color: Colors.white, blurRadius: 14, offset: Offset(-6, -6)),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.teal500, AppColors.teal700]),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [BoxShadow(color: AppColors.teal700.withOpacity(.45), blurRadius: 18, offset: const Offset(0, 10))],
                ),
                child: m.asset != null
                    ? ClipRRect(borderRadius: BorderRadius.circular(28), child: Image.asset(m.asset!, fit: BoxFit.cover))
                    : Icon(m.icon, color: Colors.white, size: 46),
              ),
              const SizedBox(height: 22),
              Text(m.label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22, color: AppColors.ink)),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.teal700, AppColors.teal500]),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: const [
                  Text('Abrir', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                  SizedBox(width: 6),
                  Icon(Icons.arrow_forward, size: 16, color: Colors.white),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dots(int total) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final ativo = i == _page;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: ativo ? 20 : 7,
          height: 7,
          decoration: BoxDecoration(
            color: ativo ? AppColors.teal700 : AppColors.teal700.withOpacity(.25),
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }

  Widget _hero(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.teal700, AppColors.teal800, AppColors.teal900]),
        boxShadow: [BoxShadow(color: AppColors.teal900.withOpacity(.25), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _logoBox(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Porteira sem fronteiras', style: GoogleFonts.archivo(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, height: 1.1)),
                  Text('Grupo Porteira Agrocomercial', style: GoogleFonts.inter(color: Colors.white.withOpacity(.85), fontSize: 12, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            IconButton(icon: const Icon(Icons.logout, color: Colors.white), tooltip: 'Sair', onPressed: _sair),
          ]),
          const SizedBox(height: 20),
          Text('Olá, ${widget.nome} 👋', style: GoogleFonts.archivo(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -.5)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: Colors.white.withOpacity(.14), borderRadius: BorderRadius.circular(999), border: Border.all(color: Colors.white.withOpacity(.22))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.verified_user_outlined, color: Color(0xFFBFE0DA), size: 15),
              const SizedBox(width: 6),
              Text('Perfil: ${nomeDoPerfil(widget.role)}', style: const TextStyle(color: Color(0xFFE7F5F2), fontWeight: FontWeight.w600, fontSize: 13)),
            ]),
          ),
        ],
      ),
    );
  }
}

class _MenuCard extends StatefulWidget {
  final _MenuItem item;
  final UserRole role;
  final double width;
  const _MenuCard({required this.item, required this.role, required this.width});

  @override
  State<_MenuCard> createState() => _MenuCardState();
}

class _MenuCardState extends State<_MenuCard> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) {
        setState(() => _down = false);
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => widget.item.tela(widget.role)));
      },
      child: AnimatedScale(
        scale: _down ? 0.96 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: widget.width,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.white, Color(0xFFEFF5F0)]),
            border: Border.all(color: Colors.white, width: 1),
            boxShadow: _down
                ? [BoxShadow(color: AppColors.teal900.withOpacity(.14), blurRadius: 8, offset: const Offset(0, 3))]
                : [
                    // sombra escura embaixo (profundidade) + brilho claro em cima (relevo)
                    BoxShadow(color: AppColors.teal900.withOpacity(.16), blurRadius: 20, offset: const Offset(0, 12)),
                    const BoxShadow(color: Colors.white, blurRadius: 12, offset: Offset(-5, -5)),
                  ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ícone "flutuante" com gradiente e sombra própria (efeito 3D)
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.teal500, AppColors.teal700]),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: AppColors.teal700.withOpacity(.45), blurRadius: 12, offset: const Offset(0, 7))],
                ),
                child: widget.item.asset != null
                    ? ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.asset(widget.item.asset!, fit: BoxFit.cover))
                    : Icon(widget.item.icon, color: Colors.white, size: 26),
              ),
              const SizedBox(height: 16),
              Text(widget.item.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.ink)),
              const SizedBox(height: 4),
              Row(children: const [
                Text('Abrir', style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
                SizedBox(width: 2),
                Icon(Icons.arrow_forward, size: 13, color: AppColors.muted),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
//  CLIENTES
// ============================================================================
class ClientesScreen extends StatefulWidget {
  final UserRole role;
  const ClientesScreen({super.key, required this.role});
  @override
  State<ClientesScreen> createState() => _ClientesScreenState();
}

class _ClientesScreenState extends State<ClientesScreen> {
  List<Map<String, dynamic>> _clientes = [];
  bool _carregando = true;
  String? _erro;
  String _busca = '';

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
      final data = await supabase.from('clientes').select('id, nome, telefone, municipio, endereco, latitude, longitude').order('nome');
      setState(() {
        _clientes = List<Map<String, dynamic>>.from(data);
        _carregando = false;
      });
    } catch (e) {
      setState(() {
        _erro = 'Não foi possível carregar os clientes.\n$e';
        _carregando = false;
      });
    }
  }

  Future<void> _novo() async {
    final criou = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CadastroClienteScreen(role: widget.role)),
    );
    if (criou == true) _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _clientes.where((c) => (c['nome'] as String).toLowerCase().contains(_busca.toLowerCase())).toList();
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.teal700, foregroundColor: Colors.white, title: const Text('Clientes')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.coral,
        foregroundColor: Colors.white,
        onPressed: _novo,
        icon: const Icon(Icons.add),
        label: const Text('Novo'),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator(color: AppColors.teal500))
          : _erro != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_erro!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFC23A2B)))))
              : Column(children: [
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
                    child: filtrados.isEmpty
                        ? const Center(child: Text('Nenhum cliente encontrado.', style: TextStyle(color: AppColors.muted)))
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            itemCount: filtrados.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (_, i) {
                              final c = filtrados[i];
                              return Container(
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.fieldBorder)),
                                child: ListTile(
                                  onTap: () => Navigator.of(context)
                                      .push(MaterialPageRoute(builder: (_) => ClienteHistoricoScreen(cliente: c)))
                                      .then((_) => _carregar()),
                                  leading: CircleAvatar(
                                    backgroundColor: AppColors.teal500.withOpacity(.12),
                                    child: Text((c['nome'] as String).isNotEmpty ? (c['nome'] as String)[0].toUpperCase() : '?', style: const TextStyle(color: AppColors.teal700, fontWeight: FontWeight.w700)),
                                  ),
                                  title: Text(c['nome'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                                  subtitle: Text([
                                    if ((c['municipio'] as String?)?.isNotEmpty == true) c['municipio'],
                                    if ((c['telefone'] as String?)?.isNotEmpty == true) c['telefone'],
                                  ].join(' • ')),
                                  trailing: const Icon(Icons.chevron_right, color: AppColors.muted),
                                ),
                              );
                            },
                          ),
                  ),
                ]),
    );
  }
}

class EmBreveScreen extends StatelessWidget {
  final String titulo;
  const EmBreveScreen(this.titulo, {super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.teal700, foregroundColor: Colors.white, title: Text(titulo)),
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.construction, size: 56, color: AppColors.muted),
          const SizedBox(height: 12),
          Text('"$titulo" em construção', style: GoogleFonts.archivo(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 6),
          const Text('Essa tela é a próxima da fila. 🙂', style: TextStyle(color: AppColors.muted)),
        ]),
      ),
    );
  }
}