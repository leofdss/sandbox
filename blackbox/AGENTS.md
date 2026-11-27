# Instruções para agentes — Sandbox AI

## Objetivo

O repositório (clonado em qualquer pasta do host; aqui chamada de `<raiz>`) contém o ambiente em `<raiz>/blackbox/` e o espaço do usuário em `<raiz>/sandbox/`. Não presuma um caminho absoluto fixo no host. O diretório `blackbox/` constrói um ambiente de desenvolvimento reproduzível com OpenCode V2, Git, Podman e podman-compose. O container externo é rootless e o Podman interno usa armazenamento próprio. Wayland, áudio e GPU são perfis opcionais.

A separação é obrigatória: o ambiente fica em `<raiz>/blackbox/`; os projetos do usuário ficam em `<raiz>/sandbox/`, montados como `/workspace` no container. O `blackbox` não é montado por padrão. Estas instruções e os agentes gerenciados são copiados para `/etc/opencode` na imagem e se aplicam a qualquer projeto do usuário.

**Onde você está?** Se o diretório atual é `/workspace` e existe `/etc/opencode`, você está **dentro do container**: só os projetos do usuário estão visíveis, `blackbox/` não existe e alterações no ambiente não podem ser feitas daqui. Caso contrário, você está no host, com acesso ao repositório completo.

## Comandos úteis

Execute no host, a partir de `<raiz>/blackbox/` (ou use `./sandbox.sh <comando>` a partir de `<raiz>/`):

```bash
./sandbox doctor
./sandbox build
./sandbox verify
./sandbox shell
./sandbox ai
./sandbox gui
./sandbox gui-verify
./sandbox down
```

Dentro do container:

```bash
sandbox-verify
distrobox list
podman info
podman-compose --version
opencode --version
git status --short
```

Use `VERIFY_PULL=0 sandbox-verify` para verificações sem baixar a imagem BusyBox de teste.

## Limites de segurança

- Não montar `/run/user/*/podman/podman.sock`, `/var/run/docker.sock`, o `HOME` completo, chaves SSH ou sockets de agentes do host.
- Não adicionar `privileged: true`, `network_mode: host`, `cap_add: SYS_ADMIN`, `security_opt: seccomp=unconfined` ou `user: "0"` como solução de problema.
- Não ligar o serviço `dev` a uma rede com saída nem remover `HTTP(S)_PROXY` para contornar o proxy de egress. Se um destino necessário for negado, informar o usuário e propor a linha para `config/egress/allowlist.txt`.
- Não usar `no-new-privileges` no container externo sem investigar: `newuidmap` e `newgidmap` são necessários para o rootless aninhado.
- `/dev/fuse` e `label=disable` são exceções deliberadas para o Podman aninhado. Explicar qualquer alteração em `docs/SECURITY.md`.
- Não montar todo o `XDG_RUNTIME_DIR`. Expor somente os sockets necessários.
- PipeWire/PulseAudio pode conceder acesso a microfone e outras fontes de mídia; não ativá-lo no perfil headless.
- GPU, X11 e WSLg são opt-in. Preferir Wayland a X11.
- Não incluir tokens, cookies, chaves de provedores ou credenciais em arquivos versionados, `Containerfile`, Compose, logs ou prompts.
- O repositório é **público**. Não usar `git commit --no-verify`, não desativar `core.hooksPath` e não remover regras de `.githooks/pre-commit`, `.gitignore` ou `.github/workflows/secret-scan.yml` para fazer um commit passar. Se o hook bloquear, parar e informar o usuário; usar `gitleaks:allow` somente para falso positivo confirmado pelo usuário.
- Não executar `git push`, `sudo`, `doas`, `podman system reset` ou `down -v` sem decisão explícita do usuário. O `reset` também apaga o armazenamento aninhado.
- Não desativar confirmações do OpenCode nem recomendar `--auto` como configuração padrão.

## Convenções do repositório

