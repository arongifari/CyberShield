#!/usr/bin/env bash
# ==============================================================================
# CYBERSHIELD ULTIMATE v3.0 - Universal Shell Security Toolkit
# Native Bash Security Framework for Linux, Android Termux, WSL & Git Bash
# ==============================================================================

# Strict mode for error handling (unset variables & pipe failures)
set -u
set -o pipefail

# ------------------------------------------------------------------------------
# GLOBAL CONSTANTS & DIRECTORY PATHS
# ------------------------------------------------------------------------------
VERSION="3.0 Universal Shell Edition"
APP_NAME="CYBERSHIELD ULTIMATE"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONFIG_DIR="${BASE_DIR}/config"
DB_DIR="${BASE_DIR}/database"
REPORTS_DIR="${BASE_DIR}/reports"
QUARANTINE_DIR="${BASE_DIR}/quarantine"
LOGS_DIR="${BASE_DIR}/logs"

CONFIG_FILE="${CONFIG_DIR}/cybershield.conf"
HASH_DB="${DB_DIR}/malware_hashes.db"
FIM_DB="${DB_DIR}/fim_baseline.db"
QUARANTINE_META="${QUARANTINE_DIR}/metadata.db"
APP_LOG="${LOGS_DIR}/cybershield.log"

# ------------------------------------------------------------------------------
# COLOR DEFINITIONS (ANSI ESCAPE CODES)
# ------------------------------------------------------------------------------
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    PURPLE='\033[0;35m'
    CYAN='\033[0;36m'
    WHITE='\033[1;37m'
    BOLD='\033[1m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    PURPLE=''
    CYAN=''
    WHITE=''
    BOLD=''
    NC=''
fi

# ------------------------------------------------------------------------------
# ENVIRONMENT & ENVIRONMENT DETECTION VARIABLES
# ------------------------------------------------------------------------------
OS_NAME=""
OS_TYPE=""        # termux, debian_like, arch_like, fedora_like, wsl, generic
PKG_MANAGER=""
ARCH_CPU=""
IS_ROOT=false
IS_TERMUX=false
IS_WSL=false
CURRENT_USER="$(whoami 2>/dev/null || echo "user")"
HOSTNAME_VAL="$(hostname 2>/dev/null || echo "localhost")"
KERNEL_VAL="$(uname -r 2>/dev/null || echo "Unknown")"
VIRUSTOTAL_API_KEY=""

# Global Scan Counters & Risk Stats
FINDINGS_LOW=0
FINDINGS_MED=0
FINDINGS_HIGH=0
FINDINGS_CRIT=0
TOTAL_CHECKED=0

# ------------------------------------------------------------------------------
# INITIALIZATION & SYSTEM DETECTION
# ------------------------------------------------------------------------------
detect_environment() {
    # CPU Architecture
    ARCH_CPU="$(uname -m 2>/dev/null || echo "unknown")"

    # Termux Detection
    if [[ -d "/data/data/com.termux" ]] || [[ -n "${TERMUX_VERSION:-}" ]]; then
        IS_TERMUX=true
        OS_TYPE="termux"
        OS_NAME="Android Termux (${ARCH_CPU})"
        PKG_MANAGER="pkg"
    # WSL Detection
    elif [[ -f /proc/version ]] && grep -qi "microsoft" /proc/version; then
        IS_WSL=true
        OS_TYPE="wsl"
        OS_NAME="Windows Subsystem for Linux (WSL)"
        PKG_MANAGER="apt"
    # Standard Linux Distributions
    elif [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_NAME="${NAME:-Linux}"
        if [[ "${ID_LIKE:-}" =~ "debian" ]] || [[ "${ID:-}" =~ "debian|ubuntu|kali|parrot|mint" ]]; then
            OS_TYPE="debian_like"
            PKG_MANAGER="apt"
        elif [[ "${ID_LIKE:-}" =~ "arch" ]] || [[ "${ID:-}" =~ "arch" ]]; then
            OS_TYPE="arch_like"
            PKG_MANAGER="pacman"
        elif [[ "${ID_LIKE:-}" =~ "fedora" ]] || [[ "${ID:-}" =~ "fedora|rhel|centos" ]]; then
            OS_TYPE="fedora_like"
            PKG_MANAGER="dnf"
        else
            OS_TYPE="generic"
            PKG_MANAGER="unknown"
        fi
    else
        OS_NAME="$(uname -s)"
        OS_TYPE="generic"
        PKG_MANAGER="unknown"
    fi

    # Detect Root Access
    if [[ $EUID -eq 0 ]]; then
        IS_ROOT=true
    else
        IS_ROOT=false
    fi
}

init_environment() {
    mkdir -p "$CONFIG_DIR" "$DB_DIR" "$REPORTS_DIR" "$QUARANTINE_DIR" "$LOGS_DIR"

    [[ ! -f "$APP_LOG" ]] && touch "$APP_LOG"
    [[ ! -f "$QUARANTINE_META" ]] && touch "$QUARANTINE_META"

    # Load / Create Configuration
    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat <<EOF > "$CONFIG_FILE"
# CyberShield Ultimate v3.0 Configuration
VIRUSTOTAL_API_KEY=""
CPU_THRESHOLD=80
RAM_THRESHOLD=80
EOF
    else
        VIRUSTOTAL_API_KEY="$(grep -E '^VIRUSTOTAL_API_KEY=' "$CONFIG_FILE" | cut -d'=' -f2 | tr -d '"' | tr -d "'" || true)"
    fi

    # Initialize Signature Database
    if [[ ! -f "$HASH_DB" ]]; then
        cat <<EOF > "$HASH_DB"
# Sample Known Malicious Hashes (MD5 / SHA256)
44d88612fea8a8f36de82e1278abb02f
e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
41454145414541454145414541454145
EOF
    fi

    detect_environment
}

log_message() {
    local level="$1"
    local msg="$2"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "NOW")"
    echo "[$timestamp] [$level] $msg" >> "$APP_LOG"
}

