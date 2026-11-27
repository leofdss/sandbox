#!/usr/bin/env bash
# Validação de SAÚDE e ISOLAMENTO do sandbox. Roda no HOST.
#
#   ./sandbox validate            sobe o ambiente (se preciso) e valida tudo
#   ./sandbox validate --static   só arquivos do repositório; não usa containers
#
# Este arquivo é o contrato do ambiente. Cada checagem tem um ID estável e um
# comentário com o motivo. Ao mudar imagem, Compose, rede, mounts ou o script
# `sandbox`:
#
#   1. rode `./sandbox validate` antes e depois da mudança;
#   2. NUNCA enfraqueça, pule ou apague uma checagem para fazê-la passar;
#      corrija a mudança;
#   3. se um requisito mudar de verdade (pedido explícito do usuário), altere
#      a checagem, o motivo e docs/SECURITY.md no mesmo commit;
#   4. requisito novo = checagem nova aqui, com ID novo (não reutilize IDs).
#
# Grupos:
#   S-*  estático: arquivos do repositório (vale em CI, sem Podman rodando)
#   H-*  saúde: containers de pé, saudáveis e usando a imagem/política atuais
#   I-*  isolamento: privilégios, mounts, dispositivos, rede e credenciais
#
# Saída: uma linha PASS/FAIL/SKIP por checagem; código 1 se alguma falhar.
set -uo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
NAME="${SANDBOX_NAME:-sandbox-ai}"
PROXY_NAME="${NAME}-egress"
IMAGE="localhost/sandbox-ai:2.4.1"
INTERNAL_NET="sandbox_internal"
EGRESS_NET="sandbox_egress"
# Volumes nomeados permitidos no container do agente (compose.yaml).
DEV_VOLUMES="sandbox_opencode-config sandbox_opencode-data sandbox_opencode-cache sandbox_podman-storage"
# Capabilities que nunca podem estar no bounding set do agente.
FORBIDDEN_CAPS="SYS_ADMIN NET_ADMIN NET_RAW SYS_MODULE SYS_PTRACE SYS_RAWIO SYS_BOOT SYS_TIME MKNOD BPF PERFMON DAC_READ_SEARCH"

static_only=0
case "${1:-}" in
    --static) static_only=1 ;;
    "") ;;
    -h|--help) sed -n '2,24p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) printf 'uso: %s [--static]\n' "$0" >&2; exit 2 ;;
esac

passed=0
failed=0
skipped=0
failures=()

pass() { printf 'PASS  %-10s %s\n' "$1" "$2"; passed=$((passed + 1)); }
fail() {
    printf 'FAIL  %-10s %s\n' "$1" "$2"
    [[ -n "${3:-}" ]] && printf '      %s\n' "$3"
    failed=$((failed + 1))
    failures+=("$1")
}
skip() { printf 'SKIP  %-10s %s\n' "$1" "$2"; skipped=$((skipped + 1)); }
# check ID "descrição" comando...  -> PASS se o comando retornar 0.
check() {
    local id="$1" desc="$2" out
    shift 2
    if out="$("$@" 2>&1)"; then pass "${id}" "${desc}"; else fail "${id}" "${desc}" "${out}"; fi
}
section() { printf '\n== %s ==\n' "$1"; }

# Linhas efetivas de YAML/config, sem comentários.
code_lines() { sed -e 's/[[:space:]]#.*$//' -e '/^[[:space:]]*#/d' "$@"; }

inspect() { podman inspect --format "$2" "$1" 2>/dev/null; }
in_dev() { podman exec "${NAME}" bash -c "$1"; }

# Converte um nome de capability no bit correspondente (linux/capability.h).
cap_bit() {
    case "$1" in
        DAC_READ_SEARCH) echo 2 ;; NET_ADMIN) echo 12 ;; NET_RAW) echo 13 ;;
        SYS_MODULE) echo 16 ;; SYS_RAWIO) echo 17 ;; SYS_PTRACE) echo 19 ;;
        SYS_ADMIN) echo 21 ;; SYS_BOOT) echo 22 ;; SYS_TIME) echo 25 ;;
        MKNOD) echo 27 ;; PERFMON) echo 38 ;; BPF) echo 39 ;;
    esac
}

