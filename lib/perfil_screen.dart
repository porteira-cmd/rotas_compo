  // ============================================================================
//  RotaCampo — Meu perfil (foto, nome e senha)
//  Precisa: image_picker  •  bucket "fotos" no Storage  •  perfil.sql rodado
//  Salve como: lib/perfil_screen.dart
// ============================================================================

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'main.dart'; // supabase, AppColors, perfilFromText, nomeDoPerfil

class PerfilScreen extends StatefulWidget {
  const PerfilScreen({super.key});
  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen> {
  final _nome = TextEditingController();
  String _email = '';
  String _perfil = '';
  String? _fotoUrl; // foto já salva
  Uint8List? _novaFoto; // foto escolhida, ainda não salva
  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final uid = supabase.auth.currentUser!.id;
      final u = await supabase.from('usuarios').select('nome, email, perfil, foto_url').eq('id', uid).single();
      setState(() {
        _nome.text = u['nome'] ?? '';
        _email = u['email'] ?? '';
        _perfil = u['perfil'] ?? '';
        _fotoUrl = u['foto_url'];
        _carregando = false;
      });
    } catch (e) {
      setState(() => _carregando = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao carregar: $e')));
    }
  }

  Future<void> _escolherFoto(ImageSource origem) async {
    final x = await ImagePicker().pickImage(source: origem, imageQuality: 60, maxWidth: 600);
    if (x != null) {
      final b = await x.readAsBytes();
      setState(() => _novaFoto = b);
    }
  }

  void _menuFoto() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Tirar foto'), onTap: () { Navigator.pop(context); _escolherFoto(ImageSource.camera); }),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Escolher da galeria'), onTap: () { Navigator.pop(context); _escolherFoto(ImageSource.gallery); }),
        ]),
      ),
    );
  }

  Future<void> _salvar() async {
    setState(() => _salvando = true);
    try {
      final uid = supabase.auth.currentUser!.id;
      String? novaUrl;
      if (_novaFoto != null) {
        final path = 'avatars/${uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await supabase.storage.from('fotos').uploadBinary(path, _novaFoto!);
        novaUrl = supabase.storage.from('fotos').getPublicUrl(path);
      }
      await supabase.rpc('atualizar_meu_perfil', params: {'p_nome': _nome.text.trim(), 'p_foto': novaUrl});
      await _carregar();
      setState(() => _novaFoto = null);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Perfil atualizado!'), backgroundColor: AppColors.teal700));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível salvar: $e')));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _trocarSenha() async {
    final senha = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Trocar senha'),
        content: TextField(controller: senha, obscureText: true, decoration: const InputDecoration(labelText: 'Nova senha (mín. 6)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
        ],
      ),
    );
    if (ok != true || senha.text.length < 6) {
      if (ok == true && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A senha precisa de ao menos 6 caracteres.')));
      return;
    }
    try {
      await supabase.auth.updateUser(UserAttributes(password: senha.text));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Senha alterada!'), backgroundColor: AppColors.teal700));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao trocar senha: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.teal700, foregroundColor: Colors.white, title: const Text('Meu perfil')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator(color: AppColors.teal500))
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Center(
                  child: Stack(children: [
                    CircleAvatar(
                      radius: 56,
                      backgroundColor: AppColors.teal500.withOpacity(.15),
                      backgroundImage: _novaFoto != null
                          ? MemoryImage(_novaFoto!)
                          : (_fotoUrl != null && _fotoUrl!.isNotEmpty ? NetworkImage(_fotoUrl!) : null) as ImageProvider?,
                      child: (_novaFoto == null && (_fotoUrl == null || _fotoUrl!.isEmpty))
                          ? Text(_nome.text.isNotEmpty ? _nome.text[0].toUpperCase() : '?', style: const TextStyle(fontSize: 40, color: AppColors.teal700, fontWeight: FontWeight.w700))
                          : null,
                    ),
                    Positioned(
                      right: 0, bottom: 0,
                      child: Material(
                        color: AppColors.coral,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _menuFoto,
                          child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.camera_alt, color: Colors.white, size: 20)),
                        ),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 24),
                TextField(controller: _nome, decoration: const InputDecoration(labelText: 'Nome', prefixIcon: Icon(Icons.person_outline), border: OutlineInputBorder())),
                const SizedBox(height: 14),
                TextField(enabled: false, controller: TextEditingController(text: _email), decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.mail_outline), border: OutlineInputBorder())),
                const SizedBox(height: 14),
                TextField(enabled: false, controller: TextEditingController(text: nomeDoPerfil(perfilFromText(_perfil))), decoration: const InputDecoration(labelText: 'Perfil', prefixIcon: Icon(Icons.badge_outlined), border: OutlineInputBorder())),
                const SizedBox(height: 24),
                SizedBox(
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: _salvando ? null : _salvar,
                    icon: _salvando ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_outlined),
                    label: const Text('Salvar perfil'),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.coral),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: _trocarSenha,
                    icon: const Icon(Icons.lock_outline, size: 18),
                    label: const Text('Trocar senha'),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.teal700, side: const BorderSide(color: AppColors.teal500)),
                  ),
                ),
              ],
            ),
    );
  }
}
