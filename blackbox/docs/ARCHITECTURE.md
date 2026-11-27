# Arquitetura e decisões

## Visão geral

```text
host: <raiz-do-repositório>/blackbox/                ambiente versionado, não montado
host: <raiz-do-repositório>/sandbox/                 projetos do usuário
                                       │
usuário Linux/WSL2                     ▼
└── Podman rootless do host
    └── container externo "sandbox-ai" (UID 1000, sem privilégio total)
        ├── /workspace                 somente os projetos do usuário
        ├── OpenCode --standalone      agente e ferramentas
        ├── Git / Python / Node
        ├── Podman + podman-compose    motor aninhado, não o socket do host
        │   └── containers internos    storage e rede controlados pelo sandbox
        └── sockets opcionais
            ├── Wayland               vídeo local
            ├── PipeWire/PulseAudio   áudio/vídeo local, opt-in
            ├── X11                   compatibilidade, opt-in
            └── render node/vGPU      aceleração, opt-in
```

Há dois níveis de user namespaces. No host, o processo continua sem root. O modo `keep-id:uid=1000,gid=1000` mapeia o UID/GID de quem chamou o Podman para o usuário `podman` dentro do container, independentemente de o UID do host ser 1000. Isso preserva a propriedade dos arquivos no bind mount.

O usuário interno já existe na imagem oficial e possui faixas em `/etc/subuid` e `/etc/subgid` que evitam o UID 1000. Assim, o Podman aninhado pode criar seus próprios mapeamentos.

## Escolha do Podman aninhado

| Estratégia | Vantagem | Custo/risco | Decisão |
|---|---|---|---|
| Montar `podman.sock` do host | Simples e compatível | O agente controla todos os containers e bind mounts disponíveis ao usuário do host | Rejeitada como padrão |
| Podman aninhado com `--privileged` | Menos ajustes | Remove várias barreiras de isolamento | Rejeitada |
| Podman aninhado rootless, `/dev/fuse`, sem `--privileged` | Storage e lifecycle separados; menos privilégios | SELinux externo precisa de exceção; há complexidade de UID e rede | **Adotada** |
| VM dedicada | Forte separação de kernel | Mais recursos e operação | Fora do objetivo |

A imagem deriva de `quay.io/podman/stable:v6.1.3-immutable` pelo digest multi-arquitetura. A configuração oficial dessa imagem já usa `fuse-overlayfs`, usuário UID 1000 e defaults destinados a Podman-em-Podman.

`/dev/fuse` é o único dispositivo do perfil headless. `label=disable` é exigido pela receita oficial para containers aninhados em hosts SELinux e não desativa o SELinux do host. O impacto está documentado em [SECURITY.md](SECURITY.md).

## Rede em camadas

O Compose externo coloca o container `dev` apenas na rede `sandbox_internal` (`internal: true`: sem rota padrão e sem DNS externo) e sem portas publicadas. O serviço `egress-proxy`, um tinyproxy rodando da mesma imagem com filesystem somente leitura e sem capabilities, é o único membro também ligado à rede `sandbox_egress`, com saída. A política (allowlist de domínios, `CONNECT` só na porta 443) é copiada para a imagem; alterações feitas dentro do container do agente não chegam ao proxy. A configuração da imagem oficial define `netns="host"` para o motor aninhado: “host” nesse caso é o namespace do **container externo**, não o namespace físico da máquina.

Consequências:

- containers internos enxergam serviços que escutam no sandbox;
- `-p` no motor interno não cria uma publicação no host real;
- `compose.ports.yaml` publica explicitamente uma porta do container externo em `127.0.0.1`;
- a saída é falha-fechada: sem o proxy o agente fica sem rede, e o `sandbox` recria o ambiente se o proxy não estiver em execução;
- a allowlist reduz, mas não elimina, a exfiltração: destinos liberados (GitHub, registros, provedores de IA) ainda podem receber dados.

