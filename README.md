# Blackbox AI Sandbox

Repositório completo para recriar um ambiente de desenvolvimento com **OpenCode V2, Git, Podman e podman-compose**, sem montar o socket do Podman do host e sem `--privileged`.

Nenhum caminho deste guia depende do computador onde o repositório foi criado. Todos os comandos são relativos à **raiz do repositório** (a pasta que contém este `README.md` e o `sandbox.sh`), qualquer que seja o local do clone.

## Estrutura do repositório

```text
<raiz-do-repositório>/
├── README.md             # este guia (comece por aqui)
├── sandbox.sh            # atalho: repassa os comandos para blackbox/sandbox
├── blackbox/             # AMBIENTE: imagem, Compose, scripts e documentação técnica
│   ├── README.md         # guia técnico completo
│   ├── AGENTS.md         # regras obrigatórias para agentes de IA
│   ├── sandbox           # script real com todos os comandos
│   ├── Containerfile     # definição da imagem
│   ├── compose*.yaml     # perfil padrão e perfis opcionais (GUI, áudio, GPU, portas)
│   ├── scripts/          # entrypoint, healthcheck e testes (copiados para a imagem)
│   ├── config/           # configuração do OpenCode, Git e Bash (copiados para a imagem)
│   ├── .opencode/        # agentes e comandos do OpenCode (copiados para a imagem)
│   └── docs/             # arquitetura, segurança, GUI, OpenCode e fontes
└── sandbox/              # PROJETOS DO USUÁRIO (vira /workspace dentro do container)
    └── README.md
```

Regras de separação:

- `sandbox/` é montado como `/workspace` dentro do container. Somente `sandbox/README.md` é versionado; os projetos colocados ali são ignorados por este repositório.
- `blackbox/` **não** é montado no container. Ele só é lido no host durante o `build`.

## Pré-requisitos

- Linux ou WSL2;
- Podman rootless e `podman-compose`;
- `/dev/fuse`, user namespaces e subordinate UIDs/GIDs;
- Bash.

Comandos de instalação por distribuição estão em [blackbox/README.md](blackbox/README.md#pré-requisitos-do-host).

## Início rápido

```bash
git clone <URL-DESTE-REPOSITORIO> sandbox
cd sandbox                # raiz do repositório
./sandbox.sh doctor       # confere os pré-requisitos do host
./sandbox.sh build        # constrói a imagem
./sandbox.sh verify       # testa ferramentas e Podman aninhado
./sandbox.sh ai           # abre o OpenCode
```

No primeiro uso do OpenCode, execute `/connect` para autenticar um provedor. Nenhuma credencial do host é copiada automaticamente.

### `./sandbox.sh` ou `./sandbox`?

São o mesmo comando, chamados de pastas diferentes:

| Onde você está | Comando |
|---|---|
| Raiz do repositório | `./sandbox.sh <comando>` |
| Pasta `blackbox/` | `./sandbox <comando>` |

A documentação dentro de `blackbox/` usa a forma `./sandbox`; na raiz, troque por `./sandbox.sh`.

## Baixar projetos

Execute a partir da raiz do repositório:

```bash
git -C sandbox clone <URL-DO-PROJETO>
./sandbox.sh ai
```

Para expor somente um projeto, passe um caminho **absoluto** (caminhos relativos são resolvidos a partir de `blackbox/`, não da pasta atual):

```bash
WORKSPACE_DIR="$PWD/sandbox/meu-app" ./sandbox.sh ai
```

## Comandos frequentes

| Comando | Função |
|---|---|
| `./sandbox.sh build` | Constrói a imagem. |
| `./sandbox.sh verify` | Testa ferramentas e Podman aninhado. |
| `./sandbox.sh gui-verify` | Testa containers, Wayland e áudio. |
| `./sandbox.sh shell` | Abre shell headless. |
| `./sandbox.sh gui` | Abre shell com Wayland e áudio detectado. |
| `./sandbox.sh status` | Mostra o estado do serviço. |
| `./sandbox.sh down` | Remove o container e preserva os volumes. |

Todas as demais opções estão em `./sandbox.sh help`.

## Replicar em outra máquina

1. Instale os pré-requisitos do host.
2. Clone este repositório em qualquer pasta.
3. Na raiz do clone, execute `./sandbox.sh build` e `./sandbox.sh verify`.
4. Baixe seus projetos somente dentro de `sandbox/`.

As imagens são recriadas pelo `blackbox/Containerfile`. Credenciais, sessões do OpenCode e armazenamento aninhado ficam em volumes do Podman e **não acompanham o clone**; faça backup separado se precisar migrá-los.

## Guia para agentes de IA

Se você é um agente lendo este repositório, siga esta ordem:

1. **Leia `blackbox/AGENTS.md` antes de qualquer alteração.** Ele contém os limites de segurança e as convenções obrigatórias.
2. Para entender o funcionamento, leia `blackbox/README.md` e depois `blackbox/docs/ARCHITECTURE.md`.
3. Antes de mexer em privilégios, mounts ou rede, leia `blackbox/docs/SECURITY.md`.
4. Consulte o arquivo certo para cada assunto:

| Assunto | Arquivo |
|---|---|
| Lista de comandos e variáveis | `blackbox/sandbox` (função `usage`) ou `./sandbox.sh help` |
| Imagem e pacotes instalados | `blackbox/Containerfile` |
| Container, mounts e volumes | `blackbox/compose.yaml` |
| GUI, áudio, GPU e portas | `blackbox/compose.<perfil>.yaml` e `blackbox/docs/GUI.md` |
| Testes do ambiente | `blackbox/scripts/verify.sh` |
| Permissões do OpenCode | `blackbox/config/opencode/opencode.jsonc` e `blackbox/docs/OPENCODE.md` |
| Agentes revisores | `blackbox/.opencode/agents/` |
| Valores padrão opcionais | `blackbox/.env.example` (copie para `blackbox/.env`) |

Fatos importantes:

- Caminhos nos documentos são relativos à raiz do repositório ou a `blackbox/`, conforme indicado. Não presuma um caminho absoluto específico.
- Dentro do container, só existe `/workspace` (conteúdo de `sandbox/`). `blackbox/` não está acessível; as instruções do agente estão em `/etc/opencode`.
- Mudanças em `blackbox/` só valem dentro do container após `./sandbox.sh build`.
- Commits seguem [Conventional Commits](https://www.conventionalcommits.org/pt-br/v1.0.0/) (ex.: `docs(cli): explicar WORKSPACE_DIR absoluto`). Tipos, escopos e regras estão em `blackbox/AGENTS.md`, seção "Mensagens de commit".

## Documentação

- [Guia técnico do Blackbox](blackbox/README.md)
- [Instruções para agentes](blackbox/AGENTS.md)
- [Arquitetura](blackbox/docs/ARCHITECTURE.md)
- [Segurança e limites](blackbox/docs/SECURITY.md)
- [Wayland, PipeWire e WSLg](blackbox/docs/GUI.md)
- [OpenCode e agentes](blackbox/docs/OPENCODE.md)
- [Fontes pesquisadas](blackbox/docs/SOURCES.md)
- [Orientações do espaço de trabalho](sandbox/README.md)
