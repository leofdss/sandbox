# Espaço de trabalho do usuário

Esta pasta é reservada para **seus projetos e arquivos de trabalho**. Não coloque aqui arquivos da infraestrutura do Blackbox.

- **No host:** `sandbox/`, na raiz do repositório
- **Dentro do container:** `/workspace`
- **Ambiente e ferramentas:** `blackbox/`, na raiz do repositório (não montado no container)

## Baixar um projeto

A partir da raiz do repositório:

```bash
git -C sandbox clone <URL-DO-PROJETO>
./sandbox.sh ai
```

Todos os projetos desta pasta aparecem em `/workspace` no container. Para expor somente um projeto por vez, use um caminho absoluto:

```bash
WORKSPACE_DIR="$PWD/sandbox/meu-app" ./sandbox.sh ai
```

Evite guardar senhas, chaves privadas, tokens e outros segredos nos projetos. As credenciais do OpenCode ficam em volumes separados, fora desta pasta.
