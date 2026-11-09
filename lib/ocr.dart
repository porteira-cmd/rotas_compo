// ============================================================================
//  Porteira sem fronteiras — OCR (ler texto de uma foto)
//  Usa ML Kit no celular (Android/iOS). Em Windows/web cai no stub e
//  devolve null (não transcreve, mas NÃO quebra o build).
//  Salve como: lib/ocr.dart  (junto com ocr_stub.dart e ocr_mlkit.dart)
// ============================================================================

import 'ocr_stub.dart' if (dart.library.io) 'ocr_mlkit.dart' as impl;

/// Lê o texto de uma imagem (caminho do arquivo). Devolve null se não der.
Future<String?> lerTextoDaImagem(String caminho) => impl.lerTextoDaImagem(caminho);
