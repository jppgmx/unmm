# Documentando Funções no UNMM

O projeto costuma adotar uma forma de documentar funções das bibliotecas (libs), definindo antes da função a seguinte estrutura base:
```sh
# funcao (stdin) <parametro_obrigatorio> [parametro_opcional][parametro_variavel...]
#  Uma descrição da função...
#  Parágrafos tem um espaço a mais na primeira linha, não recomendado criar uma linha grande, posso quebrar aqui
# e perceba que o espaço é normal aqui.
#
# Argumentos:
#   param1 - Parâmetro 1
#   param2 - Parâmetro 2
#   ...
# 
# Retorna:
#   - return: 0, 1 ou outro
#   - echo: "Um valor" ou outro
#   - exit: 1 em caso de erro fatal (quando aplicável)
#
# Erros:
#   - Condições que disparam log_error e exit 1
#
# Variaveis:
#   - UNMM_* e globais relevantes usados pela função
#
# Dependencias:
#   - Comandos externos exigidos pela função
#
# Pre-requisitos:
#   - Funções que precisam ser chamadas antes, quando aplicável
#
# Efeitos colaterais:
#   - Montagens, criação de dispositivos, escrita de arquivos, etc
#
# STDIN/STDOUT:
#   - O que a função lê do stdin e o que imprime no stdout
#
# Notas:
#   Algum comentário adicional
#
# Exemplos:
#   funcao foo bar -> algo
funcao() {

}
```
Onde:
- `(stdin)` a função suporta leitura vinda do `stdin` ou do `|`;
- `<>` é um parâmetro obrigatório;
- `[]` é um parâmetro opcional; 

## Blocos obrigatórios

- **Assinatura** e **descrição curta** na primeira linha de comentário.
- **Argumentos** quando houver parâmetros.
- **Retorna** sempre, indicando `return`, `echo` e `exit` quando usados.

## Blocos opcionais (quando aplicáveis)

- **Erros**: quando a função usa `log_error` ou `exit 1`.
- **Variaveis**: quando a função depende de `UNMM_*` ou globais.
- **Dependencias**: quando precisa de comandos externos.
- **Pre-requisitos**: quando depende de chamadas anteriores.
- **Efeitos colaterais**: quando altera estado do sistema.
- **STDIN/STDOUT**: quando lê de `stdin` ou escreve um valor no `stdout`.

## Exemplo completo

```sh
# exec_logged <contexto> <comando...>
# Executa um comando capturando e logando sua saída padrão e de erro.
#
# Argumentos:
#   contexto - Contexto do comando (para log)
#   comando... - Comando a ser executado
#
# Retorna:
#   - return: Código de saída do comando executado
#
# Variaveis:
#   - UNMM_LIB_LOGGING_VERBOSE, UNMM_LIB_LOGGING_LOG_FILE
#
# Dependencias:
#   - tee, date
#
# STDIN/STDOUT:
#   - stdout: não imprime diretamente; saída é logada
exec_logged() {

}
```