## Persistência

O bind mount do workspace é o único acesso intencional a arquivos comuns do host. Volumes nomeados preservam configuração, sessões e storage sem misturá-los ao Git. `Z` aplica um label SELinux privado quando necessário; isso pode exigir novo relabel caso o mesmo diretório seja compartilhado com outro container.

`/run/user/1000` é criado na camada gravável descartável do container, pertence ao UID 1000 e usa modo 0700. O Compose GUI monta sockets individuais nesse diretório, sem compartilhar o `XDG_RUNTIME_DIR` completo do host. `/var/tmp` e o storage rootful não utilizado são tmpfs para que as declarações `VOLUME` herdadas da imagem base não deixem volumes anônimos a cada recriação; somente o storage rootless é persistente.

O container externo é recriado ao trocar de perfil explicitamente (`up`, `ports`, `gui`), pois mounts e dispositivos não podem ser adicionados a um container em execução. Comandos que só precisam de um shell (`shell`, `ai`, `run`, `verify`, `exec`) reutilizam um container GUI ou com portas em execução se a imagem e o workspace coincidirem. Um hash do workspace, das opções usadas pelo perfil, dos arquivos Compose, da imagem e dos inodes dos sockets/cookies impede que um container antigo seja reutilizado com outra configuração; variáveis do host que o perfil não usa (como `DISPLAY` no headless) ficam fora do hash. Os volumes nomeados sobrevivem; processos do container anterior não.

## Reprodutibilidade e atualização

- imagem base: tag imutável **e** digest multi-arquitetura;
- OpenCode: versão 2.4.1, artefato glibc por arquitetura e SHA-256;
- x86_64 usa o artefato `baseline` para não exigir AVX2;
- ARM64 usa o artefato oficial correspondente;
- download por HTTPS, sem `curl | bash`;
- RPMs auxiliares: repositórios Fedora resolvidos durante o build.

Para atualizar, altere versão, digest e checksums juntos, construa e execute `verify`/`gui-verify`. Tags `latest` não são usadas. O lock garante identidade das duas dependências mais importantes, mas não congela todo o repositório RPM.

## GUI como overlays

`compose.yaml` não contém sockets ou dispositivos de desktop. O script combina arquivos conforme a sessão:

- `compose.wayland.yaml`: socket e variáveis do compositor;
- `compose.pipewire.yaml`: API nativa de mídia;
- `compose.pulse.yaml`: protocolo PulseAudio, inclusive WSLg;
- `compose.x11.yaml`: compatibilidade XWayland;
- `compose.xauthority.yaml`: somente o cookie X11 resolvido, se ele existir;
- `compose.gpu.yaml`: somente render node;
- `compose.wslg-gpu.yaml`: `/dev/dxg` e bibliotecas da vGPU WSLg;
- `compose.ports.yaml`: publicação explícita em loopback.

D-Bus de sessão, portals e todo o `/mnt/wslg` não são expostos. Isso reduz integração e alguns recursos de desktop, mas evita ampliar a superfície sem necessidade.

## Agentes e política em camadas

`/etc/opencode/opencode.jsonc` é a configuração gerenciada da imagem: desativa autoatualização, compartilhamento e automações, bloqueia leituras sensíveis e acesso a diretórios externos e define as permissões do fluxo de trabalho. `AGENTS.md`, a documentação, os agentes e os comandos também são copiados para `/etc/opencode`; nenhum arquivo do `blackbox` precisa ser montado no workspace do usuário.

Os agentes `reviewer` e `security-reviewer` começam negando todas as ações e liberam apenas leitura e inspeção Git. `AGENTS.md` descreve comandos e limites. Um projeto do usuário pode acrescentar suas próprias instruções, mas não pode enfraquecer as policies gerenciadas. Nenhuma dessas regras deve ser tratada como substituto do isolamento do kernel: quem executa shell arbitrário pode tentar contornar intenções expressas em prompts.
