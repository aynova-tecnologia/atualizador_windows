# atualizador_windows

Atualizacao automatica dos apps Flutter da Agrosepac no Windows. O CI publica cada build numa pasta de rede, com um `versao.json`; o app confere essa pasta, baixa a versao nova, confere o hash e um script troca a pasta do programa depois que o app fecha.

- `AtualizacaoWindowsHost`: envolve o app no `MaterialApp.builder`.
- `pastaDeDadosDoApp`: pasta de dados fora da pasta do programa, separada entre teste e producao.
- `scripts/`: `atualizador.ps1` (troca), `instalar.ps1` e `instalar.cmd` (instalacao inicial em cada PC).

So age em build com `--dart-define=APP_BUILD` e `--dart-define=PASTA_ATUALIZACAO`, rodando de uma instalacao feita pelo `instalar.cmd`. Fora disso, o app abre normalmente.

A regra completa, as decisoes e o roteiro para ligar numa app estao no vault: *Atualizacao Windows - Arquitetura* e *Atualizacao Windows - Adicionar uma app*.
