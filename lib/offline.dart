// ============================================================================
//  RotaCampo — Offline (fila local + sincronização)
//  Guarda cadastros e visitas quando não há internet e envia depois.
//  Pacotes: flutter pub add connectivity_plus shared_preferences
//  Salve como: lib/offline.dart
// ============================================================================

import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart'; // supabase

const String _kFila = 'rotacampo_fila_offline';

// Tem conexão de rede?
Future<bool> estaOnline() async {
  final r = await Connectivity().checkConnectivity();
  return !r.contains(ConnectivityResult.none);
}

Future<List<dynamic>> _lerFila() async {
  final p = await SharedPreferences.getInstance();
  final s = p.getString(_kFila);
  return s == null ? [] : (jsonDecode(s) as List);
}

Future<void> _gravarFila(List fila) async {
  final p = await SharedPreferences.getInstance();
  await p.setString(_kFila, jsonEncode(fila));
}

// Quantos itens estão esperando pra enviar
Future<int> pendentes() async => (await _lerFila()).length;

// Guarda um item na fila offline
Future<void> enfileirar(Map<String, dynamic> item) async {
  final fila = await _lerFila();
  fila.add(item);
  await _gravarFila(fila);
}

// Envia tudo que está na fila. Retorna quantos foram enviados.
Future<int> sincronizar() async {
  if (!await estaOnline()) return 0;
  final fila = await _lerFila();
  if (fila.isEmpty) return 0;

  final restantes = [];
  int enviados = 0;
  for (final item in fila) {
    try {
      await _enviar(Map<String, dynamic>.from(item));
      enviados++;
    } catch (_) {
      restantes.add(item); // falhou — mantém pra tentar depois
    }
  }
  await _gravarFila(restantes);
  return enviados;
}

Future<void> _enviar(Map<String, dynamic> item) async {
  if (item['tipo'] == 'cliente') {
    await supabase.from('clientes').insert(Map<String, dynamic>.from(item['dados']));
  } else if (item['tipo'] == 'visita') {
    final uid = supabase.auth.currentUser!.id;

    // Sobe as fotos (guardadas em base64) e junta as URLs
    final List<String> urls = [];
    final fotos = (item['fotos'] as List?) ?? [];
    for (var i = 0; i < fotos.length; i++) {
      final bytes = base64Decode(fotos[i] as String);
      final caminho = '$uid/${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
      await supabase.storage.from('fotos').uploadBinary(caminho, bytes);
      urls.add(supabase.storage.from('fotos').getPublicUrl(caminho));
    }

    await supabase.from('checkins').insert(Map<String, dynamic>.from(item['checkin']));

    final presc = Map<String, dynamic>.from(item['prescricao']);
    if (urls.isNotEmpty) presc['fotos'] = urls;
    await supabase.from('prescricoes').insert(presc);
  }
}