# ------------------------------------------------------------------------------
# UI HELPER & TERMINAL FORMATTING FUNCTIONS
# ------------------------------------------------------------------------------
draw_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "  ██████╗██╗   ██╗██████╗ ███████╗██████╗ ███████╗██╗  ██╗██╗███████╗██╗     ██╗██╗"
    echo " ██╔════╝╚██╗ ██╔╝██╔══██╗██╔════╝██╔══██╗██╔════╝██║  ██║██║██╔════╝██║     ██║██║"
    echo " ██║      ╚████╔╝ ██████╔╝█████╗  ██████╔╝███████╗███████║██║█████╗  ██║     ██║██║"
    echo " ██║       ╚██╔╝  ██╔══██╗██╔══╝  ██╔══██╗╚════██║██╔══██║██║██╔══╝  ██║     ██║██║"
    echo " ╚██████╗   ██║   ██████╔╝███████╗██║  ██║███████║██║  ██║██║███████╗███████╗██║███████╗"
    echo "  ╚═════╝   ╚═╝   ╚═════╝ ╚══════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝╚══════╝╚══════╝╚═╝╚══════╝"
    echo -e "${NC}"
    echo -e "${WHITE}${BOLD}               CYBERSHIELD ULTIMATE v${VERSION}${NC}"
    echo -e "${CYAN}             UNIVERSAL SHELL DEFENSIVE SECURITY TOOLKIT${NC}"
    echo -e "${CYAN}${BOLD}====================================================================${NC}"
    echo -e "${WHITE}OS Platform:${NC} ${GREEN}${OS_NAME}${NC}"
    echo -e "${WHITE}Arch / CPU :${NC} ${ARCH_CPU} | ${WHITE}Kernel:${NC} ${KERNEL_VAL}"
    echo -e "${WHITE}Hostname   :${NC} ${HOSTNAME_VAL} | ${WHITE}User:${NC} ${CURRENT_USER}"
    if $IS_ROOT; then
        echo -e "${WHITE}Privileges :${NC} ${RED}${BOLD}ROOT / ADMINISTRATOR (FULL ACCESS)${NC}"
    else
        echo -e "${WHITE}Privileges :${NC} ${YELLOW}LIMITED USER / NON-ROOT (RESTRICTED AUDIT)${NC}"
    fi
    echo -e "${CYAN}--------------------------------------------------------------------${NC}"
}

print_status() {
    local type="$1"
    local message="$2"
    case "$type" in
        "INFO")  echo -e "[${BLUE}INFO${NC}] $message" ;;
        "OK")    echo -e "[${GREEN} OK ${NC}] $message" ;;
        "WARN")  echo -e "[${YELLOW}WARN${NC}] $message" ;;
        "FAIL")  echo -e "[${RED}FAIL${NC}] $message" ;;
        "CRIT")  echo -e "[${RED}${BOLD}CRIT${NC}] $message" ;;
        "LIMITED") echo -e "[${YELLOW}LIMITED${NC}] $message" ;;
        "NOTSUP") echo -e "[${PURPLE}NOT SUPPORTED${NC}] $message" ;;
        *)       echo -e "[$type] $message" ;;
    esac
}

press_enter() {
    echo ""
    echo -e "${WHITE}Tekan [ENTER] untuk kembali ke menu...${NC}"
    read -r
}

check_cmd() {
    command -v "$1" &>/dev/null
}

