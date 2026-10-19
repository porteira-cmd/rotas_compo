// ============================================================================
//  RotaCampo — Avisar clientes da rota (WhatsApp)
//  Abre a lista dos clientes da rota com a mensagem pronta; você envia
//  tocando em cada um, e o app marca quem já foi avisado.
//  Salve como: lib/avisar_clientes.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'main.dart'; // AppColors
import 'acoes.dart'; // abrirWhatsApp, mensagemVisita

Future<void> mostrarAvisarClientes(BuildContext context, List<Map<String, dynamic>> clientes) async {
  final Set<dynamic> enviados = {};

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        final semTel = clientes.where((c) => (c['telefone'] as String?)?.trim().isNotEmpty != true).length;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.72),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Text('Avisar clientes da rota', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    'Toque em cada cliente pra abrir o WhatsApp com a mensagem pronta.${semTel > 0 ? ' ($semTel sem telefone)' : ''}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: clientes.length,
                    itemBuilder: (_, i) {
                      final c = clientes[i];
                      final tel = (c['telefone'] as String?)?.trim() ?? '';
                      final temTel = tel.isNotEmpty;
                      final enviado = enviados.contains(c['id']);
                      return ListTile(
                        leading: Icon(
                          enviado ? Icons.check_circle : Icons.chat,
                          color: enviado ? const Color(0xFF2E7D5B) : (temTel ? const Color(0xFF128C7E) : AppColors.muted),
                        ),
                        title: Text(c['nome'] ?? 'Cliente', style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(temTel ? tel : 'Sem telefone', style: TextStyle(color: temTel ? AppColors.muted : const Color(0xFFC23A2B))),
                        trailing: temTel
                            ? FilledButton(
                                onPressed: () async {
                                  await abrirWhatsApp(tel, mensagemVisita(c['nome'] ?? 'cliente'));
                                  setSheet(() => enviados.add(c['id']));
                                },
                                style: FilledButton.styleFrom(backgroundColor: enviado ? AppColors.muted : const Color(0xFF128C7E)),
                                child: Text(enviado ? 'Reenviar' : 'Enviar'),
                              )
                            : null,
                        onTap: temTel
                            ? () async {
                                await abrirWhatsApp(tel, mensagemVisita(c['nome'] ?? 'cliente'));
                                setSheet(() => enviados.add(c['id']));
                              }
                            : null,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    ),
  );
}
