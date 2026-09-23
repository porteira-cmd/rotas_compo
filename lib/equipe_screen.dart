// ============================================================================
//  RotaCampo — Tela Equipe (só Gestor)
//  Lista o time e cadastra Vendedores e Técnicos.
//  Salve como: lib/equipe_screen.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'main.dart'; // supabase, AppColors, UserRole, supabaseUrl, supabaseAnonKey

// "Gavetinha" de memória para o cliente temporário de cadastro.
// Resolve o erro "You need to provide asyncStorage to perform pkce flow".
class _MemoriaStorage extends GotrueAsyncStorage {
  final Map<String, String> _dados = {};
  @override
  Future<String?> getItem({required String key}) async => _dados[key];
  @override
  Future<void> setItem({required String key, required String value}) async => _dados[key] = value;
  @override
  Future<void> removeItem({required String key}) async => _dados.remove(key);
}

class EquipeScreen extends StatefulWidget {
  final UserRole role;
  const EquipeScreen({super.key, required this.role});

  @override
  State<EquipeScreen> createState() => _EquipeScreenState();
}

class _EquipeScreenState extends State<EquipeScreen> {
  List<Map<String, dynamic>> _usuarios = [];
  List<Map<String, dynamic>> _operacoes = [];
  bool _carregando = true;
  String? _erro;

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
      final u = await supabase.from('usuarios').select('id, nome, email, perfil').order('nome');
      List op = [];
      try {
        op = await supabase.from('operacoes').select('id, nome').order('nome');
      } catch (_) {}
      setState(() {
        _usuarios = List<Map<String, dynamic>>.from(u);
        _operacoes = List<Map<String, dynamic>>.from(op);
        _carregando = false;
      });
    } catch (e) {
      setState(() {
        _erro = '$e';
        _carregando = false;
      });
    }
  }

  Color _corPerfil(String p) => switch (p) {
        'gestor' => AppColors.teal700,
        'tecnico' => AppColors.coral,
        _ => const Color(0xFFB8860B), // vendedor
      };
  String _nomePerfil(String p) => switch (p) {
        'gestor' => 'Gestor',
        'tecnico' => 'Técnico',
        _ => 'Vendedor',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.teal700,
        foregroundColor: Colors.white,
        title: const Text('Equipe'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.coral,
        foregroundColor: Colors.white,
        onPressed: _novoUsuario,
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Novo'),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator(color: AppColors.teal500))
          : _erro != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Erro: $_erro', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFC23A2B)))))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _usuarios.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final u = _usuarios[i];
                    final perfil = u['perfil'] as String;
                    return Container(
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.fieldBorder)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _corPerfil(perfil).withOpacity(.15),
                          child: Text((u['nome'] as String).isNotEmpty ? (u['nome'] as String)[0].toUpperCase() : '?',
                              style: TextStyle(color: _corPerfil(perfil), fontWeight: FontWeight.w700)),
                        ),
                        title: Text(u['nome'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(u['email'] ?? ''),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: _corPerfil(perfil).withOpacity(.12), borderRadius: BorderRadius.circular(999)),
                          child: Text(_nomePerfil(perfil), style: TextStyle(color: _corPerfil(perfil), fontWeight: FontWeight.w600, fontSize: 12)),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  // ---------- Cadastrar novo usuário ----------
  Future<void> _novoUsuario() async {
    final nome = TextEditingController();
    final email = TextEditingController();
    final senha = TextEditingController();
    String perfil = 'vendedor';
    String? operacaoId;
    bool salvando = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Novo membro da equipe'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nome, decoration: const InputDecoration(labelText: 'Nome')),
                const SizedBox(height: 10),
                TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'E-mail')),
                const SizedBox(height: 10),
                TextField(controller: senha, decoration: const InputDecoration(labelText: 'Senha inicial')),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: perfil,
                  decoration: const InputDecoration(labelText: 'Perfil'),
                  items: const [
                    DropdownMenuItem(value: 'vendedor', child: Text('Vendedor')),
                    DropdownMenuItem(value: 'tecnico', child: Text('Técnico')),
                    DropdownMenuItem(value: 'gestor', child: Text('Gestor')),
                  ],
                  onChanged: (v) => setD(() => perfil = v!),
                ),
                if (perfil == 'tecnico' && _operacoes.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: operacaoId,
                    decoration: const InputDecoration(labelText: 'Operação (do técnico)'),
                    items: _operacoes
                        .map((o) => DropdownMenuItem(value: o['id'] as String, child: Text(o['nome'] ?? '')))
                        .toList(),
                    onChanged: (v) => setD(() => operacaoId = v),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: salvando ? null : () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: salvando
                  ? null
                  : () async {
                      if (nome.text.trim().isEmpty || email.text.trim().isEmpty || senha.text.length < 6) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Preencha nome, e-mail e senha (mín. 6 caracteres).')),
                        );
                        return;
                      }
                      setD(() => salvando = true);
                      final ok = await _criar(nome.text.trim(), email.text.trim(), senha.text, perfil, operacaoId);
                      if (ok && ctx.mounted) Navigator.pop(ctx);
                      if (!ok) setD(() => salvando = false);
                    },
              child: salvando
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Cadastrar'),
            ),
          ],
        ),
      ),
    );
  }

  // Cria o acesso (sem derrubar o login do gestor) e grava o perfil
  Future<bool> _criar(String nome, String email, String senha, String perfil, String? operacaoId) async {
    // Cliente temporário só pra criar o acesso — não mexe na sua sessão de Gestor.
    // A gavetinha de memória evita o erro de "asyncStorage / pkce".
    final temp = SupabaseClient(
      supabaseUrl,
      supabaseAnonKey,
      authOptions: AuthClientOptions(pkceAsyncStorage: _MemoriaStorage()),
    );
    try {
      final res = await temp.auth.signUp(email: email, password: senha);
      final novoId = res.user?.id;
      if (novoId == null) throw 'Não foi possível criar o acesso.';

      // Grava o perfil na tabela (só o Gestor consegue, pelas regras RLS)
      await supabase.from('usuarios').insert({
        'id': novoId,
        'nome': nome,
        'email': email,
        'perfil': perfil,
        if (operacaoId != null) 'operacao_id': operacaoId,
        'gestor_id': supabase.auth.currentUser!.id,
      });

      await _carregar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$nome cadastrado! Passe o e-mail e a senha para a pessoa.'), backgroundColor: AppColors.teal700),
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível cadastrar: $e')),
        );
      }
      return false;
    } finally {
      await temp.dispose();
    }
  }
}