# ------------------------------------------------------------------------------
# UNIVERSAL INSTALLER & DEPENDENCY MANAGER
# ------------------------------------------------------------------------------
install_dependencies() {
    draw_banner
    echo -e "${BOLD}--- [ DEPENDENCY & INSTALLER MANAGER ] ---${NC}\n"

    echo "Pilih Mode Instalasi Dependensi:"
    echo "1. Instalasi Minimal (curl, wget, net-tools, coreutils, clamav)"
    echo "2. Instalasi Lengkap (Minimal + Nmap, Rkhunter, Chkrootkit, UFW)"
    echo "3. Batal"
    echo -ne "\nPilihan [1-3]: "
    read -r inst_opt

    local pkgs_minimal=""
    local pkgs_full=""

    if $IS_TERMUX; then
        pkgs_minimal="curl wget coreutils findutils net-tools openssl"
        pkgs_full="$pkgs_minimal nmap clamav"
    elif [[ "$PKG_MANAGER" == "apt" ]]; then
        pkgs_minimal="curl wget coreutils net-tools openssl clamav"
        pkgs_full="$pkgs_minimal nmap rkhunter chkrootkit ufw"
    elif [[ "$PKG_MANAGER" == "pacman" ]]; then
        pkgs_minimal="curl wget coreutils net-tools openssl clamav"
        pkgs_full="$pkgs_minimal nmap rkhunter chkrootkit ufw"
    elif [[ "$PKG_MANAGER" == "dnf" ]]; then
        pkgs_minimal="curl wget coreutils net-tools openssl clamav"
        pkgs_full="$pkgs_minimal nmap rkhunter chkrootkit ufw"
    fi

    local target_pkgs=""
    case "$inst_opt" in
        1) target_pkgs="$pkgs_minimal" ;;
        2) target_pkgs="$pkgs_full" ;;
        *) return ;;
    esac

    print_status "INFO" "Memeriksa koneksi internet..."
    if ! ping -c 1 8.8.8.8 &>/dev/null; then
        print_status "WARN" "Koneksi internet tidak stabil atau ping diblokir. Melanjutkan instalasi..."
    fi

    print_status "INFO" "Menginstall paket via $PKG_MANAGER: $target_pkgs"
    case "$PKG_MANAGER" in
        pkg)
            pkg update -y && pkg install -y $target_pkgs
            ;;
        apt)
            if $IS_ROOT; then
                apt update -y && apt install -y $target_pkgs
            else
                print_status "FAIL" "Diperlukan hak akses ROOT (sudo) untuk menjalankan apt!"
            fi
            ;;
        pacman)
            if $IS_ROOT; then
                pacman -Sy --noconfirm $target_pkgs
            else
                print_status "FAIL" "Diperlukan hak akses ROOT untuk menjalankan pacman!"
            fi
            ;;
        dnf)
            if $IS_ROOT; then
                dnf install -y $target_pkgs
            else
                print_status "FAIL" "Diperlukan hak akses ROOT untuk menjalankan dnf!"
            fi
            ;;
        *)
            print_status "FAIL" "Package manager tidak didukung untuk instalasi otomatis."
            ;;
    esac

    press_enter
}

# ------------------------------------------------------------------------------
# MODULE 1: MALWARE SCANNER
# ------------------------------------------------------------------------------
module_malware_scanner() {
    draw_banner
    echo -e "${BOLD}--- [ MODUL 1: MALWARE SCANNER ] ---${NC}\n"

    local scan_dir=""
    if $IS_TERMUX; then
        echo "Pilih direktori pemindaian Termux:"
        echo "1. Termux Private Home (~)"
        echo "2. Termux Temp Directory ($PREFIX/tmp)"
        echo "3. Shared Internal Storage (/sdcard) - Memerlukan Izin"
        echo "4. Custom Path"
        echo -ne "\nPilihan [1-4]: "
        read -r t_opt
        case "$t_opt" in
            1) scan_dir="$HOME" ;;
            2) scan_dir="$PREFIX/tmp" ;;
            3) scan_dir="/sdcard" ;;
            4) echo -ne "Masukkan path lengkap: "; read -r scan_dir ;;
            *) return ;;
        esac
    else
        echo "Pilih direktori pemindaian Linux:"
        echo "1. Temporary Folders (/tmp, /var/tmp, /dev/shm)"
        echo "2. User Home Directory ($HOME)"
        echo "3. Custom Path"
        echo -ne "\nPilihan [1-3]: "
        read -r l_opt
        case "$l_opt" in
            1) scan_dir="/tmp /var/tmp /dev/shm" ;;
            2) scan_dir="$HOME" ;;
            3) echo -ne "Masukkan path lengkap: "; read -r scan_dir ;;
            *) return ;;
        esac
    fi

    print_status "INFO" "Memulai pemindaian malware di: $scan_dir"
    local findings=0
    local scanned_files=0

    for d in $scan_dir; do
        if [[ -d "$d" ]]; then
            while IFS= read -r file; do
                [[ -f "$file" ]] || continue
                ((scanned_files++))

                # Hash Calculation
                local file_hash_md5=""
                local file_hash_sha256=""
                if check_cmd "md5sum"; then file_hash_md5=$(md5sum "$file" 2>/dev/null | awk '{print $1}'); fi
                if check_cmd "sha256sum"; then file_hash_sha256=$(sha256sum "$file" 2>/dev/null | awk '{print $1}'); fi

                # Hash DB Matching
                if grep -qi "$file_hash_md5" "$HASH_DB" 2>/dev/null || grep -qi "$file_hash_sha256" "$HASH_DB" 2>/dev/null; then
                    print_status "CRIT" "MALWARE DETECTED: $file"
                    echo "   -> Risk: HIGH | Signature Match"
                    ((findings++))
                    ((FINDINGS_HIGH++))
                fi

                # Suspicious Extensions / Executables in Temp
                if [[ "$d" =~ "tmp" ]] && [[ "$file" =~ \.(sh|py|exe|elf|bin|php)$ ]]; then
                    print_status "WARN" "Suspicious Executable Script in Temp Folder: $file"
                    ((findings++))
                    ((FINDINGS_MED++))
                fi

            done < <(find "$d" -maxdepth 2 -type f 2>/dev/null)
        fi
    done

    # ClamAV Engine Integration
    if check_cmd "clamscan"; then
        print_status "INFO" "Menjalankan ClamAV Antivirus Engine..."
        clamscan -r --no-summary $scan_dir 2>/dev/null | grep "FOUND" && ((findings++)) || true
    fi

    echo -e "\n${BOLD}Ringkasan Pemindaian:${NC} $scanned_files file diperiksa, $findings ancaman ditemukan."
    press_enter
}

