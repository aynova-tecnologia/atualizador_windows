class Manifesto {
  final String nome;
  final String versao;
  final int build;
  final String exe;
  final String zip;
  final String sha256;
  final bool obrigatoria;

  const Manifesto({
    required this.nome,
    required this.versao,
    required this.build,
    required this.exe,
    required this.zip,
    required this.sha256,
    required this.obrigatoria,
  });

  factory Manifesto.fromJson(Map<String, dynamic> json) => Manifesto(
    nome: json['nome'] as String,
    versao: json['versao'] as String,
    build: (json['build'] as num).toInt(),
    exe: json['exe'] as String,
    zip: json['zip'] as String,
    sha256: (json['sha256'] as String).toLowerCase(),
    obrigatoria: json['obrigatoria'] as bool? ?? true,
  );

  String get rotulo => '$versao+$build';
}
