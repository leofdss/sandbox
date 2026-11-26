# OpenCode V2 e agentes

## Uso diário

```bash
./sandbox ai
```

Isso executa `opencode --standalone /workspace`, evitando o serviço compartilhado em segundo plano. Na primeira sessão:

1. execute `/connect`;
2. escolha o provedor;
3. conclua a autenticação;
4. revise as permissões antes de aprovar comandos.

Para automação não interativa:

```bash
./sandbox run "Explique a arquitetura e aponte riscos sem editar arquivos"
```

Não acrescente `--auto` ao fluxo padrão. Regras `deny` continuam válidas com autoaprovação, mas pedidos `ask` deixam de oferecer a mesma revisão humana.

## Arquivos de instrução

No diretório `blackbox/` do repositório:

- `AGENTS.md`: arquitetura, comandos, convenções e limites obrigatórios.
- `docs/OPENCODE.md` e `docs/SECURITY.md`: instruções complementares.
- `config/opencode/opencode.jsonc`: configuração V2 gerenciada e regras de confirmação.
- `.opencode/agents/*.md`: agentes especializados com frontmatter V2.
- `.opencode/commands/verify.md`: slash command `/verify`.

Durante o build, esses arquivos são instalados em `/etc/opencode` na imagem. Assim, ficam disponíveis em qualquer projeto montado em `/workspace` (por padrão, a pasta `sandbox/` do repositório) sem montar o `blackbox` no container. Se um projeto tiver seu próprio `AGENTS.md` ou `opencode.jsonc`, ele será combinado com as regras gerenciadas, que têm precedência maior.

Versionar o `AGENTS.md` do ambiente permite que todas as pessoas e agentes recebam a mesma orientação. Alterações nesses arquivos entram em novos builds da imagem; não são montadas dinamicamente a partir do host.

## Agentes incluídos

### `reviewer`

Use após uma mudança:

```text
Use o subagente reviewer para revisar o diff atual. Procure regressões e testes ausentes; não edite nada.
```

Ele começa com deny-all e pode ler arquivos permitidos e consultar `git status`; buscas e diffs pedem confirmação porque seu conteúdo pode incluir segredos.

### `security-reviewer`

Use para Containerfile, Compose, mounts, rede ou permissões:

```text
Use o subagente security-reviewer para revisar os mounts e privilégios atuais, incluindo riscos residuais.
```

Ele não edita, não instala e não deve acessar segredos. As conclusões precisam incluir arquivo/linha e caminho de abuso, evitando alarmismo sobre exceções já documentadas.

### `/verify`

O comando orienta validação de shell, Compose, build, Podman aninhado e GUI quando disponível. Builds e downloads continuam sujeitos a confirmação.

## Formato V2

Este repositório usa deliberadamente os campos atuais:

```yaml
---
description: Revisor sem alterações
mode: subagent
permissions:
  - action: edit
    resource: "*"
    effect: deny
---
```

Não misture os campos V1 `permission`, `bash` e `task`. Em V2, use `permissions`, `shell` e `subagent`. As regras são avaliadas em ordem e a última correspondência vence; por isso regras amplas aparecem antes das exceções.

As configurações do sistema, globais e do projeto se combinam. Policies gerenciadas têm precedência maior que regras do projeto. Ainda assim, não trate texto de prompt como barreira contra um processo comprometido.

## Credenciais

A autenticação fica no volume `opencode-data`, não no repositório. Não use:

```bash
# Evite exportar segredos do host para o container:
# ANTHROPIC_API_KEY=... ./sandbox ai
# OPENAI_API_KEY=... ./sandbox ai
```

Se um provedor corporativo exigir variável de ambiente, crie um mecanismo de injeção de curta duração fora do Git e revise seus riscos. Não monte arquivos de credenciais pessoais por conveniência.

## Personalização segura

- Adicione regras específicas depois da regra ampla e teste a precedência.
- Prefira `ask` para shell e ferramentas externas.
- Não permita edição silenciosa das próprias políticas sem revisão.
- Mantenha agentes de revisão sem escrita.
- Não configure MCP/plugins de origem desconhecida: eles executam código e ampliam a superfície.
- Atualizações do binário são feitas no Containerfile, não com auto-update dentro do volume.
- Para migrar definições antigas, consulte o guia oficial V1→V2 antes de alterar os arquivos.

Fontes: [instruções](https://opencode.ai/docs/rules), [agentes](https://opencode.ai/docs/agents), [permissões](https://opencode.ai/docs/permissions), [configuração](https://opencode.ai/docs/config) e [CLI](https://opencode.ai/docs/cli).