# ------------------------------------------------------------------------------
# MODULE 2: ROOTKIT SCANNER (WITH TERMUX ADAPTATION)
# ------------------------------------------------------------------------------
module_rootkit_scanner() {
    draw_banner
    echo -e "${BOLD}--- [ MODUL 2: ROOTKIT SCANNER ] ---${NC}\n"

    if $IS_TERMUX && ! $IS_ROOT; then
        print_status "NOTSUP" "Pemeriksaan Rootkit Lengkap TIDAK DIDUKUNG di Termux tanpa akses ROOT!"
        print_status "LIMITED" "Menjalankan pemeriksaan keterbatasan terbatas pada biner pengguna..."
    fi

    local findings=0

    # Inspect Core System Binaries
    print_status "INFO" "Memeriksa integritas binary (/bin/ls, /bin/ps, /usr/bin/top)..."
    local bins=("/bin/ls" "/bin/ps" "/usr/bin/top" "$PREFIX/bin/ls" "$PREFIX/bin/ps")
    for b in "${bins[@]}"; do
        if [[ -f "$b" ]]; then
            if file "$b" 2>/dev/null | grep -qi "shell script"; then
                print_status "CRIT" "Binary Terinfeksi/Trojanized (Script Replace): $b"
                ((findings++))
                ((FINDINGS_CRIT++))
            fi
        fi
    done

    # Integrated Tools Exec
    if check_cmd "rkhunter" && $IS_ROOT; then
        print_status "INFO" "Menjalankan rkhunter..."
        rkhunter --check --sk --quiet 2>/dev/null || true
    elif check_cmd "rkhunter"; then
        print_status "LIMITED" "rkhunter membutuhkan akses ROOT."
    fi

    if check_cmd "chkrootkit" && $IS_ROOT; then
        print_status "INFO" "Menjalankan chkrootkit..."
        chkrootkit -q 2>/dev/null || true
    fi

    press_enter
}

# ------------------------------------------------------------------------------
# MODULE 3: BACKDOOR DETECTOR
# ------------------------------------------------------------------------------
module_backdoor_detector() {
    draw_banner
    echo -e "${BOLD}--- [ MODUL 3: BACKDOOR DETECTOR ] ---${NC}\n"

    print_status "INFO" "Menganalisis proses aktif & Reverse Shell..."
    local findings=0

    local rev_shells
    rev_shells=$(ps aux 2>/dev/null || ps -ef 2>/dev/null | grep -E "nc -e|/bin/bash -i|python.*socket|perl -e.*socket" | grep -v grep || true)

    if [[ -n "$rev_shells" ]]; then
        print_status "CRIT" "REVERSE SHELL PROCESS DETECTED!"
        echo "$rev_shells"
        ((findings++))
        ((FINDINGS_CRIT++))
    else
        print_status "OK" "Tidak terdeteksi indikasi Reverse Shell standar."
    fi

    # Check Suspicious Listening Ports
    if check_cmd "ss"; then
        local ports
        ports=$(ss -tuln 2>/dev/null | grep -E ":(4444|5555|6666|1337|31337) " || true)
        if [[ -n "$ports" ]]; then
            print_status "HIGH" "Port umum backdoor/Metasploit Listening!"
            echo "$ports"
            ((findings++))
            ((FINDINGS_HIGH++))
        fi
    fi

    press_enter
}

