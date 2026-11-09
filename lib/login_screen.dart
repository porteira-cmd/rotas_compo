// ============================================================================
//  RotaCampo — Tela de Login (Flutter)
//  Roda em Android, iOS e Web com este mesmo arquivo.
//
//  ANTES DE RODAR:
//  1) No terminal, dentro do seu projeto Flutter, adicione a fonte do Google:
//        flutter pub add google_fonts
//  2) Cole este arquivo em  lib/main.dart  (ou importe a LoginScreen onde quiser)
//  3) Rode:
//        flutter run              (no celular/emulador)
//        flutter run -d chrome    (na web)
//
//  Este exemplo usa um login "de mentira" (_fakeSignIn) só pra você VER a tela
//  funcionando. Mais pra frente você troca isso pela chamada real ao Supabase
//  — deixei o comentário exato de onde fazer isso.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

void main() => runApp(const RotaCampoApp());

// ----------------------------------------------------------------------------
//  Paleta de cores do app (as mesmas do preview: teal + coral de "pin de mapa")
// ----------------------------------------------------------------------------
class AppColors {
  static const teal900 = Color(0xFF0D2F2C);
  static const teal800 = Color(0xFF123F3A);
  static const teal700 = Color(0xFF0E6157);
  static const teal500 = Color(0xFF12897A);
  static const coral = Color(0xFFF2603C);
  static const coralDark = Color(0xFFD94B28);
  static const ink = Color(0xFF12312E);
  static const muted = Color(0xFF5F7370);
  static const field = Color(0xFFF4F7F6);
  static const fieldBorder = Color(0xFFD6E0DE);
}

// ----------------------------------------------------------------------------
//  Os 3 perfis do seu sistema (batem com a sua matriz de permissões)
// ----------------------------------------------------------------------------
enum UserRole { gestor, vendedor, tecnico }

class RotaCampoApp extends StatelessWidget {
  const RotaCampoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Porteira sem fronteiras',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFEEF2F1),
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.teal500),
        // Aplica a fonte Inter em todo o texto do app
        textTheme: GoogleFonts.interTextTheme(),
      ),
      home: const LoginScreen(),
    );
  }
}

// ============================================================================
//  TELA DE LOGIN
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

  bool _obscure = true; // senha escondida?
  bool _loading = false; // mostrando o "carregando"?

  @override
  void dispose() {
    _emailCtrl.dispose();
    _senhaCtrl.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  //  Ação do botão "Entrar"
  // --------------------------------------------------------------------------
  Future<void> _entrar() async {
    // valida os campos do formulário
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    // >>> AQUI, no futuro, entra o login REAL com o Supabase. Algo como:
    //
    //   final res = await supabase.auth.signInWithPassword(
    //     email: _emailCtrl.text.trim(),
    //     password: _senhaCtrl.text,
    //   );
    //   // depois você busca o perfil do usuário na sua tabela e decide a rota
    //
    // Por enquanto, um login de mentira só pra ver a tela funcionando:
    final role = await _fakeSignIn(_emailCtrl.text.trim());

    if (!mounted) return;
    setState(() => _loading = false);

    // Leva cada perfil pra sua própria tela (roteamento por permissão)
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => HomeScreen(role: role)),
    );
  }

  // Simula o backend: descobre o perfil pelo e-mail (só para o exemplo).
  // Ex.: gestor@..., vendedor@..., tecnico@...
  Future<UserRole> _fakeSignIn(String email) async {
    await Future.delayed(const Duration(milliseconds: 1100)); // finge a rede
    final e = email.toLowerCase();
    if (e.startsWith('gestor')) return UserRole.gestor;
    if (e.startsWith('tecnico') || e.startsWith('técnico')) return UserRole.tecnico;
    return UserRole.vendedor;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        // LayoutBuilder = decide o layout pelo tamanho da tela.
        // Tela larga (web/tablet) -> dois painéis lado a lado.
        // Tela estreita (celular) -> só o formulário, com cabeçalho compacto.
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > 820;
            if (wide) {
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Row(
                    children: [
                      const Expanded(flex: 105, child: _BrandPanel()),
                      Expanded(flex: 100, child: _buildForm(compact: false)),
                    ],
                  ),
                ),
              );
            }
            return SingleChildScrollView(child: _buildForm(compact: true));
          },
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  //  O formulário de login (reaproveitado no celular e na web)
  // --------------------------------------------------------------------------
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
              // No celular, um logo compacto no topo
              if (compact) ...[
                Row(
                  children: [
                    _logoBox(),
                    const SizedBox(width: 12),
                    Text('Porteira sem fronteiras',
                        style: GoogleFonts.archivo(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink)),
                  ],
                ),
                const SizedBox(height: 32),
              ],

              Text('Bem-vindo de volta',
                  style: const TextStyle(
                      color: AppColors.teal500,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
              const SizedBox(height: 6),
              Text('Entrar',
                  style: GoogleFonts.archivo(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                      letterSpacing: -.6)),
              const SizedBox(height: 6),
              const Text('Acesse com sua conta corporativa.',
                  style: TextStyle(color: AppColors.muted, fontSize: 14)),
              const SizedBox(height: 28),

              // Campo E-MAIL
              _label('E-mail'),
              const SizedBox(height: 7),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: _inputDeco(
                  hint: 'voce@empresa.com.br',
                  icon: Icons.mail_outline,
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  final ok = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(t);
                  return ok ? null : 'Digite um e-mail válido.';
                },
              ),
              const SizedBox(height: 16),

              // Campo SENHA (com botão de mostrar/ocultar)
              _label('Senha'),
              const SizedBox(height: 7),
              TextFormField(
                controller: _senhaCtrl,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                decoration: _inputDeco(
                  hint: 'Sua senha',
                  icon: Icons.lock_outline,
                  suffix: IconButton(
                    icon: Icon(
                        _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        color: AppColors.muted, size: 20),
                    onPressed: () => setState(() => _obscure = !_obscure),
                    tooltip: _obscure ? 'Mostrar senha' : 'Ocultar senha',
                  ),
                ),
                validator: (v) =>
                    (v ?? '').length < 4 ? 'A senha precisa de ao menos 4 caracteres.' : null,
              ),
              const SizedBox(height: 14),

              // "Esqueci a senha"
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {},
                  child: const Text('Esqueci a senha',
                      style: TextStyle(
                          color: AppColors.teal500, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 10),

              // BOTÃO ENTRAR
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _entrar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.coral,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.coral.withOpacity(.7),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white))
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Entrar',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w700)),
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward, size: 18),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 24),

              const Center(
                child: Text('Não tem conta? Peça acesso ao seu gestor.',
                    style: TextStyle(color: AppColors.muted, fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Rótulo dos campos
  Widget _label(String t) => Text(t,
      style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink));

  // Estilo padrão dos campos de texto
  InputDecoration _inputDeco(
      {required String hint, required IconData icon, Widget? suffix}) {
    OutlineInputBorder border(Color c, [double w = 1.5]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c, width: w),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.muted),
      prefixIcon: Icon(icon, color: AppColors.muted, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: AppColors.field,
      contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 14),
      enabledBorder: border(AppColors.fieldBorder),
      focusedBorder: border(AppColors.teal500, 1.8),
      errorBorder: border(const Color(0xFFC23A2B)),
      focusedErrorBorder: border(const Color(0xFFC23A2B), 1.8),
    );
  }
}