# ---------------------------------------------------------------------------
section 'Estático (repositório)'
# ---------------------------------------------------------------------------

# S-01: erro de sintaxe quebra o CLI e os testes dentro da imagem.
check S-01 'scripts Bash sem erro de sintaxe' \
    bash -n "${ROOT_DIR}/sandbox" "${ROOT_DIR}"/scripts/*.sh

# S-02: as opções abaixo anulam o isolamento inteiro; nenhum perfil as usa.
s02() {
    local hits
    hits="$(for f in "${ROOT_DIR}"/compose*.yaml; do
        code_lines "$f" | grep -nEi \
            -e 'privileged:[[:space:]]*true' -e 'network_mode' \
            -e '(pid|ipc|uts|userns_mode|cgroup):[[:space:]]*"?host' \
            -e 'SYS_ADMIN|NET_ADMIN|SYS_MODULE|SYS_PTRACE' -e 'cap_add' \
            -e '(seccomp|apparmor)[=:]unconfined' \
            -e 'docker\.sock|podman\.sock|SSH_AUTH_SOCK|/\.ssh' \
            -e 'user:[[:space:]]*"?(0|root)' \
            | sed "s|^|$(basename "$f"):|"
    done)"
    [[ -z "${hits}" ]] || { printf '%s\n' "${hits}"; return 1; }
}
check S-02 'Compose sem privileged, host namespaces, cap_add, unconfined ou sockets do host' s02

# S-03: o agente só pode estar na rede interna; a saída é o proxy.
s03() {
    code_lines "${ROOT_DIR}/compose.yaml" | grep -qE '^[[:space:]]+internal:[[:space:]]*true' \
        || { echo 'rede sandbox-internal sem internal: true'; return 1; }
    # Bloco de networks do serviço dev: exatamente "- sandbox-internal".
    local nets
    nets="$(code_lines "${ROOT_DIR}/compose.yaml" | awk '
        /^  dev:/ { in_dev = 1; next }
        in_dev && /^  [a-z]/ { in_dev = 0 }
        in_dev && /^    networks:/ { in_net = 1; next }
        in_net && /^    [a-z]/ { in_net = 0 }
        in_net && NF { print $NF }')"
    [[ "${nets}" == "sandbox-internal" ]] || { echo "dev.networks = ${nets:-<vazio>}"; return 1; }
    # Nenhum override pode religar o dev a outra rede.
    ! grep -lE '^[[:space:]]+networks:' "${ROOT_DIR}"/compose.*.yaml 2>/dev/null
}
check S-03 'serviço dev somente na rede internal; overrides não mudam a rede' s03

# S-04: as variáveis de proxy precisam sobrescrever as herdadas do host.
s04() {
    local v
    for v in HTTP_PROXY HTTPS_PROXY http_proxy https_proxy; do
        code_lines "${ROOT_DIR}/compose.yaml" | grep -qE "^[[:space:]]+${v}: http://egress-proxy:8888$" \
            || { echo "falta ${v}"; return 1; }
    done
}
check S-04 'HTTP(S)_PROXY apontam para o egress-proxy' s04

# S-05: a política do proxy é negar por padrão e tunelar só TLS.
s05() {
    local conf="${ROOT_DIR}/config/egress/tinyproxy.conf" c
    c="$(code_lines "${conf}")"
    grep -qx 'FilterDefaultDeny Yes' <<<"${c}" || { echo 'FilterDefaultDeny Yes ausente'; return 1; }
    [[ "$(grep -c '^ConnectPort' <<<"${c}")" == 1 ]] && grep -qx 'ConnectPort 443' <<<"${c}" \
        || { echo 'ConnectPort deve ser só 443'; return 1; }
    ! grep -nE '^(Allow[[:space:]]+0\.0\.0\.0|Listen[[:space:]]+0\.0\.0\.0|Upstream|BasicAuth)' <<<"${c}"
}
check S-05 'tinyproxy: deny por padrão, CONNECT só 443, sem Allow 0.0.0.0/Upstream' s05

# S-06: regra sem "$" no fim libera "github.com.atacante.tld"; ".*" libera tudo.
s06() {
    local bad
    bad="$(code_lines "${ROOT_DIR}/config/egress/allowlist.txt" | sed '/^[[:space:]]*$/d' \
        | grep -vE '^\(\^\|\\\.\)[a-z0-9-]+(\\\.[a-z0-9-]+)+\$$')"
    [[ -z "${bad}" ]] || { printf 'regras fora do formato (^|\\.)dominio\\.tld$:\n%s\n' "${bad}"; return 1; }
}
check S-06 'allowlist: toda regra ancorada no formato (^|\.)dominio\.tld$' s06

# S-07: o proxy não pode herdar VOLUME graváveis/anônimos da imagem base.
s07() {
    local block
    block="$(code_lines "${ROOT_DIR}/compose.yaml" | awk '/^  egress-proxy:/ {p=1; next} p && /^  [a-z]/ {p=0} p')"
    grep -qE '^[[:space:]]+read_only:[[:space:]]*true' <<<"${block}" || { echo 'read_only ausente'; return 1; }
    grep -qE '^[[:space:]]+volumes:' <<<"${block}" && { echo 'proxy não deve ter volumes'; return 1; }
    local p
    for p in /home/podman/.local/share/containers /var/lib/containers /var/tmp; do
        grep -qE "^[[:space:]]+- ${p}:" <<<"${block}" || { echo "tmpfs ausente para VOLUME ${p}"; return 1; }
    done
}
check S-07 'egress-proxy read_only e com tmpfs sobre os VOLUME da imagem' s07

if [[ "${static_only}" == 1 ]]; then
    printf '\nresultado: %d passou, %d falhou, %d ignorado (modo --static)\n' "${passed}" "${failed}" "${skipped}"
    [[ "${failed}" == 0 ]] || { printf 'falhas: %s\n' "${failures[*]}"; exit 1; }
    exit 0
fi

# ---------------------------------------------------------------------------
section 'Saúde'
# ---------------------------------------------------------------------------

check H-01 "imagem ${IMAGE} existe" podman image exists "${IMAGE}"
image_id="$(podman image inspect --format '{{.Id}}' "${IMAGE}" 2>/dev/null || true)"

for c in "${NAME}" "${PROXY_NAME}"; do
    if ! podman container exists "${c}"; then
        fail H-02 "container ${c} existe" 'rode ./sandbox up'
        continue
    fi
    # H-02: ambos precisam estar de pé; sem o proxy o agente fica sem rede.
    if [[ "$(inspect "${c}" '{{.State.Running}}')" == "true" ]]; then
        pass H-02 "${c} em execução"
    else
        fail H-02 "${c} em execução" "estado: $(inspect "${c}" '{{.State.Status}}')"
    fi
    # H-03: executa o healthcheck agora em vez de esperar o intervalo.
    check H-03 "${c} healthcheck" podman healthcheck run "${c}"
    # H-04: container antigo após um build = política/código desatualizados.
    if [[ "$(inspect "${c}" '{{.Image}}')" == "${image_id}" ]]; then
        pass H-04 "${c} usa a imagem atual"
    else
        fail H-04 "${c} usa a imagem atual" 'rode ./sandbox up para recriar'
    fi
done

# H-05: a política lida pelo proxy é a do repositório (imagem não ficou velha).
h05() {
    local f
    for f in allowlist.txt:allowlist.txt tinyproxy.conf:sandbox.conf; do
        cmp -s <(podman exec "${PROXY_NAME}" cat "/etc/tinyproxy/${f#*:}") \
               "${ROOT_DIR}/config/egress/${f%%:*}" \
            || { echo "/etc/tinyproxy/${f#*:} difere de config/egress/${f%%:*}; rode ./sandbox build"; return 1; }
    done
}
check H-05 'política do proxy igual a config/egress/' h05

# H-06: testes funcionais dentro do agente (ferramentas, workspace, egress,
# Podman aninhado). Ver scripts/verify.sh. VERIFY_PULL=0 evita download.
h06() { podman exec -e "VERIFY_PULL=${VERIFY_PULL:-1}" "${NAME}" sandbox-verify; }
if out="$(h06 2>&1)"; then
    pass H-06 'sandbox-verify dentro do container'
else
    fail H-06 'sandbox-verify dentro do container' "$(tail -12 <<<"${out}")"
fi

if ! podman container exists "${NAME}" || ! podman container exists "${PROXY_NAME}"; then
    printf '\nresultado: %d passou, %d falhou — containers ausentes, isolamento não avaliado\n' "${passed}" "${failed}"
    exit 1
fi

# ---------------------------------------------------------------------------
section 'Isolamento: privilégios do agente'
# ---------------------------------------------------------------------------

profile="$(inspect "${NAME}" '{{ index .Config.Labels "ai.sandbox.profile" }}')"
printf 'perfil: %s\n' "${profile:-desconhecido}"

check I-01 'agente não é privileged' \
    test "$(inspect "${NAME}" '{{.HostConfig.Privileged}}')" == false
check I-02 'agente roda como 1000:1000' \
    test "$(inspect "${NAME}" '{{.Config.User}}')" == 1000:1000
check I-03 'processo do agente tem UID 1000 e nenhuma capability efetiva' \
    in_dev '[[ "$(id -u)" == 1000 ]] && grep -qx "CapEff:[[:space:]]*0000000000000000" /proc/self/status'

# I-04: o bounding set limita o que o Podman aninhado pode conceder.
i04() {
    local bnd name bit bad=()
    bnd="$(in_dev 'awk "/^CapBnd/ {print \$2}" /proc/self/status')" || return 1
    for name in ${FORBIDDEN_CAPS}; do
        bit="$(cap_bit "${name}")"
        (( (16#${bnd} >> bit) & 1 )) && bad+=("${name}")
    done
    [[ "${#bad[@]}" == 0 ]] || { echo "CapBnd=${bnd} contém: ${bad[*]}"; return 1; }
}
check I-04 "bounding set sem ${FORBIDDEN_CAPS// /, }" i04

check I-05 'seccomp ativo (modo filtro)' \
    in_dev 'grep -qx "Seccomp:[[:space:]]*2" /proc/self/status'

# I-06: namespaces do host anulariam o isolamento de processos e rede.
i06() {
    local f v
    for f in NetworkMode PidMode IpcMode UTSMode; do
        v="$(inspect "${NAME}" "{{.HostConfig.${f}}}")"
        [[ "${v}" != host ]] || { echo "${f}=host"; return 1; }
    done
    # UID 0 do container não pode ser o root do host (sem userns).
    in_dev '! grep -qE "^[[:space:]]*0[[:space:]]+0[[:space:]]+4294967295" /proc/self/uid_map' \
        || { echo 'container no user namespace do host'; return 1; }
}
check I-06 'sem namespaces do host (net, pid, ipc, uts, user)' i06

check I-07 'security_opt sem seccomp/apparmor unconfined' \
    bash -c '! grep -qiE "unconfined" <<<"$1"' _ "$(inspect "${NAME}" '{{json .HostConfig.SecurityOpt}}')"

check I-08 'configuração gerenciada do OpenCode não é gravável pelo agente' \
    in_dev '! test -w /etc/opencode && ! test -w /etc/opencode/opencode.jsonc && ! test -w /etc/tinyproxy/allowlist.txt'

# ---------------------------------------------------------------------------
section 'Isolamento: arquivos, sockets e dispositivos'
# ---------------------------------------------------------------------------

workspace="$(inspect "${NAME}" '{{range .Mounts}}{{if eq .Destination "/workspace"}}{{.Source}}{{end}}{{end}}')"

# I-10: /workspace é o projeto do usuário; nunca HOME, /, a raiz do repo ou
# algo que contenha o blackbox (o agente poderia reescrever o próprio sandbox).
i10() {
    [[ -n "${workspace}" ]] || { echo '/workspace não montado'; return 1; }
    local ws
    ws="$(realpath -e "${workspace}" 2>/dev/null || echo "${workspace}")"
    case "${ws}" in
        /|"${HOME}"|"$(dirname -- "${ROOT_DIR}")") echo "workspace amplo demais: ${ws}"; return 1 ;;
    esac
    [[ "${ROOT_DIR}/" != "${ws}/"* ]] || { echo "workspace ${ws} contém o blackbox"; return 1; }
    [[ "${ws}/" != "${HOME}/.ssh/"* && "${ws}" != "${HOME}/.config" ]] || { echo "workspace sensível: ${ws}"; return 1; }
}
check I-10 "workspace restrito (${workspace:-?})" i10

# I-11: mounts do agente só nos destinos previstos pelos perfis Compose.
i11() {
    local type name src dst rw bad=()
    while IFS='|' read -r type name src dst rw; do
        [[ -n "${type}" ]] || continue
        case "${type}:${dst}" in
            bind:/workspace) ;;
            volume:*)
                [[ " ${DEV_VOLUMES} " == *" ${name} "* ]] || bad+=("volume inesperado ${name}:${dst}") ;;
            # Sockets/arquivos individuais da GUI, nunca diretórios inteiros.
            bind:/run/user/1000/pipewire-0|bind:/run/user/1000/pulse/native|bind:/run/user/1000/wayland-*)
                [[ -S "${src}" ]] || bad+=("${dst} não é socket (${src})") ;;
            bind:/run/user/1000/.Xauthority)
                [[ -f "${src}" && "${rw}" == false ]] || bad+=("Xauthority deve ser arquivo somente leitura") ;;
            bind:/tmp/.X11-unix|bind:/usr/lib/wsl)
                [[ "${rw}" == false ]] || bad+=("${dst} deve ser somente leitura") ;;
            *) bad+=("mount não previsto ${type} ${src} -> ${dst}") ;;
        esac
        case "${src}" in
            *podman.sock|*docker.sock|*/.ssh|*/.ssh/*|*/.gnupg*|*ssh-agent*|"${HOME}") bad+=("fonte proibida ${src}") ;;
        esac
    done < <(inspect "${NAME}" '{{range .Mounts}}{{.Type}}|{{.Name}}|{{.Source}}|{{.Destination}}|{{.RW}}{{"\n"}}{{end}}')
    [[ "${#bad[@]}" == 0 ]] || { printf '%s\n' "${bad[@]}"; return 1; }
}
check I-11 'mounts do agente só nos destinos previstos (sem HOME, SSH ou sockets do motor)' i11

