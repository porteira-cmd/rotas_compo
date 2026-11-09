// ============================================================================
//  Porteira sem fronteiras — Tela de abertura animada (splash)
//  Mostra a logo com uma animação (surge, cresce e o nome aparece) e, ao
//  terminar, segue para o AuthGate (login ou início).
//  Salve como: lib/splash_screen.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'main.dart'; // AppColors, AuthGate

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoScale;
  late final Animation<double> _brilho; // halo pulsante atrás da logo
  late final Animation<double> _textoOpacity;
  late final Animation<Offset> _textoSlide;
  late final Animation<double> _barra;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));

    _logoOpacity = CurvedAnimation(parent: _c, curve: const Interval(0.0, 0.35, curve: Curves.easeOut));
    _logoScale = Tween(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _c, curve: const Interval(0.0, 0.55, curve: Curves.easeOutBack)),
    );
    _brilho = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _c, curve: const Interval(0.1, 0.7, curve: Curves.easeOut)),
    );
    _textoOpacity = CurvedAnimation(parent: _c, curve: const Interval(0.5, 0.85, curve: Curves.easeOut));
    _textoSlide = Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(
      CurvedAnimation(parent: _c, curve: const Interval(0.5, 0.9, curve: Curves.easeOutCubic)),
    );
    _barra = CurvedAnimation(parent: _c, curve: const Interval(0.7, 1.0, curve: Curves.easeInOut));

    _c.forward();
    _irParaApp();
  }

  Future<void> _irParaApp() async {
    await Future.delayed(const Duration(milliseconds: 2600));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, __, ___) => const AuthGate(),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.teal700, AppColors.teal800, AppColors.teal900],
          ),
        ),
        child: SafeArea(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(flex: 3),
                  // Logo com halo pulsante e animação de surgir
                  Opacity(
                    opacity: _logoOpacity.value,
                    child: Transform.scale(
                      scale: _logoScale.value,
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(32),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.teal500.withOpacity(0.35 + 0.25 * _brilho.value),
                              blurRadius: 30 + 30 * _brilho.value,
                              spreadRadius: 2 + 6 * _brilho.value,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: Image.asset(
                            'assets/logo.png',
                            width: 180,
                            height: 180,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 180,
                              height: 180,
                              color: AppColors.teal700,
                              child: const Icon(Icons.agriculture, color: Colors.white, size: 80),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  // Nome + subtítulo deslizando de baixo
                  SlideTransition(
                    position: _textoSlide,
                    child: Opacity(
                      opacity: _textoOpacity.value,
                      child: Column(
                        children: [
                          Text(
                            'Porteira sem fronteiras',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.archivo(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Grupo Porteira Agrocomercial',
                            style: GoogleFonts.inter(
                              color: Colors.white.withOpacity(0.85),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(flex: 3),
                  // Barrinha de carregamento que avança no fim
                  Opacity(
                    opacity: _textoOpacity.value,
                    child: SizedBox(
                      width: 140,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: _c.value < 0.7 ? null : _barra.value,
                          minHeight: 4,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation(Colors.white),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Opacity(
                    opacity: _textoOpacity.value * 0.8,
                    child: Text(
                      'A serviço do campo e da cidade',
                      style: GoogleFonts.inter(color: Colors.white.withOpacity(0.7), fontSize: 11, fontStyle: FontStyle.italic),
                    ),
                  ),
                  const SizedBox(height: 28),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
