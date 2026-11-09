// ============================================================================
//  RotaCampo — Sobre o app
//  Tela institucional: logo, versão, empresa e créditos.
//  Salve como: lib/sobre_screen.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'main.dart'; // AppColors

const String kAppVersao = '1.0.0';

class SobreScreen extends StatelessWidget {
  const SobreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.teal700, foregroundColor: Colors.white, title: const Text('Sobre o app')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Cabeçalho com logo
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.teal700, AppColors.teal800, AppColors.teal900]),
            ),
            child: Column(children: [
              Container(
                width: 90,
                height: 90,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                padding: const EdgeInsets.all(4),
                child: ClipOval(
                  child: Image.asset(
                    'assets/logo.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      decoration: const BoxDecoration(color: AppColors.coral, shape: BoxShape.circle),
                      child: const Icon(Icons.agriculture, color: Colors.white, size: 44),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text('Porteira sem fronteiras', style: GoogleFonts.archivo(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Grupo Porteira Agrocomercial', style: TextStyle(color: Colors.white.withOpacity(.9), fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('Versão $kAppVersao', style: TextStyle(color: Colors.white.withOpacity(.7), fontSize: 12)),
            ]),
          ),
          const SizedBox(height: 20),

          _bloco('O que é', 'Aplicativo de gestão de equipe de campo: cadastro de clientes, mapa, rotas, check-ins, prescrições e relatórios — para gestores, vendedores e técnicos.'),
          _bloco('Empresa', 'Porteira Agrocomercial — produtos agrícolas e materiais para construção em geral. A serviço do campo e da cidade.'),
          _bloco('Tecnologia', 'Feito em Flutter (Android, iOS e Web), com banco de dados Supabase e mapas OpenStreetMap.'),

          const SizedBox(height: 8),
          Center(child: Text('© ${DateTime.now().year} Porteira Agrocomercial', style: const TextStyle(color: AppColors.muted, fontSize: 12))),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _bloco(String titulo, String texto) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.fieldBorder)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titulo, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink, fontSize: 15)),
          const SizedBox(height: 6),
          Text(texto, style: const TextStyle(color: AppColors.muted, height: 1.5)),
        ]),
      );
}