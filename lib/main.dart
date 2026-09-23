// ============================================================================
//  RotaCampo — main.dart (completo)
//  Rodar: flutter run -d edge
// ============================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'mapa_screen.dart';
import 'prioridade_screen.dart';
import 'equipe_screen.dart';
import 'carteira_screen.dart';
import 'cadastro_cliente_screen.dart';
import 'visitas_screen.dart';
import 'prescricoes_screen.dart';
import 'relatorios_screen.dart';
import 'rotas_screen.dart';
import 'cliente_historico_screen.dart';

const String supabaseUrl = 'https://nkefheoniufxuulspgrr.supabase.co';
const String supabaseAnonKey = 'sb_publishable_YKuENF9apMDo0wgcllgk-Q_B71-5jRN';

final supabase = Supabase.instance.client;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  runApp(const RotaCampoApp());
}

class AppColors {
  static const teal900 = Color(0xFF0D2F2C);
  static const teal800 = Color(0xFF123F3A);
  static const teal700 = Color(0xFF0E6157);
  static const teal500 = Color(0xFF12897A);
  static const coral = Color(0xFFF2603C);
  static const ink = Color(0xFF12312E);
  static const muted = Color(0xFF5F7370);
  static const field = Color(0xFFF4F7F6);
  static const fieldBorder = Color(0xFFD6E0DE);
  static const page = Color(0xFFEEF2F1);
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
      title: 'RotaCampo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.page,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.teal500),
        textTheme: GoogleFonts.interTextTheme(),
      ),
      home: const AuthGate(),
    );
  }
}

// ============================================================================
//  PORTEIRO — mantém a sessão (não pede senha toda vez)
// ============================================================================
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Future<Widget> _inicial = _decidir();

  Future<Widget> _decidir() async {
    final session = supabase.auth.currentSession;
    if (session == null) return const LoginScreen();
    try {
      final linha = await supabase.from('usuarios').select('perfil, nome').eq('id', session.user.id).single();
      final role = perfilFromText(linha['perfil'] as String);
      final nome = (linha['nome'] as String?) ?? 'Usuário';
      return HomeScreen(role: role, nome: nome);
    } catch (_) {
      await supabase.auth.signOut();
      return const LoginScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _inicial,
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.teal500)));
        }
        return snap.data!;
      },
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
      final role = perfilFromText(linha['perfil'] as String);
      final nome = (linha['nome'] as String?) ?? 'Usuário';
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => HomeScreen(role: role, nome: nome)));
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
                  Text('RotaCampo', style: GoogleFonts.archivo(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ink)),
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

Widget _logoBox() => Container(
      width: 42, height: 42,
      decoration: BoxDecoration(color: AppColors.coral, borderRadius: BorderRadius.circular(12)),
      child: const Icon(Icons.location_on, color: Colors.white, size: 22),
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
            Text('RotaCampo', style: GoogleFonts.archivo(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
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
  const _MenuItem(this.label, this.icon, this.perfis, this.tela);
}

final List<_MenuItem> _menu = [
  _MenuItem('Clientes', Icons.people_outline, {UserRole.gestor, UserRole.vendedor, UserRole.tecnico}, (r) => ClientesScreen(role: r)),
  _MenuItem('Carteira', Icons.folder_shared_outlined, {UserRole.vendedor}, (r) => CarteiraScreen(role: r)),
  _MenuItem('Equipe', Icons.badge_outlined, {UserRole.gestor}, (r) => EquipeScreen(role: r)),
  _MenuItem('Prioridade', Icons.priority_high, {UserRole.gestor, UserRole.vendedor, UserRole.tecnico}, (r) => PrioridadeScreen(role: r)),
  _MenuItem('Rotas', Icons.route_outlined, {UserRole.gestor, UserRole.tecnico}, (r) => RotasScreen(role: r)),
  _MenuItem('Prescrições', Icons.description_outlined, {UserRole.gestor, UserRole.vendedor, UserRole.tecnico}, (r) => PrescricoesScreen(role: r)),
  _MenuItem('Visitas', Icons.event_available_outlined, {UserRole.gestor, UserRole.vendedor, UserRole.tecnico}, (r) => VisitasScreen(role: r)),
  _MenuItem('Relatórios', Icons.bar_chart_outlined, {UserRole.gestor, UserRole.vendedor, UserRole.tecnico}, (r) => RelatoriosScreen(role: r)),
  _MenuItem('Mapa', Icons.map_outlined, {UserRole.gestor, UserRole.vendedor, UserRole.tecnico}, (r) => MapaScreen(role: r)),
];

class HomeScreen extends StatelessWidget {
  final UserRole role;
  final String nome;
  const HomeScreen({super.key, required this.role, required this.nome});

  @override
  Widget build(BuildContext context) {
    final itens = _menu.where((m) => m.perfis.contains(role)).toList();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.teal700,
        foregroundColor: Colors.white,
        title: const Text('RotaCampo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sair',
            onPressed: () async {
              await supabase.auth.signOut();
              if (context.mounted) {
                Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Olá, $nome 👋', style: GoogleFonts.archivo(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.ink)),
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: AppColors.teal500.withOpacity(.12), borderRadius: BorderRadius.circular(999)),
              child: Text('Perfil: ${nomeDoPerfil(role)}', style: const TextStyle(color: AppColors.teal700, fontWeight: FontWeight.w600, fontSize: 13)),
            ),
            const SizedBox(height: 24),
            Wrap(spacing: 14, runSpacing: 14, children: itens.map((m) => _MenuCard(item: m, role: role)).toList()),
          ],
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final _MenuItem item;
  final UserRole role;
  const _MenuCard({required this.item, required this.role});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      height: 120,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => item.tela(role))),
          child: Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.fieldBorder)),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: AppColors.teal500.withOpacity(.12), borderRadius: BorderRadius.circular(12)),
                  child: Icon(item.icon, color: AppColors.teal700, size: 22),
                ),
                Text(item.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: AppColors.ink)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
//  CLIENTES — lista com busca; toque abre o cliente; "Novo" abre o cadastro
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

// ============================================================================
//  Placeholder pras telas ainda não construídas
// ============================================================================
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