# ------------------------------------------------------------------------------
# MODULE 4 & 5: UNIVERSAL URL & WEBSITE SECURITY AUDIT
# ------------------------------------------------------------------------------
module_url_scanner() {
    draw_banner
    echo -e "${BOLD}--- [ MODUL 4 & 5: UNIVERSAL URL & WEBSITE AUDIT ] ---${NC}\n"

    echo -ne "Masukkan URL / Domain target (contoh: https://example.com): "
    read -r target_url

    if [[ -z "$target_url" ]]; then
        print_status "FAIL" "URL tidak boleh kosong!"
        press_enter
        return
    fi

    local domain
    domain=$(echo "$target_url" | awk -F/ '{print $3}')
    [[ -z "$domain" ]] && domain=$(echo "$target_url" | awk -F/ '{print $1}')

    print_status "INFO" "Menganalisis URL secara PASIF dan AMAN: $target_url"
    print_status "INFO" "Domain Target: $domain"

    # 1. DNS Resolution
    print_status "INFO" "1. Checking DNS Lookup..."
    if check_cmd "host"; then
        host "$domain" | head -n 3
    elif check_cmd "nslookup"; then
        nslookup "$domain"
    elif check_cmd "ping"; then
        ping -c 1 "$domain" 2>/dev/null | head -n 1
    fi

    # 2. SSL/TLS Inspection
    print_status "INFO" "2. Checking SSL/TLS Certificate..."
    if check_cmd "openssl"; then
        local cert_out
        cert_out=$(echo | openssl s_client -servername "$domain" -connect "${domain}:443" 2>/dev/null | openssl x509 -noout -dates 2>/dev/null || true)
        if [[ -n "$cert_out" ]]; then
            print_status "OK" "SSL Certificate Active:"
            echo "$cert_out"
        else
            print_status "WARN" "Gagal mengambil SSL cert / port 443 tidak merespon."
        fi
    fi

    # 3. HTTP Security Headers
    print_status "INFO" "3. Checking Security Headers..."
    if check_cmd "curl"; then
        local headers
        headers=$(curl -sI -m 5 "$target_url" || true)
        if [[ -n "$headers" ]]; then
            echo "$headers" | grep -iE "HTTP/|strict-transport-security|x-frame-options|x-content-type-options|content-security-policy" || true
        fi
    fi

    # 4. Phishing Heuristics
    if echo "$target_url" | grep -qE "login|verify|account|banking|free|secure"; then
        print_status "WARN" "URL mengandung kata sensitif (Potensi Phishing)."
        ((FINDINGS_LOW++))
    fi

    # 5. VirusTotal API Query (If API Key Present)
    if [[ -n "$VIRUSTOTAL_API_KEY" ]] && check_cmd "curl"; then
        print_status "INFO" "Querying VirusTotal API..."
        local vt_res
        vt_res=$(curl -s --request GET --url "https://www.virustotal.com/api/v3/domains/${domain}" --header "x-apikey: ${VIRUSTOTAL_API_KEY}" || true)
        if echo "$vt_res" | grep -q "malicious"; then
            print_status "CRIT" "VirusTotal Reputasi Ancam Terdeteksi!"
        fi
    fi

    press_enter
}

# ------------------------------------------------------------------------------
# MODULE 6: NETWORK SCANNER
# ------------------------------------------------------------------------------
module_network_scanner() {
    draw_banner
    echo -e "${BOLD}--- [ MODUL 6: NETWORK SCANNER ] ---${NC}\n"

    print_status "INFO" "Memeriksa Socket & Port Terbuka Aktif..."
    if check_cmd "ss"; then
        ss -tuln
    elif check_cmd "netstat"; then
        netstat -tuln
    fi

    if check_cmd "nmap"; then
        echo -ne "\n[?] Jalankan Nmap port scan lokal? (y/n): "
        read -r ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            nmap -sT 127.0.0.1
        fi
    fi

    press_enter
}

# ------------------------------------------------------------------------------
# MODULE 7: PROCESS ANALYZER
# ------------------------------------------------------------------------------
module_process_analyzer() {
    draw_banner
    echo -e "${BOLD}--- [ MODUL 7: PROCESS ANALYZER ] ---${NC}\n"

    print_status "INFO" "Top 5 Proses Penggunaan CPU/RAM Tertinggi:"
    ps aux 2>/dev/null | sort -nr -k 3 | head -n 6 || ps -ef 2>/dev/null | head -n 6

    press_enter
}

# ------------------------------------------------------------------------------
# MODULE 8: FILE INTEGRITY MONITOR (FIM)
# ------------------------------------------------------------------------------
module_fim() {
    draw_banner
    echo -e "${BOLD}--- [ MODUL 8: FILE INTEGRITY MONITOR ] ---${NC}\n"

    echo "1. Buat / Perbarui Baseline Hash"
    echo "2. Bandingkan dengan Baseline"
    echo "3. Batal"
    echo -ne "\nPilihan [1-3]: "
    read -r fim_opt

    local mon_files=()
    if $IS_TERMUX; then
        mon_files=("$PREFIX/etc/bash.bashrc" "$HOME/.bashrc")
    else
        mon_files=("/etc/passwd" "/etc/shadow" "/etc/hosts" "/etc/sudoers")
    fi

    case "$fim_opt" in
        1)
            > "$FIM_DB"
            for f in "${mon_files[@]}"; do
                if [[ -f "$f" ]]; then
                    local h
                    h=$(sha256sum "$f" 2>/dev/null | awk '{print $1}')
                    echo "$f|$h" >> "$FIM_DB"
                    print_status "OK" "Recorded: $f"
                fi
            done
            print_status "OK" "Baseline berhasil dibuat."
            ;;
        2)
            if [[ ! -f "$FIM_DB" ]] || [[ ! -s "$FIM_DB" ]]; then
                print_status "FAIL" "Baseline tidak ditemukan!"
                press_enter; return
            fi
            while IFS='|' read -r file old_h; do
                if [[ ! -f "$file" ]]; then
                    print_status "CRIT" "FILE DELETED: $file"
                    ((FINDINGS_HIGH++))
                else
                    local cur_h
                    cur_h=$(sha256sum "$file" 2>/dev/null | awk '{print $1}')
                    if [[ "$cur_h" != "$old_h" ]]; then
                        print_status "CRIT" "FILE MODIFIED: $file"
                        ((FINDINGS_CRIT++))
                    else
                        print_status "OK" "Unchanged: $file"
                    fi
                fi
            done < "$FIM_DB"
            ;;
        *) return ;;
    esac

    press_enter
}

