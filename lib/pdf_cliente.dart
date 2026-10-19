// ============================================================================
//  RotaCampo — Gerar PDF do histórico do cliente (com fotos)
//  Pacotes: flutter pub add pdf printing
//  Salve como: lib/pdf_cliente.dart
// ============================================================================

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'visitas_screen.dart' show formatarData;

Future<void> gerarPdfCliente(Map<String, dynamic> cliente, List<Map<String, dynamic>> eventos) async {
  final doc = pw.Document();

  // 1) Baixa as imagens antes (não dá pra fazer isso dentro do build do PDF)
  final Map<String, pw.ImageProvider> imgs = {};
  for (final e in eventos) {
    for (final u in ((e['fotos'] as List?) ?? [])) {
      final url = u as String;
      if (imgs.containsKey(url)) continue;
      try {
        imgs[url] = await networkImage(url);
      } catch (_) {
        // foto quebrada — ignora
      }
    }
  }

  // 2) Monta o documento (MultiPage quebra em várias páginas sozinho)
  doc.addPage(
    pw.MultiPage(
      margin: const pw.EdgeInsets.all(28),
      build: (ctx) => [
        pw.Text('Histórico do cliente', style: pw.TextStyle(fontSize: 12, color: PdfColors.grey600)),
        pw.SizedBox(height: 2),
        pw.Text(cliente['nome'] ?? 'Cliente', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 10),
        pw.Text('Município: ${cliente['municipio'] ?? '-'}'),
        pw.Text('Telefone: ${cliente['telefone'] ?? '-'}'),
        pw.Text('Endereço: ${cliente['endereco'] ?? '-'}'),
        pw.Divider(height: 24),
        pw.Text('Linha do tempo', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        if (eventos.isEmpty)
          pw.Text('Nenhuma visita ou prescrição registrada.', style: const pw.TextStyle(color: PdfColors.grey600))
        else
          ...eventos.map((e) {
            final visita = e['tipo'] == 'visita';
            final fotos = ((e['fotos'] as List?) ?? []).where((u) => imgs.containsKey(u)).toList();
            return pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 12),
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(visita ? 'Visita' : 'Prescrição', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: visita ? PdfColors.green800 : PdfColors.teal800)),
                      pw.Text(formatarData(e['quando']), style: const pw.TextStyle(color: PdfColors.grey600, fontSize: 10)),
                    ],
                  ),
                  if ((e['texto'] as String).isNotEmpty) ...[
                    pw.SizedBox(height: 4),
                    pw.Text(e['texto']),
                  ],
                  if ((e['recomendacoes'] as List?)?.isNotEmpty == true) ...[
                    pw.SizedBox(height: 4),
                    ...(e['recomendacoes'] as List).map((r) => pw.Bullet(
                          text: '${r['produto']}${(r['dosagem'] ?? '').toString().isNotEmpty ? ' — ${r['dosagem']}' : ''}',
                          style: const pw.TextStyle(fontSize: 11),
                        )),
                  ],
                  if (fotos.isNotEmpty) ...[
                    pw.SizedBox(height: 8),
                    pw.Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: fotos.map<pw.Widget>((u) => pw.ClipRRect(
                        horizontalRadius: 4, verticalRadius: 4,
                        child: pw.Image(imgs[u]!, width: 130, height: 130, fit: pw.BoxFit.cover),
                      )).toList(),
                    ),
                  ],
                ],
              ),
            );
          }),
        pw.SizedBox(height: 20),
        pw.Text('Gerado pelo RotaCampo', style: const pw.TextStyle(color: PdfColors.grey500, fontSize: 9)),
      ],
    ),
  );

  // 3) Abre a tela de compartilhar/salvar/imprimir
  final nome = (cliente['nome'] ?? 'cliente').toString().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
  await Printing.sharePdf(bytes: await doc.save(), filename: 'historico_$nome.pdf');
}