- Documentação e instruções em português do Brasil; identificadores e comandos em inglês.
- YAML e JSONC com dois espaços; shell com quatro espaços e `set -euo pipefail`.
- Manter compatibilidade com OpenCode V2: usar `permissions`, `shell`, `subagent` e frontmatter V2, não os campos V1 `permission`, `bash` ou `task`.
- Fixar versões e checksums do OpenCode e do starship e o digest multi-arquitetura da imagem base. Não introduzir `latest`.
- O shell interativo é fish + starship (`config/sandbox.fish`); scripts continuam em Bash. Não remover o shim do distrobox (`scripts/distrobox-podman.sh`) nem contorná-lo liberando seccomp, `SYS_ADMIN` ou cgroups no container externo.
- Não executar scripts de instalação remotos diretamente no shell. Downloads devem usar HTTPS e verificação SHA-256.
- Preservar o nome do serviço `dev` e os caminhos internos `/workspace`, `/home/podman` e `/run/user/1000`, salvo mudança coordenada em todos os arquivos.
- Não colocar código do ambiente em `<raiz>/sandbox/` nem projetos do usuário em `<raiz>/blackbox/`. Alterações no ambiente são feitas no host e entram no container por novo build.
- Manter o perfil padrão sem portas publicadas e sem acesso a GUI, áudio ou GPU.
- Atualizar `README.md`, `docs/` e `AGENTS.md` quando comandos ou arquitetura mudarem.

## Mensagens de commit

Usar [Conventional Commits](https://www.conventionalcommits.org/pt-br/v1.0.0/):

```text
<tipo>(<escopo opcional>): <descrição>

<corpo opcional: o que mudou e por quê>

<rodapé opcional: BREAKING CHANGE: ..., Refs: #123>
```

- `tipo` em inglês e minúsculo: `feat` (funcionalidade), `fix` (correção), `docs` (somente documentação), `refactor` (sem mudar comportamento), `test`, `build` (imagem, Containerfile, dependências), `ci`, `chore` (manutenção), `perf`, `style`, `revert`.
- `escopo` opcional, curto e em minúsculas. Neste repositório, prefira: `image` (Containerfile), `compose`, `cli` (`sandbox`/`sandbox.sh`), `gui`, `opencode`, `security`, `docs`.
- `descrição` em português do Brasil, no imperativo, sem ponto final e com até 72 caracteres na primeira linha. Exemplo: `fix(cli): resolver WORKSPACE_DIR relativo a partir da raiz`.
- Mudança incompatível: `!` após o tipo/escopo (`feat(compose)!: ...`) **e** rodapé `BREAKING CHANGE: <explicação>`.
- Um commit por mudança lógica; não misturar refatoração com correção.
- Em projetos do usuário que já tenham convenção própria de commits, seguir a do projeto.

## Ao modificar

1. Ler `docs/ARCHITECTURE.md` e `docs/SECURITY.md` antes de alterar privilégios, mounts ou rede.
2. Fazer a menor alteração que atenda ao pedido; não sobrescrever trabalho do usuário.
3. Rodar `./sandbox validate` **antes e depois** de mudanças em imagem, Compose, rede, mounts, permissões ou no script `sandbox`. O `scripts/validate.sh` é o contrato de saúde e isolamento: cada checagem tem um ID e o motivo. Nunca enfraquecer, pular ou remover uma checagem para fazê-la passar; corrigir a mudança. Se o usuário pedir explicitamente para mudar um requisito, alterar a checagem, o motivo e `docs/SECURITY.md` no mesmo commit. Requisito novo = checagem nova com ID novo.
4. Sem Podman disponível, rodar ao menos `./sandbox validate --static` e declarar que a validação em runtime não foi executada.
5. Validar o Compose com `podman-compose -f compose.yaml config` e, quando GUI for alterada, mesclar os overrides correspondentes e rodar `./sandbox validate` com o perfil GUI ativo.
6. Para Wayland/PipeWire, executar `./sandbox gui-verify`; se não houver sessão gráfica, declarar que o teste não foi executado em vez de afirmar que passou.
7. Revisar o diff e procurar segredos antes de concluir. Não fazer commit ou push automaticamente; quando o usuário pedir um commit, seguir a seção "Mensagens de commit".

## Agentes especializados

- `reviewer`: revisão somente leitura de corretude, regressões e testes.
- `security-reviewer`: revisão somente leitura de isolamento, segredos, supply chain e permissões.

O agente principal deve acionar o revisor adequado para mudanças não triviais. Achados precisam citar arquivo e linha, priorizar riscos reais e evitar alterações automáticas durante a revisão.
