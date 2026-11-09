// Implementação com ML Kit (Android/iOS). Em desktop o canal falha e
// devolve null (tratado no catch). Salve como: lib/ocr_mlkit.dart
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

Future<String?> lerTextoDaImagem(String caminho) async {
  try {
    final entrada = InputImage.fromFilePath(caminho);
    final leitor = TextRecognizer(script: TextRecognitionScript.latin);
    final resultado = await leitor.processImage(entrada);
    await leitor.close();
    final t = resultado.text.trim();
    return t.isEmpty ? null : t;
  } catch (_) {
    return null; // desktop/sem modelo: só não transcreve
  }
}
