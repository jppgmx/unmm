Teste do confldr.py
===================

Este diretório contém os testes unitários para `assets/confldr.py`.

Pré-requisitos
- Python 3 (recomenda-se um venv)

Como executar os testes

1) Ative o virtualenv (se existirem dependências instaladas nele):

```shell
source .venv/bin/activate
```

2) Rode os testes unitários do `confldr`:

```shell
python -m unittest tests.test_confldr -v

3) Rode os testes unitários do `unit`:

```shell
python -m unittest tests.test_unit -v
```
```

Testando o `confldr.py` manualmente

- Gerar defaults a partir de `unmm.conf`:

```shell
python3 assets/confldr.py unmm.conf > defaults
```

- Ler configuração via stdin (use `-` como fonte):

```shell
echo "[General]\nNoLogo=true\n" | python3 assets/confldr.py -
```

- Aplicar overrides via `--set` (exemplo):

```shell
python3 assets/confldr.py unmm.conf -s "Lib.Logging.Verbose=true"
```