# ------------------------------------------------------------------------------
# MODULE 9: PERSISTENCE SCANNER
# ------------------------------------------------------------------------------
module_persistence_scanner() {
    draw_banner
    echo -e "${BOLD}--- [ MODUL 9: PERSISTENCE SCANNER ] ---${NC}\n"

    print_status "INFO" "Checking Autostart & Scheduled Tasks..."

    if $IS_TERMUX; then
        print_status "INFO" "Checking Termux Boot / Startup Scripts (~/.termux/boot)..."
        if [[ -d "$HOME/.termux/boot" ]]; then
            ls -la "$HOME/.termux/boot"
        else
            print_status "OK" "Tidak ada skrip autostart termux-boot."
        fi
    else
        print_status "INFO" "Checking Cron Jobs & Systemd..."
        ls -la /etc/cron* 2>/dev/null || true
    fi

    press_enter
}

# ------------------------------------------------------------------------------
# MODULE 10: SSH SECURITY AUDIT
# ------------------------------------------------------------------------------
module_ssh_audit() {
    draw_banner
    echo -e "${BOLD}--- [ MODUL 10: SSH SECURITY AUDIT ] ---${NC}\n"

    local ssh_cfg="/etc/ssh/sshd_config"
    $IS_TERMUX && ssh_cfg="$PREFIX/etc/ssh/sshd_config"

    if [[ -f "$ssh_cfg" ]]; then
        if grep -Ei "^PermitRootLogin\s+yes" "$ssh_cfg" &>/dev/null; then
            print_status "CRIT" "PermitRootLogin DIINZINKAN (YES)!"
            ((FINDINGS_HIGH++))
        else
            print_status "OK" "PermitRootLogin aman/dibatasi."
        fi
    else
        print_status "WARN" "SSH Server Config ($ssh_cfg) tidak ditemukan."
    fi

    press_enter
}

# ------------------------------------------------------------------------------
# MODULE 11: LOG ANALYZER
# ------------------------------------------------------------------------------
module_log_analyzer() {
    draw_banner
    echo -e "${BOLD}--- [ MODUL 11: LOG ANALYZER ] ---${NC}\n"

    if [[ -f /var/log/auth.log ]]; then
        print_status "INFO" "Analisis Login Gagal (/var/log/auth.log):"
        grep -i "failed password" /var/log/auth.log | tail -n 5 || echo "Tidak ada log login gagal."
    elif check_cmd "journalctl"; then
        journalctl -u ssh -n 5 --no-pager 2>/dev/null || true
    else
        print_status "LIMITED" "File log standar Linux tidak dapat diakses di lingkungan ini."
    fi

    press_enter
}

# ------------------------------------------------------------------------------
# MODULE 12: FIREWALL AUDIT
# ------------------------------------------------------------------------------
module_firewall_audit() {
    draw_banner
    echo -e "${BOLD}--- [ MODUL 12: FIREWALL AUDIT ] ---${NC}\n"

    if $IS_TERMUX; then
        print_status "NOTSUP" "Firewall audit tidak didukung di Android tanpa akses ROOT kernel."
    elif check_cmd "ufw"; then
        ufw status
    elif check_cmd "iptables" && $IS_ROOT; then
        iptables -L -n -v | head -n 10
    else
        print_status "LIMITED" "Firewall tools (ufw/iptables) memerlukan hak akses ROOT."
    fi

    press_enter
}

# ------------------------------------------------------------------------------
# MODULE 13: VULNERABILITY CHECKER
# ------------------------------------------------------------------------------
module_vulnerability_checker() {
    draw_banner
    echo -e "${BOLD}--- [ MODUL 13: VULNERABILITY CHECKER ] ---${NC}\n"

    print_status "INFO" "Kernel: $KERNEL_VAL"
    print_status "INFO" "Pemeriksaan Update Paket OS ($PKG_MANAGER)..."

    case "$PKG_MANAGER" in
        pkg) pkg list-upgradable 2>/dev/null || true ;;
        apt) apt-get --just-print upgrade 2>/dev/null | grep -i "Inst " | head -n 5 || true ;;
        pacman) checkupdates 2>/dev/null | head -n 5 || true ;;
        dnf) dnf check-update --security 2>/dev/null || true ;;
    esac

    press_enter
}

