---
description: Valida scripts, Compose, containers e documentação alterada
---

Verifique as mudanças atuais sem fazer commit nem push.

1. Execute `bash -n sandbox scripts/*.sh`.
2. Execute `podman-compose -f compose.yaml config`.
3. Se houver alteração de imagem ou Compose, execute `./sandbox verify`.
4. Se houver alteração de Wayland, PipeWire, PulseAudio ou GPU, execute `./sandbox gui-verify` somente quando uma sessão gráfica estiver disponível; caso contrário, registre a limitação.
5. Revise `git diff --check` e procure credenciais acidentais.
6. Use o subagente `reviewer`; para mudanças de privilégios, mounts ou supply chain, use também `security-reviewer`.

Peça confirmação antes de qualquer build longo ou download. Não mude arquivos durante uma revisão somente leitura. Informe comandos executados, resultados e verificações que ficaram pendentes.
