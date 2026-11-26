# Wayland, PipeWire, X11 e WSLg

## O que é realmente necessário

Um aplicativo Wayland é um cliente do compositor do host. Para exibi-lo, o container precisa:

1. do socket `${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}`, normalmente `/run/user/1000/wayland-0`;
2. de `XDG_RUNTIME_DIR` apontando para o diretório interno do socket;
3. de `WAYLAND_DISPLAY` com o nome do socket;
4. de bibliotecas cliente e, opcionalmente, aceleração.

**PipeWire não participa da abertura da janela.** Ele é incluído apenas para aplicativos que produzem/consomem áudio ou vídeo. Muitos aplicativos usam a API PulseAudio de compatibilidade, oferecida pelo `pipewire-pulse` ou, no WSLg, por um servidor PulseAudio.

Não é iniciado outro compositor nem outro daemon de mídia no container. O sandbox é cliente dos serviços da sessão do host.

## Detecção automática

```bash
./sandbox doctor
./sandbox gui
```

O script:

- resolve symlinks do socket Wayland (necessário no WSL2);
- monta somente esse socket em `/run/user/1000/<display>`;
- detecta `/tmp/.X11-unix` quando `DISPLAY` existe;
- se houver `XAUTHORITY` ou `$HOME/.Xauthority`, resolve e monta somente esse cookie como leitura; servidores X11 sem cookie, como o WSLg, não recebem esse arquivo;
- prefere `pipewire-0`; se ausente, tenta `PULSE_SERVER=unix:...` ou `pulse/native`;
- não monta D-Bus, `/dev/snd` ou o `XDG_RUNTIME_DIR` completo;
- não passa GPU a menos que `--gpu` ou `--wslg-gpu` seja informado.

Sem GPU, o rendering por software costuma funcionar, com desempenho menor.

## Testes

```bash
./sandbox gui-verify
./sandbox exec foot       # terminal nativo Wayland
./sandbox exec xeyes      # compatibilidade X11
```

`gui-verify` verifica:

- execução de um container aninhado;
- conexão `wayland-info`;
- `xdpyinfo`, se X11 estiver habilitado;
- `pw-cli info 0` ou `pactl info`, se áudio estiver habilitado;
- escrita no workspace.

Um teste de protocolo não substitui o teste visual de cada toolkit/aplicativo.

## Linux nativo com PipeWire

O caminho típico é:

```text
host:      /run/user/1000/pipewire-0
container: /run/user/1000/pipewire-0
```

`PIPEWIRE_RUNTIME_DIR` e `XDG_RUNTIME_DIR` apontam para o diretório interno. O socket dá acesso às permissões da sua sessão, que podem incluir microfone, câmera ou compartilhamento de mídia. Use `--no-audio` quando somente vídeo for necessário.

## WSL2 / WSLg

No WSLg, `/run/user/1000/wayland-0` frequentemente é um symlink para `/mnt/wslg/runtime-dir/wayland-0`, e o áudio usa algo como:

```bash
PULSE_SERVER=unix:/mnt/wslg/PulseServer
```

O script resolve esses caminhos e os apresenta em locais neutros no container. Não é necessário montar `/mnt/wslg` inteiro.

Em outros compositores, o XWayland pode exigir um cookie. Nesse caso o arquivo `XAUTHORITY` (ou `$HOME/.Xauthority`) é montado individualmente como leitura, e o hostname do container assume o hostname do host para que entradas `FamilyLocal` sejam encontradas. O cookie é uma credencial da sessão: use `--no-x11` se a aplicação for nativa Wayland.

Para a vGPU:

```bash
./sandbox gui --wslg-gpu
```

Isso adiciona `/dev/dxg`, `/usr/lib/wsl` e `LD_LIBRARY_PATH=/usr/lib/wsl/lib`, seguindo o exemplo oficial do WSLg. Use somente se o aplicativo precisar de aceleração. Para um render node DRM convencional:

```bash
./sandbox gui --gpu
# ou outro nó explicitamente:
DRI_DEVICE=/dev/dri/renderD129 ./sandbox gui --gpu
```

`group_add: keep-groups` preserva o grupo `render` no modo DRI e requer `crun`. Drivers NVIDIA proprietários e treinamento de modelos por CDI não fazem parte deste perfil de GUI.

## Servidor headless e aplicativo remoto

Não há `WAYLAND_DISPLAY` em um servidor headless e o perfil padrão não precisa dele. Para desenvolver via SSH:

```bash
./sandbox up
./sandbox ai
```

Para abrir no laptop uma aplicação criada no servidor, montar um socket não basta: o socket está no namespace de filesystem do servidor. Alternativas:

- `waypipe ssh usuario@servidor <aplicativo>`, com Waypipe nos dois lados e o container configurado para usar o socket encaminhado;
- forwarding X11 para aplicações legadas, com as ressalvas de segurança do X11;
- VNC/RDP ou uma interface web publicada com autenticação e TLS.

A referência da Red Hat descreve Waypipe para encaminhar aplicativos individuais, não um desktop inteiro. O wrapper não instala nem configura Waypipe automaticamente porque envolve duas máquinas, credenciais SSH e escolhas de transporte.

## Problemas comuns

### `Socket Wayland não encontrado`

Confirme na sessão local:

```bash
printf '%s\n' "$XDG_RUNTIME_DIR" "$WAYLAND_DISPLAY"
ls -l "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}"
./sandbox doctor
```

Em SSH sem sessão gráfica isso é esperado. Não use o modo `gui`; configure Waypipe ou outro transporte.

### `Permission denied` no socket

Não execute o container como root. O Compose mapeia o usuário do host para UID 1000. Em SELinux, verifique os logs AVC antes de mudar labels. O perfil já usa `label=disable` para o Podman aninhado; não desabilite o SELinux do host inteiro.

### Janela preta ou falha EGL

Teste primeiro sem GPU. Depois use `--gpu` ou `--wslg-gpu`, confirme o dispositivo e instale no aplicativo os drivers adequados. O projeto contém Mesa para cenários comuns, não todos os drivers proprietários.

### Aplicativo abre, mas não há som

Execute `./sandbox gui-verify`. Verifique se foi usado `--no-audio`, se o servidor está no modo PipeWire ou PulseAudio e se o aplicativo usa ALSA direto. ALSA direto exigiria `/dev/snd`, que não é exposto deliberadamente.

### Portais, captura de tela ou notificações falham

O D-Bus de sessão e os XDG Desktop Portals não são compartilhados. Essa é uma limitação intencional de integração/segurança. Não monte `/run/user/.../bus` indiscriminadamente; desenhe e revise um perfil específico antes de habilitar esses recursos.