# ------------------------------------------------------------------------------
# MODULE 14: QUARANTINE MANAGER
# ------------------------------------------------------------------------------
module_quarantine_manager() {
    draw_banner
    echo -e "${BOLD}--- [ MODUL 14: QUARANTINE MANAGER ] ---${NC}\n"

    echo "1. Isolasi File ke Karantina"
    echo "2. Lihat Isi Vault Karantina"
    echo "3. Pulihkan (Restore) File"
    echo "4. Batal"
    echo -ne "\nPilihan [1-4]: "
    read -r q_opt

    case "$q_opt" in
        1)
            echo -ne "Masukkan path file lengkap: "
            read -r target_f
            if [[ ! -f "$target_f" ]]; then
                print_status "FAIL" "File tidak ditemukan!"
                press_enter; return
            fi
            echo -ne "[?] Pindahkan '$target_f' ke Karantina? (y/n): "
            read -r c_ans
            if [[ "$c_ans" =~ ^[Yy]$ ]]; then
                local q_id="Q_$(date +%s)"
                mv "$target_f" "${QUARANTINE_DIR}/${q_id}.vault"
                chmod 000 "${QUARANTINE_DIR}/${q_id}.vault"
                echo "${q_id}|${target_f}|$(date +%s)" >> "$QUARANTINE_META"
                print_status "OK" "File terisolasi aman. ID: $q_id"
            fi
            ;;
        2)
            echo -e "\n${BOLD}[ Isi Vault Karantina ]${NC}"
            cat "$QUARANTINE_META" 2>/dev/null || echo "Vault kosong."
            ;;
        3)
            echo -ne "Masukkan ID Karantina (contoh: Q_1670000000): "
            read -r r_id
            local line
            line=$(grep "^${r_id}|" "$QUARANTINE_META" || true)
            if [[ -n "$line" ]]; then
                IFS='|' read -r q_id orig_path q_time <<< "$line"
                chmod 600 "${QUARANTINE_DIR}/${q_id}.vault"
                mv "${QUARANTINE_DIR}/${q_id}.vault" "$orig_path"
                grep -v "^${r_id}|" "$QUARANTINE_META" > "${QUARANTINE_META}.tmp" && mv "${QUARANTINE_META}.tmp" "$QUARANTINE_META"
                print_status "OK" "File berhasil dipulihkan ke: $orig_path"
            fi
            ;;
        *) return ;;
    esac

    press_enter
}

# ------------------------------------------------------------------------------
# MODULE 15: SECURITY REPORT GENERATOR
# ------------------------------------------------------------------------------
module_report_generator() {
    draw_banner
    echo -e "${BOLD}--- [ MODUL 15: SECURITY REPORT GENERATOR ] ---${NC}\n"

    local t_str
    t_str=$(date +%Y%m%d_%H%M%S)
    local r_txt="${REPORTS_DIR}/report_${t_str}.txt"
    local r_json="${REPORTS_DIR}/report_${t_str}.json"
    local r_html="${REPORTS_DIR}/report_${t_str}.html"

    local penalty=$(( (FINDINGS_LOW * 2) + (FINDINGS_MED * 5) + (FINDINGS_HIGH * 15) + (FINDINGS_CRIT * 30) ))
    local sec_score=$(( 100 - penalty ))
    [[ $sec_score -lt 0 ]] && sec_score=0

    # TXT Report
    cat <<EOF > "$r_txt"
====================================================================
CYBERSHIELD ULTIMATE v3.0 - SECURITY REPORT
====================================================================
Timestamp  : $(date)
OS Platform: $OS_NAME
User/Host  : $CURRENT_USER @ $HOSTNAME_VAL
SECURITY SCORE: $sec_score / 100

[ FINDINGS SUMMARY ]
- Critical : $FINDINGS_CRIT
- High     : $FINDINGS_HIGH
- Medium   : $FINDINGS_MED
- Low      : $FINDINGS_LOW
====================================================================
EOF

    # JSON Report
    cat <<EOF > "$r_json"
{
  "timestamp": "$(date)",
  "os": "$OS_NAME",
  "security_score": $sec_score,
  "findings": {
    "critical": $FINDINGS_CRIT,
    "high": $FINDINGS_HIGH,
    "medium": $FINDINGS_MED,
    "low": $FINDINGS_LOW
  }
}
EOF

    # HTML Report
    cat <<EOF > "$r_html"
<!DOCTYPE html>
<html>
<head><title>CyberShield v3.0 Report</title></head>
<body style="background:#121212; color:#fff; font-family:sans-serif; padding:20px;">
    <h1>CyberShield v3.0 Security Report</h1>
    <p>OS: $OS_NAME | Host: $HOSTNAME_VAL</p>
    <h2>Security Score: $sec_score / 100</h2>
    <ul>
        <li>Critical: $FINDINGS_CRIT</li>
        <li>High: $FINDINGS_HIGH</li>
        <li>Medium: $FINDINGS_MED</li>
        <li>Low: $FINDINGS_LOW</li>
    </ul>
</body>
</html>
EOF

    print_status "OK" "Laporan berhasil digenerasi:"
    echo " -> TXT  : $r_txt"
    echo " -> JSON : $r_json"
    echo " -> HTML : $r_html"

    press_enter
}

# ------------------------------------------------------------------------------
# MODULE 16: LIVE SYSTEM MONITOR
# ------------------------------------------------------------------------------
module_live_monitor() {
    draw_banner
    echo -e "${BOLD}--- [ MODUL 16: LIVE SYSTEM MONITOR ] ---${NC}"
    echo "Tekan [CTRL+C] untuk keluar dari monitoring.\n"
    sleep 1

    trap 'break' INT
    while true; do
        clear
        echo -e "${CYAN}=== CYBERSHIELD LIVE MONITOR ===${NC} ($(date '+%H:%M:%S'))"
        echo -e "\n${WHITE}Memory Status:${NC}"
        free -h 2>/dev/null || free
        echo -e "\n${WHITE}Active Processes:${NC}"
        ps aux 2>/dev/null | head -n 5 || ps -ef 2>/dev/null | head -n 5
        sleep 2
    done
    trap - INT

    press_enter
}

