# Fontes pesquisadas

Consulta realizada em **26 de novembro de 2026**. As decisões priorizam documentação oficial e upstream; artigos de terceiros não são a base das opções de privilégio.

## Podman e rootless

- [Podman rootless tutorial — containers/podman](https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md): subordinate IDs, volumes, storage rootless e `keep-id`.
- [`podman run` — documentação oficial](https://docs.podman.io/en/stable/markdown/podman-run.1.html): `keep-id`, dispositivos, `keep-groups`, SELinux, volumes e segurança.
- [Understanding rootless Podman's user namespace modes — Red Hat](https://www.redhat.com/en/blog/rootless-podman-user-namespace-modes): diferença entre mapeamento padrão, `keep-id`, `auto` e `nomap`.
- [How to use Podman inside of a container — Red Hat](https://www.redhat.com/en/blog/podman-inside-container): motivos para `/dev/fuse`, user namespaces e armazenamento aninhado.
- [RHEL 10 — Running Podman with less privileges](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html/building_running_and_managing_containers/running-skopeo-buildah-and-podman-in-a-container): exemplo sem `--privileged`, com `label=disable`, usuário não root e `/dev/fuse`.
- [Privileged and unprivileged containers — RHEL 10](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html/building_running_and_managing_containers/running-skopeo-buildah-and-podman-in-a-container): efeitos de `--privileged` sobre isolamento.
- [Containerfile oficial `containers/image_build/podman`](https://github.com/containers/image_build/blob/main/podman/Containerfile): base da imagem `quay.io/podman/stable`, UID 1000, subordinate IDs e fuse-overlayfs.
- [`containers.conf` da imagem oficial](https://github.com/containers/image_build/blob/main/podman/containers.conf) e [configuração rootless](https://github.com/containers/image_build/blob/main/podman/podman-containers.conf): namespaces e mounts do motor aninhado.
- [Quay — tags/digests `podman/stable`](https://quay.io/repository/podman/stable?tab=tags): origem da tag imutável e do digest multi-arquitetura fixado.
- [Docker Hub — BusyBox 1.37.0](https://hub.docker.com/_/busybox): digest multi-arquitetura da imagem mínima usada somente no teste aninhado.

## Podman Compose

- [containers/podman-compose](https://github.com/containers/podman-compose): funcionamento rootless/daemon-less, dependências e instalação.
- [Extensão `x-podman.in_pod`](https://github.com/containers/podman-compose/blob/main/docs/Extensions.md): necessidade de desativar o pod ao usar `userns_mode`.
- [`podman compose` — documentação](https://docs.podman.io/en/stable/markdown/podman-compose.1.html): relação entre o wrapper do Podman e o provedor externo `podman-compose`.

## OpenCode V2

- [Introdução e instalação](https://opencode.ai/docs): CLI V2 e artefatos por plataforma.
- [Release v2.4.1 e assets](https://github.com/anomalyco/opencode/releases/expanded_assets/v2.4.1): binários Linux e SHA-256 usados no Containerfile.
- [Configuração](https://opencode.ai/docs/config): `opencode.jsonc`, precedência, policies e variáveis.
- [Instruções/AGENTS.md](https://opencode.ai/docs/rules): descoberta, escopo e atualização de instruções.
- [Agentes](https://opencode.ai/docs/agents): Markdown em `.opencode/agents`, frontmatter V2, modos e permissões.
- [Permissões](https://opencode.ai/docs/permissions): ordem das regras, `shell`, `external_directory`, scanner e policies.
- [CLI](https://opencode.ai/docs/cli): `run` e `--standalone` para servidor privado.
- [Migração V1→V2](https://opencode.ai/docs/migrate-v1): razão para não usar campos antigos.

## Wayland e mídia

- [Wayland Client API — `wl_display_connect`](https://wayland.freedesktop.org/docs/html/apb.html): resolução de `WAYLAND_DISPLAY` relativa a `XDG_RUNTIME_DIR` e sockets absolutos.
- [Wayland Protocol and Model of Operation](https://wayland.freedesktop.org/docs/book/Protocol.html): socket Unix `wayland-0`.
- [X11 Application Support/XWayland](https://wayland.freedesktop.org/docs/book/Xwayland.html): relação entre clientes X11, XWayland e compositor.
- [X.Org — `xauth(1)`](https://www.x.org/archive/current/doc/man/man1/xauth.1.xhtml) e [`Xsecurity(7)`](https://www.x.org/archive/current/doc/man/man7/Xsecurity.7.xhtml): localização e sensibilidade do cookie `XAUTHORITY`.
- [PipeWire Native Protocol](https://docs.pipewire.org/page_native_protocol.html): busca por `PIPEWIRE_RUNTIME_DIR`/`XDG_RUNTIME_DIR` e socket `pipewire-0`.
- [PipeWire Protocol Pulse](https://pipewire.pages.freedesktop.org/pipewire/devel/page_module_protocol_pulse.html): compatibilidade com clientes PulseAudio.
- [PulseAudio FAQ](https://www.freedesktop.org/wiki/Software/PulseAudio/FAQ/): precedência de `PULSE_SERVER` e localização de sockets.
- [Microsoft WSLg — Containerizing GUI applications](https://github.com/microsoft/wslg/blob/main/samples/container/Containers.md): mounts Wayland/PulseAudio, `/dev/dxg` e `/usr/lib/wsl`.
- [Red Hat — Remotely accessing a Wayland-based application](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/getting_started_with_the_gnome_desktop_environment/remotely-accessing-an-individual-application-wayland_getting-started-with-the-gnome-desktop-environment): `waypipe` sobre SSH para aplicativos individuais.

## Implicações adotadas no projeto

1. Podman aninhado sem socket do host e sem `--privileged`, aceitando a exceção SELinux documentada.
2. `keep-id` com UID/GID interno explícito para propriedade correta no workspace.
3. Storage rootless em volume separado, evitando overlay-sobre-overlay no bind mount.
4. Wayland independente de PipeWire; PulseAudio como compatibilidade necessária no WSLg.
5. GUI, mídia, GPU e portas como opt-in; D-Bus fora do escopo.
6. OpenCode V2 com instruções versionadas, agentes read-only e auto-update desativado.
7. GUI remota não tratada como simples bind mount: requer transporte como Waypipe.
