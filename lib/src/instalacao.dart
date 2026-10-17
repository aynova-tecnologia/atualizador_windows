import 'dart:io';

import 'package:path/path.dart' as p;

class Instalacao {
  static const marcador = '.atualizador';

  final Directory raiz;
  final String exe;

  const Instalacao({required this.raiz, required this.exe});

  static Instalacao? doExecutavel(String caminhoExe) {
    final pastaDoExe = File(caminhoExe).parent;
    if (p.basename(pastaDoExe.path).toLowerCase() != 'app') return null;
    final raiz = pastaDoExe.parent;
    if (!File(p.join(raiz.path, marcador)).existsSync()) return null;
    return Instalacao(raiz: raiz, exe: p.basename(caminhoExe));
  }

  Directory get app => Directory(p.join(raiz.path, 'app'));

  Directory get download => Directory(p.join(raiz.path, 'download'));

  File get registroDeFalha => File(p.join(raiz.path, 'falha.json'));

  File get registroPendente => File(p.join(raiz.path, 'pendente.json'));

  File get log => File(p.join(raiz.path, 'atualizador.log'));

  File get script => File(p.join(download.path, 'atualizador.ps1'));

  File scriptEmbutido() => File(
        p.join(
          app.path,
          'data',
          'flutter_assets',
          'packages',
          'atualizador_windows',
          'scripts',
          'atualizador.ps1',
        ),
      );
}