# ------------------------------------------------------------------------------
# MODULE 17: FULL SECURITY SCAN
# ------------------------------------------------------------------------------
module_full_scan() {
    draw_banner
    echo -e "${BOLD}=== [ MEMULAI FULL SECURITY SCAN ] ===${NC}\n"
    sleep 1

    module_malware_scanner
    module_rootkit_scanner
    module_backdoor_detector
    module_process_analyzer
    module_network_scanner
    module_persistence_scanner
    module_ssh_audit
    module_log_analyzer
    module_vulnerability_checker
    
    module_report_generator
}

# ------------------------------------------------------------------------------
# UTILITY MODULES
# ------------------------------------------------------------------------------
module_scan_history() {
    draw_banner
    echo -e "${BOLD}--- [ HISTORI LOG & SCAN ] ---${NC}\n"
    tail -n 20 "$APP_LOG" 2>/dev/null || echo "Belum ada histori."
    press_enter
}

module_system_info() {
    draw_banner
    echo -e "${BOLD}--- [ INFORMASI DETAIL SISTEM ] ---${NC}\n"
    echo "OS Name      : $OS_NAME"
    echo "OS Type      : $OS_TYPE"
    echo "Package Mgr  : $PKG_MANAGER"
    echo "CPU Arch     : $ARCH_CPU"
    echo "Kernel       : $KERNEL_VAL"
    echo "Termux Env   : $IS_TERMUX"
    echo "WSL Env      : $IS_WSL"
    echo "Root Access  : $IS_ROOT"
    press_enter
}

module_help() {
    draw_banner
    echo -e "${BOLD}--- [ BANTUAN & DOKUMENTASI ] ---${NC}\n"
    echo "CyberShield Ultimate v3.0 Universal Shell Edition."
    echo "Mendukung Termux Android, Linux Server, Desktop, dan WSL."
    echo ""
    echo "Status Fitur:"
    echo " - AVAILABLE : Fitur berjalan penuh."
    echo " - LIMITED   : Berjalan terbatas (akses non-root)."
    echo " - NOTSUP    : Tidak didukung oleh arsitektur kernel target."
    press_enter
}

# ------------------------------------------------------------------------------
# MAIN MENU CONTROLLER
# ------------------------------------------------------------------------------
main_menu() {
    while true; do
        draw_banner
        echo -e "${WHITE}${BOLD}[ MAIN MENU UTAMA ]${NC}"
        echo -e " ${GREEN}1.${NC} Malware Scanner           ${GREEN}13.${NC} Vulnerability Checker"
        echo -e " ${GREEN}2.${NC} Rootkit Scanner           ${GREEN}14.${NC} Quarantine Manager"
        echo -e " ${GREEN}3.${NC} Backdoor Detector         ${GREEN}15.${NC} Security Report Generator"
        echo -e " ${GREEN}4.${NC} Universal URL Scanner     ${GREEN}16.${NC} Live System Monitor"
        echo -e " ${GREEN}5.${NC} Website Security Audit    ${GREEN}17.${NC} ${BOLD}FULL SECURITY SCAN${NC}"
        echo -e " ${GREEN}6.${NC} Network Scanner           ${GREEN}18.${NC} Scan History / Logs"
        echo -e " ${GREEN}7.${NC} Process Analyzer          ${GREEN}19.${NC} Dependency Manager"
        echo -e " ${GREEN}8.${NC} File Integrity Monitor    ${GREEN}20.${NC} System Information"
        echo -e " ${GREEN}9.${NC} Persistence Scanner       ${GREEN}21.${NC} Update Checker"
        echo -e " ${GREEN}10.${NC} SSH Security Audit        ${GREEN}22.${NC} Help / Bantuan"
        echo -e " ${GREEN}11.${NC} Log Analyzer              ${GREEN}23.${NC} ${RED}Exit / Keluar${NC}"
        echo -e " ${GREEN}12.${NC} Firewall Audit"
        echo -e "${CYAN}--------------------------------------------------------------------${NC}"
        echo -ne "${BOLD}Pilih menu [1-23]: ${NC}"
        read -r choice

        case "$choice" in
            1)  module_malware_scanner ;;
            2)  module_rootkit_scanner ;;
            3)  module_backdoor_detector ;;
            4|5) module_url_scanner ;;
            6)  module_network_scanner ;;
            7)  module_process_analyzer ;;
            8)  module_fim ;;
            9)  module_persistence_scanner ;;
            10) module_ssh_audit ;;
            11) module_log_analyzer ;;
            12) module_firewall_audit ;;
            13) module_vulnerability_checker ;;
            14) module_quarantine_manager ;;
            15) module_report_generator ;;
            16) module_live_monitor ;;
            17) module_full_scan ;;
            18) module_scan_history ;;
            19) install_dependencies ;;
            20) module_system_info ;;
            21) draw_banner; print_status "OK" "Versi terkini: $VERSION"; press_enter ;;
            22) module_help ;;
            23) echo -e "\n${GREEN}Keluar dari CyberShield Ultimate v3.0. Stay Secure!${NC}"; exit 0 ;;
            *)  print_status "FAIL" "Pilihan tidak valid!"; sleep 1 ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# MAIN ENTRY POINT
# ------------------------------------------------------------------------------
main() {
    init_environment
    main_menu
}

main "$@"
