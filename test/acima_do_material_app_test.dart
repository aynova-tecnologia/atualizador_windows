import 'dart:io';

import 'package:atualizador_windows/atualizador_windows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Falso extends AtualizadorWindows {
  int downloads = 0;
  Manifesto? reiniciouCom;
  _Falso()
      : super(
          configuracao: const ConfiguracaoAtualizacao(
            buildAtual: 4,
            pastaPublicacao: 'rede',
            instalacao: null,
          ),
        );
  @override
  bool get ativo => true;
  @override
  Future<Manifesto?> versaoNova() async => const Manifesto(
        nome: 'X',
        versao: '1.0.0',
        build: 5,
        exe: 'x.exe',
        zip: 'x.zip',
        sha256: 'a',
        obrigatoria: true,
      );
  @override
  bool jaFalhouCom(Manifesto manifesto) => false;
  @override
  bool scriptNaoRodouPara(Manifesto manifesto) => false;
  @override
  Future<File> baixar(Manifesto manifesto,
      {void Function(double fracao)? progresso}) async {
    downloads++;
    return File('zip');
  }

  @override
  Future<void> trocarEReiniciar(Manifesto manifesto, File zip) async =>
      reiniciouCom = manifesto;
}

void main() {
  testWidgets(
      'funciona acima do MaterialApp (app da msk_lib), so com Directionality e Theme, e o falso nao precisa sobrescrever esquecerFalha',
      (tester) async {
    final a = _Falso();
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Theme(
        data: ThemeData(),
        child: AtualizacaoWindowsHost(
          atualizador: a,
          child: const MaterialApp(home: Scaffold(body: Text('app'))),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('Atualização obrigatória'), findsOneWidget);
    await tester.tap(find.text('Atualizar'));
    await tester.pump();
    await tester.pump();
    expect(a.downloads, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