check I-12 'nenhum socket do motor de containers do host visível' \
    in_dev '! test -e /run/user/1000/podman/podman.sock && ! test -e /run/podman/podman.sock && ! test -e /var/run/docker.sock && [[ -z "${SSH_AUTH_SOCK:-}" ]]'

# I-13: /dev só com o padrão do runtime + fuse; GPU apenas nos perfis -gpu.
i13() {
    local allowed='console core fd full fuse mqueue null ptmx pts random shm stderr stdin stdout tty urandom zero'
    case "${profile}" in
        *wslg-gpu*) allowed+=' dxg' ;;
        *gpu*) allowed+=' dri' ;;
    esac
    local extra
    extra="$(in_dev 'ls -A /dev' | grep -vxF -f <(tr ' ' '\n' <<<"${allowed}"))"
    [[ -z "${extra}" ]] || { echo "dispositivos inesperados: $(tr '\n' ' ' <<<"${extra}")"; return 1; }
    in_dev 'test -c /dev/fuse' || { echo '/dev/fuse ausente (Podman aninhado quebra)'; return 1; }
}
check I-13 '/dev contém apenas dispositivos previstos para o perfil' i13

# I-14: segredos de provedores não podem ser herdados do host. Só nomes são
# exibidos, nunca valores.
check I-14 'nenhuma variável com cara de credencial no ambiente do agente' \
    bash -c 'hits="$(grep -E "(KEY|TOKEN|SECRET|PASSW|CREDENTIAL|COOKIE)[A-Z_]*$|^AWS_|^AZURE_|^GOOGLE_APPLICATION" <<<"$1")"; [[ -z "${hits}" ]] || { echo "${hits}"; exit 1; }' \
    _ "$(in_dev 'env | cut -d= -f1')"