// Logo (o quadradinho coral com o pin)
Widget _logoBox() => Container(
      width: 42, height: 42,
      decoration: BoxDecoration(
        color: AppColors.coral,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.location_on, color: Colors.white, size: 22),
    );

// ============================================================================
//  PAINEL DA MARCA (aparece só na web/tablet, no lado esquerdo)
// ============================================================================
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(52),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.teal700, AppColors.teal800, AppColors.teal900],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              _logoBox(),
              const SizedBox(width: 12),
              Text('Porteira sem fronteiras',
                  style: GoogleFonts.archivo(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sua equipe,\ndo escritório à estrada.',
                  style: GoogleFonts.archivo(
                      color: Colors.white,
                      fontSize: 34,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1)),
              const SizedBox(height: 16),
              const Text(
                'Rotas, visitas e check-ins de campo em um só lugar — no celular e no navegador.',
                style: TextStyle(color: Color(0xFFBFE0DA), fontSize: 15, height: 1.6),
              ),
            ],
          ),
          Wrap(
            spacing: 10, runSpacing: 10,
            children: const [
              _RoleChip('Gestor', Color(0xFF6FE3CF)),
              _RoleChip('Vendedor', Color(0xFFFFCF6B)),
              _RoleChip('Técnico', Color(0xFFFF9D80)),
            ],
          ),
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
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(
                  color: Color(0xFFE7F5F2), fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ============================================================================
//  TELA "HOME" DE EXEMPLO — só mostra qual perfil entrou.
//  Aqui, no futuro, você mostra as telas de acordo com a matriz de permissões.
// ============================================================================
class HomeScreen extends StatelessWidget {
  final UserRole role;
  const HomeScreen({super.key, required this.role});

  String get nomePerfil => switch (role) {
        UserRole.gestor => 'Gestor',
        UserRole.vendedor => 'Vendedor',
        UserRole.tecnico => 'Técnico',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.teal700,
        foregroundColor: Colors.white,
        title: const Text('Porteira sem fronteiras'),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: AppColors.teal500, size: 56),
            const SizedBox(height: 16),
            Text('Login concluído!',
                style: GoogleFonts.archivo(
                    fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: 8),
            Text('Perfil: $nomePerfil',
                style: const TextStyle(fontSize: 16, color: AppColors.muted)),
            const SizedBox(height: 4),
            const Text('(Aqui entram as telas conforme a matriz de permissões)',
                style: TextStyle(fontSize: 13, color: AppColors.muted)),
          ],
        ),
      ),
    );
  }
}
