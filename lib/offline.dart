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
    final dados = Map<String, dynamic>.from(item['dados']);
    // foto da propriedade (guardada em base64)
    final fotoB64 = item['fotoB64'] as String?;
    if (fotoB64 != null && fotoB64.isNotEmpty) {
      final uid = supabase.auth.currentUser!.id;
      final bytes = base64Decode(fotoB64);
      final caminho = '$uid/prop_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await supabase.storage.from('fotos').uploadBinary(caminho, bytes);
      dados['foto_url'] = supabase.storage.from('fotos').getPublicUrl(caminho);
    }
    final novo = await supabase.from('clientes').insert(dados).select('id').single();
    final culturas = (item['culturas'] as List?) ?? [];
    if (culturas.isNotEmpty) {
      final rows = culturas.map((c) => {...Map<String, dynamic>.from(c), 'cliente_id': novo['id']}).toList();
      await supabase.from('cliente_culturas').insert(rows);
    }
  } else if (item['tipo'] == 'justificativa') {
    await supabase.from('justificativas').insert(Map<String, dynamic>.from(item['dados']));
  } else if (item['tipo'] == 'rota_concluida') {
    await supabase.from('rotas').update({'status': item['status'] ?? 'concluida'}).eq('id', item['rota_id']);
  } else if (item['tipo'] == 'visita') {
    final uid = supabase.auth.currentUser!.id;

    // Sobe listas de fotos guardadas em base64 e devolve as URLs
    Future<List<String>> subir(String chave, String tag) async {
      final List<String> us = [];
      final lista = (item[chave] as List?) ?? [];
      for (var i = 0; i < lista.length; i++) {
        final bytes = base64Decode(lista[i] as String);
        final caminho = '$uid/${tag}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
        await supabase.storage.from('fotos').uploadBinary(caminho, bytes);
        us.add(supabase.storage.from('fotos').getPublicUrl(caminho));
      }
      return us;
    }

    // Sobe listas de pragas/doenças: [{nome, fotosB64:[...]}] -> [{nome, fotos:[urls]}]
    Future<List<Map<String, dynamic>>> subirAlvos(String chave, String tag) async {
      final out = <Map<String, dynamic>>[];
      for (final a in (item[chave] as List?) ?? []) {
        final us = <String>[];
        final b64s = (a['fotosB64'] as List?) ?? [];
        for (var i = 0; i < b64s.length; i++) {
          final bytes = base64Decode(b64s[i] as String);
          final caminho = '$uid/${tag}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
          await supabase.storage.from('fotos').uploadBinary(caminho, bytes);
          us.add(supabase.storage.from('fotos').getPublicUrl(caminho));
        }
        out.add({'nome': a['nome'], 'fotos': us});
      }
      return out;
    }

    final urls = await subir('fotos', 'prob');
    final pragasOut = await subirAlvos('pragas', 'praga');
    final doencasOut = await subirAlvos('doencas', 'doenca');

    await supabase.from('checkins').insert(Map<String, dynamic>.from(item['checkin']));

    final presc = Map<String, dynamic>.from(item['prescricao']);
    if (urls.isNotEmpty) presc['fotos'] = urls;
    presc['pragas'] = pragasOut;
    presc['doencas'] = doencasOut;
    final pf = pragasOut.expand((e) => (e['fotos'] as List)).toList();
    final df = doencasOut.expand((e) => (e['fotos'] as List)).toList();
    if (pf.isNotEmpty) presc['praga_fotos'] = pf;
    if (df.isNotEmpty) presc['doenca_fotos'] = df;
    await supabase.from('prescricoes').insert(presc);

    // atualiza a localização do cliente (GPS pego no check-in)
    final local = item['local'];
    if (local != null) {
      try {
        await supabase.rpc('atualizar_local_cliente', params: {'p_id': local['id'], 'p_lat': local['lat'], 'p_lng': local['lng']});
      } catch (_) {}
    }
  }
}