# ---------------------------------------------------------------------------
section 'Isolamento: rede'
# ---------------------------------------------------------------------------

nets_of() { inspect "$1" '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' | xargs -n1 | sort | xargs; }

check I-20 "rede ${INTERNAL_NET} é internal" \
    test "$(podman network inspect --format '{{.Internal}}' "${INTERNAL_NET}" 2>/dev/null)" == true
check I-21 "agente somente em ${INTERNAL_NET}" \
    bash -c '[[ "$1" == "$2" ]] || { echo "redes: $1"; exit 1; }' _ "$(nets_of "${NAME}")" "${INTERNAL_NET}"
check I-22 "proxy somente em ${EGRESS_NET} e ${INTERNAL_NET}" \
    bash -c '[[ "$1" == "$2" ]] || { echo "redes: $1"; exit 1; }' _ "$(nets_of "${PROXY_NAME}")" "${EGRESS_NET} ${INTERNAL_NET}"

# I-23: portas só em loopback (perfil ports); o proxy nunca publica portas.
i23() {
    local line bad=()
    while read -r line; do
        [[ -n "${line}" ]] || continue
        [[ "${line#*=}" == 127.0.0.1 || "${line#*=}" == ::1 ]] || bad+=("agente ${line}")
    done < <(inspect "${NAME}" '{{range $p, $b := .NetworkSettings.Ports}}{{range $b}}{{$p}}={{.HostIP}}{{"\n"}}{{end}}{{end}}')
    [[ -z "$(inspect "${PROXY_NAME}" '{{range $p, $b := .NetworkSettings.Ports}}{{range $b}}{{$p}}{{end}}{{end}}')" ]] \
        || bad+=('proxy publica portas')
    [[ "${#bad[@]}" == 0 ]] || { printf '%s\n' "${bad[@]}"; return 1; }
}
check I-23 'portas publicadas apenas em loopback; proxy sem portas' i23

