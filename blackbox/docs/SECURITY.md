# Segurança, ameaças e limites

## Objetivo de proteção

O projeto reduz o impacto de erros, comandos destrutivos e dependências comprometidas durante desenvolvimento assistido por IA. Ele busca limitar acesso ao filesystem, ao motor de containers do host, a dispositivos e a credenciais.

Ele **não** promete conter um exploit de kernel, um adversário com controle total do host ou todo código deliberadamente hostil. Containers compartilham o kernel. Para execução de malware ou cargas de altíssimo risco, prefira uma VM, microVM ou hardware dedicado.

## Controles adotados

| Camada | Controle |
|---|---|
| Host | Podman rootless; execução como usuário comum. |
| Filesystem | Somente `WORKSPACE_DIR` em `/workspace`; nenhum `HOME` completo. |
| Containers | Podman aninhado com storage dedicado; nenhum socket do motor do host. |
| Privilégios | Sem `--privileged`, `SYS_ADMIN` ou root como usuário de execução; `NET_RAW` removido. |
| GUI | Wayland e mídia por overlays; somente sockets necessários; GPU opt-in. |
| Rede | Nenhuma porta publicada por padrão; publicação explícita em loopback. Saída só via proxy com allowlist. |
| Credenciais | Nenhuma variável de provedor herdada; volumes separados e `.env` no `.gitignore`. |
| OpenCode | Servidor privado, shell com confirmação, leituras sensíveis negadas e push/sudo bloqueados. |
| Supply chain | Digest multi-arquitetura da base e SHA-256 dos binários OpenCode. |

## Exceções deliberadas

### `/dev/fuse`

O `fuse-overlayfs` aninhado precisa desse dispositivo. Ele aumenta a superfície em comparação a um container comum, mas evita conceder `--privileged` e o socket do motor do host. Não adicione `/dev/kvm`, `/dev/snd`, dispositivos de bloco ou outros nós sem necessidade documentada.

### `security_opt: label=disable`

A documentação da Red Hat para Podman aninhado sem `--privileged` usa `--security-opt label=disable`, porque a política SELinux padrão impede mounts exigidos pelo motor interno.

Isso desativa a separação SELinux **do container externo**, não o SELinux do host. Rootless, capabilities, namespaces e permissões de arquivos continuam aplicáveis, mas uma camada de defesa é removida. Não oculte essa perda ao avaliar o ambiente. Não desabilite SELinux globalmente.

`label=nested` pode ser avaliado em hosts/políticas mais recentes, mas não é usado como default sem uma matriz de testes equivalente.

### Sem `no-new-privileges`

`newuidmap`/`newgidmap` usam mecanismos de transição necessários aos mapeamentos rootless. Ativar `no-new-privileges` no container externo pode impedir o Podman aninhado. Por isso não adicionamos essa opção como “hardening” automático.

### Rede de saída

A rede externa é necessária para provedores de IA, Git e registros OCI. O container do agente não tem rota própria para fora: está numa rede interna do Podman e só alcança o `egress-proxy`, que libera os domínios de `config/egress/allowlist.txt` e túneis `CONNECT` apenas na porta 443. Isso vale também para binários que ignoram as regras do OpenCode, pois a contenção é de rede, não de configuração.

Limites que permanecem:

- domínios liberados continuam podendo receber dados (por exemplo, um gist no GitHub ou um pacote publicado num registro);
- o filtro compara o nome do host; o conteúdo HTTPS não é inspecionado;
- o proxy aceita qualquer cliente das redes privadas do Podman, então outros containers do mesmo usuário ligados à rede interna também podem usá-lo.

Para projetos não confiáveis, reduza a allowlist ao mínimo, use credenciais de escopo mínimo e uma conta de usuário dedicada.

## O que o socket do host evitaria expor

Montar `podman.sock` ou `docker.sock` permitiria pedir ao motor do host containers com bind mounts arbitrários acessíveis ao usuário, além de listar/remover cargas alheias. Mesmo rootless, isso é muito mais autoridade do que o Podman aninhado precisa. Por isso não há fallback automático para o socket.

## Riscos dos overlays de desktop

- **Wayland:** concede criação de clientes na sessão do compositor. É preferível ao X11, mas não transforma o aplicativo em confiável.
- **X11:** clientes podem ter visibilidade indevida de entrada/saída de outros clientes, dependendo do servidor/extensions. Use apenas para compatibilidade. Quando exigido, o cookie `XAUTHORITY` também é uma credencial sensível e é montado isoladamente como leitura.
- **PipeWire/PulseAudio:** pode expor microfone, fontes e controle de streams. Desative com `--no-audio` quando não for essencial.
- **GPU:** dispositivos ampliam a superfície de drivers/kernel. O perfil comum usa apenas render node; WSLg usa `/dev/dxg`.
- **D-Bus/portals:** não são configurados, evitando autoridade adicional sobre a sessão. Alguns recursos ficam indisponíveis.

## Credenciais e dados

Não coloque segredos em `.env`, `opencode.jsonc`, prompts, `Containerfile` ou Compose. `.env` é ignorado pelo Git; `.env.example` contém somente valores não secretos. Não há montagem de `~/.ssh`, `~/.config`, cookies de browser ou agentes SSH.

As credenciais conectadas pela TUI são persistidas no volume `opencode-data`. Volumes nomeados não são criptografados por este projeto: o usuário do host e administradores com acesso ao storage podem lê-los. Proteja backup e disco, use contas com escopo mínimo e revogue chaves ao descartar o ambiente.

O `reset` apaga volumes locais, mas não revoga tokens no provedor nem remove segredos que tenham sido enviados a terceiros.

## Permissões do OpenCode

As políticas V2 são uma segunda linha de defesa:

- shell padrão: `ask`; somente `git status` é liberado, pois diffs e logs podem conter segredos;
- `grep`, pesquisas web e diffs Git: `ask` (o recurso da permissão `grep` é a expressão, não o caminho);
- `external_directory`: `deny` por regra e policy;
- arquivos `.env`, chaves e padrões de chave privada: `deny`;
- `git push`, `sudo`, `doas` e `podman system reset`: `deny` por regra e policy;
- revisores: deny-all seguido de allow somente para leitura/inspeção;
- mudanças de configuração sensível: `ask`.

Não use `--auto` por padrão. Mesmo sem ele, comandos aprovados pelo usuário executam com a autoridade real do processo. Um scanner de shell não consegue prever todo efeito de scripts, binários ou comandos compostos. `AGENTS.md` orienta comportamento, mas não é mecanismo de segurança do kernel.

## Recomendações para servidor

1. Use uma conta sem sudo dedicada ao sandbox.
2. Mantenha kernel, Podman e `crun` atualizados.
3. Restrinja o workspace e nunca monte `/`, `$HOME` ou diretórios de outros clientes.
4. Faça backup dos volumes com permissões adequadas e trate-os como segredos.
5. Não exponha a porta `APP_PORT` publicamente sem autenticação/TLS e firewall.
6. Considere limites de memória/CPU além de `pids_limit`, conforme cgroups do servidor.
7. Monitore consumo do `podman-storage`; o build aninhado pode crescer bastante.
8. Revise atualizações de digest/checksum e execute os testes antes de substituir o ambiente ativo.