check I-24 'variáveis de proxy ativas no agente' \
    in_dev '[[ "${HTTPS_PROXY:-}" == http://egress-proxy:8888 && "${https_proxy:-}" == http://egress-proxy:8888 ]]'

# ---------------------------------------------------------------------------
section 'Isolamento: proxy de egress'
# ---------------------------------------------------------------------------

check I-30 'proxy não é privileged e roda como 1000:1000' \
    test "$(inspect "${PROXY_NAME}" '{{.HostConfig.Privileged}} {{.Config.User}}')" == 'false 1000:1000'
check I-31 'proxy com rootfs somente leitura' \
    test "$(inspect "${PROXY_NAME}" '{{.HostConfig.ReadonlyRootfs}}')" == true
check I-32 'proxy com no-new-privileges e sem capabilities' \
    podman exec "${PROXY_NAME}" bash -c 'grep -qx "NoNewPrivs:[[:space:]]*1" /proc/self/status && grep -qx "CapBnd:[[:space:]]*0000000000000000" /proc/self/status'
check I-33 'proxy sem bind mounts nem volumes' \
    test -z "$(inspect "${PROXY_NAME}" '{{range .Mounts}}{{.Type}}:{{.Destination}} {{end}}')"
check I-34 'proxy com limites de PIDs e memória' \
    bash -c '[[ "$1" -gt 0 && "$2" -gt 0 ]]' _ \
    "$(inspect "${PROXY_NAME}" '{{.HostConfig.PidsLimit}}')" "$(inspect "${PROXY_NAME}" '{{.HostConfig.Memory}}')"

# ---------------------------------------------------------------------------
printf '\nresultado: %d passou, %d falhou, %d ignorado\n' "${passed}" "${failed}" "${skipped}"
if [[ "${failed}" -gt 0 ]]; then
    printf 'falhas: %s\n' "${failures[*]}"
    printf 'Não enfraqueça a checagem: corrija a mudança (veja o cabeçalho deste script).\n'
    exit 1
fi
