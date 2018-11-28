#!/usr/bin/env bash

set -euo pipefail
test ! -z ${DEBUG+x} && set -x

WORKDIR=$(realpath $(dirname $0))

cd ${WORKDIR}

# ==============================================================================

STAT_CMD=stat
DATE_CMD=date
ECHO_CMD=echo
BASE64_CMD=base64

log() {
    ${ECHO_CMD} -e "$(${DATE_CMD} --utc +%FT%T.%3NZ) $1"
}

log_info() {
    log " [INFO ] \e[92m$1\e[0m"
}

log_warn() {
    log " [WARN ] \e[93m$1\e[0m"
}

log_error() {
    log " [ERROR] \e[91m$1\e[0m"
}

# ==============================================================================
# base system
# ==============================================================================

self_update() {
    log_info "Checking for self updates..."
    if [[ ! -d .git ]]; then
	log_error "YO! where is your git repo ?"
        exit 1
    fi
    if [[ -n $(which git) ]]; then
        if [[ -z "$(git diff)" ]]; then
            git fetch origin
            if [[ "$(git log HEAD..origin/master --oneline)" != "" ]]; then
                log_info "Self updating..."
                git merge origin/master
                log_info "Self update done. Run $0 again."
                exit 0
            fi
            log_info "Up to date."
        else
            log_warn "Local changes detected, skipping self-update."
        fi
    else
        # skip if sys was just copied over to the new machine
        log_warn "Git not installed, skipping self-update."
    fi
}

check_root_password() {
    if os_linux; then
        log_info "Checking root password..."
        if [[ "$(sudo passwd -S root | awk '{print $2}')" == "P" ]]; then
            log_info "Root password is enabled, locking now..."
            sudo passwd -l root
        fi
        log_info "Root password is locked."
    fi
}

check_reboot_required() {
    if os_ubuntu; then
        if [[ -f /var/run/reboot-required ]]; then
            log_info "
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!!                                                 !!!
!!!        /var/run/reboot-required says            !!!
!!!        *** System restart required ***          !!!
!!!                                                 !!!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
            read -n 1 -p "Press any key to continue or Ctrl+C to exit."
        fi
    fi
}

apt_update_all() {
    log_info "Checking for APT packages updates..."
    sudo apt update
    sudo apt dist-upgrade -y
    sudo apt autoremove -y
    log_info "APT packages up to date."
}

apt_install_package() {
    PACKAGE=$1
    sudo apt install ${PACKAGE} -y
}

apt_package_installed() {
    PACKAGE=$1
    dpkg -s ${PACKAGE} &>/dev/null && return 0 || return 1
}

check_install_apt_package() {
    PACKAGE=$1
    LABEL=${2:-$1}
    log_info "Checking ${LABEL}..."
    if ! apt_package_installed ${PACKAGE}; then
        log_info "Installing ${LABEL}..."
        apt_install_package ${PACKAGE}
    fi
    log_info "${LABEL} is installed."
}

check_install_download_deb() {
    PACKAGE=$1
    LABEL=$2
    URL=$3
    LOCAL_FILE=$4
    log_info "Checking ${LABEL}..."
    if ! apt_package_installed ${PACKAGE}; then
        log_info "Installing ${LABEL}..."
        wget -c ${URL} -O ${LOCAL_FILE}
        sudo apt install -y ${LOCAL_FILE}
        rm -f ${LOCAL_FILE}
    fi
    log_info "${LABEL} is installed."
}

snap_update_all() {
    log_info "Checking for snap packages updates..."
    sudo snap refresh
    log_info "snap packages up to date."
}

snap_install_package() {
    PACKAGE=$1
    OPTS=${2:-}
    sudo snap install ${PACKAGE} ${OPTS}
}

snap_package_installed() {
    PACKAGE=$1
    INSTALLED=$(sudo snap list | grep "^${PACKAGE} " 2>/dev/null)
    test -n "${INSTALLED}" && return 0 || return 1
}

check_install_snap_package() {
    PACKAGE=$1
    LABEL=${2:-$1}
    OPTS=${3:-}
    log_info "Checking ${LABEL}..."
    if ! snap_package_installed ${PACKAGE}; then
        log_info "Installing ${LABEL}..."
        snap_install_package ${PACKAGE} ${OPTS}
    fi
    log_info "${LABEL} is installed."
}

install_coreutils() {
    check_install_apt_package curl "cURL"
}

install_ssh() {
    check_install_apt_package openssh-client "SSH Client"
    check_install_apt_package openssh-server "SSH Server"
    check_install_apt_package autossh "auto SSH"
}

install_rsync() {
    check_install_apt_package rsync Rsync
}

install_git() {
    check_install_apt_package git Git
    check_install_apt_package gitk GitK
}

# ==============================================================================
# personal config
# ==============================================================================

check_permissions() {
    MOD=$1
    FILE=$2
    if [[ "$(${STAT_CMD} -c %a ${FILE})" != "${MOD}" ]]; then
        chmod "${MOD}" "${FILE}"
    fi
}

install_file() {
    SOURCE=$1
    DESTINATION=$2
    MOD=$3
    if [[ ! -f ${DESTINATION} ]]; then
        if [[ ${SOURCE} == *.gpg ]] && [[ ${DESTINATION} != *.gpg ]]; then
            gpg_decrypt_file ${SOURCE} ${DESTINATION}
        elif [[ ${SOURCE} != *.gpg ]] && [[ ${DESTINATION} == *.gpg ]]; then
            gpg_encrypt_file ${SOURCE} ${DESTINATION}
        else
            cp -f ${SOURCE} ${DESTINATION}
        fi
    fi
    check_permissions ${MOD} ${DESTINATION}
}

check_ssh_id() {
    SERVER=$1
    ssh -o PasswordAuthentication=no ${SERVER} exit &>/dev/null || ssh-copy-id ${SERVER}
}

add_line() {
    FILE=$1
    LINE=$2
    grep -q -F "${LINE}" "${FILE}" || echo "${LINE}" >>"${FILE}"
}

sudo_add_line() {
    FILE=$1
    LINE=$2
    sudo grep -q -F "${LINE}" "${FILE}" || echo "${LINE}" | sudo tee -a "${FILE}"
}

add_zshrc_line() {
    LINE=$1
    add_line "${HOME}/.zshrc" "${LINE}"
}

install_zsh() {
    log_info "Installing zsh..."
    check_install_apt_package zsh Zsh
    log_info "Zsh installed."
}

configure_git() {
    log_info "Configuring git..."
    git config --global user.name "Alexei Guevara"
    git config --global user.email alguevara@ebay.com
    git config --global branch.autosetuprebase always
    git config --global pull.rebase true
    git config --global core.editor vim
    git config --global color.ui true
    git config --global push.default simple
    log_info "git configured."
}

install_i3() {
    check_install_apt_package i3 i3
}

install_ubuntu_restricted_extras() {
    check_install_apt_package ubuntu-restricted-extras "Ubuntu Restricted Extras"
}

# ==============================================================================
# system/desktop tools
# ==============================================================================

install_chromium() {
    check_install_apt_package chromium-browser Chromium
}

# ==============================================================================
# dev packages
# ==============================================================================

install_docker() {
    log_info "Checking Docker..."
    if ! apt_package_installed docker-ce; then
        log_info "Installing Docker..."
        sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
        # sudo add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        # sudo add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) edge"
        # sudo add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable"
        sudo add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic edge"
        sudo apt update
        apt_install_package docker-ce
        if [[ -z "$(grep docker /etc/group)" ]]; then
            sudo groupadd docker
        fi
        sudo usermod -aG docker ${USER}
        # Using overlay2 FS instead of default older AUFS
        # Log files rotation
        # Exposing Docker metrics to prometheus
        cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "storage-driver": "overlay2",
  "experimental": true
}
EOF

        sudo systemctl enable docker
        log_info "
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!                                                 !!!
    !!!        YOU NEED TO RESTART TO USE DOCKER        !!!
    !!!                                                 !!!
    !!!        RESTART AND RUN AGAIN                    !!!
    !!!                                                 !!!
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        exit 0
    fi
    log_info "Docker is installed."
}

install_docker_compose() {
    log_info "Checking Docker Compose..."
    if [[ -z "$(which docker-compose)" ]]; then
        log_info "Installing Docker Compose..."
	sudo curl -L "https://github.com/docker/compose/releases/download/1.22.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
	sudo chmod +x /usr/local/bin/docker-compose
    fi
    log_info "Docker Compose is installed."
}

install_cli_utils() {
    check_install_apt_package tmux tmux
    check_install_apt_package jq jq
    check_install_apt_package httpie HTTPie
}

install_ag() {
    check_install_apt_package silversearcher-ag "Silver Searcher"
}

install_vim() {
    check_install_apt_package vim "Vim"
}

configure_xrandr() {
    log_info "Configuring xrandr..."
    add_zshrc_line "# xrandr"
    add_zshrc_line "xrandr_hires() { xrandr --output Virtual1 --primary --mode 1920x1200 ; }"
    log_info "Xrandr configured."
}

clone_repo() {
    URL=$1
    DESTINATION=$2
    PARENT_DIR=$(dirname ${DESTINATION})
    if [[ ! -d ${PARENT_DIR} ]]; then
        mkdir -p ${PARENT_DIR}
    fi
    if [[ ! -d ${DESTINATION} ]]; then
        git clone $URL $DESTINATION
    fi
}

download_display_link() {
    local dlfileid=$(echo $dlurl | perl -pe '($_)=/.+\?id=(\d+)/')

    echo -en "\nPlease read the Software License Agreement\navailable at $dlurl\nand accept here: [Y]es or [N]o: "
    read ACCEPT
    case $ACCEPT in
        y*|Y*)
            echo -e "\nDownloading DisplayLink Ubuntu driver:\n"
            wget -O ./tmp/DisplayLink_Ubuntu_${version}.zip "--post-data=fileId=$dlfileid&accept_submit=Accept" $dlurl
            # make sure we got the file downloadet before continueing
            if [ $? -ne 0 ]
            then
                echo -e "\nUnable to download Displaylink driver\n"
                exit
            fi
            ;;
        *)
            echo "Can't download the driver without accepting the license agreement!"
            exit 1
            ;;
    esac
}

install_display_link() {
    log_info "Installing DisplayLink..."

    log_info "Installing DisplayLink deps..."

    check_install_apt_package unzip "unzip"
    check_install_apt_package linux-headers-$(uname -r) "Linux Headers"
    check_install_apt_package dkms "DKMS"
    check_install_apt_package lsb-release "lsb-release"
    check_install_apt_package linux-source "linux-source"

    log_info "DisplayLink deps are installed."

    local version=`wget -q -O - https://www.displaylink.com/downloads/ubuntu | grep "download-version" | head -n 1 | perl -pe '($_)=/([0-9]+([.][0-9]+)+)/'`
    # define download url to be the correct version
    local dlurl="https://www.displaylink.com/"`wget -q -O - https://www.displaylink.com/downloads/ubuntu | grep "download-link" | head -n 1 | perl -pe '($_)=/<a href="\/([^"]+)"[^>]+class="download-link"/'`
    local driver_dir=./tmp/$version

    download_display_link

    unzip -d $driver_dir ./tmp/DisplayLink_Ubuntu_${version}.zip

    sudo ./$driver_dir/displaylink-driver-4.4.24.run

    log_info "DisplayLink is installed."
}

install_nvidia_driver() {
    check_install_apt_package nvidia-driver-390 "NVidia Driver 390"
}

install_nvidia_docker() {
    log_info "Installing NVidia Docker..."
    curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | \
	    sudo apt-key add -
    distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
    curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | \
	    sudo tee /etc/apt/sources.list.d/nvidia-docker.list
    sudo apt-get -y update
    check_install_apt_package nvidia-docker2 "NVidia Docker v2"
    sudo pkill -SIGHUP dockerd
    log_info "NVidia Docker Installed."
}


disabled_wakeup_from_kb_mouse() {
   cp /proc/acpi/wakeup ~/tmp/
   sed -i 's/enabled   pci:0000:00:14.0/disabled   pci:0000:00:14.0/g' ~/tmp/wakeup
   sudo cp ~/tmp/wakeup /proc/acpi/
}

suspend_on_power_button_press() {
    sudo_add_line /etc/systemd/logind.conf "HandlePowerKey=suspend"
}

# ==============================================================================

install() {

    # base system
    self_update
    apt_update_all
    snap_update_all
    check_reboot_required
    check_root_password
    install_coreutils
    install_ssh
    install_rsync
    install_git

    # hardware setup
    disabled_wakeup_from_kb_mouse
    suspend_on_power_button_press

    # personal config
    install_zsh

    install_i3
    install_vim
    #configure_xrandr
    install_ubuntu_restricted_extras

    # system/desktop tools
    install_chromium
    # dev packages
    install_docker
    install_docker_compose
    install_cli_utils
    install_ag

    #install_display_link
    install_nvidia_driver
    install_nvidia_docker

    log_info "Great Success!"

}

main() {

    OPERATION=$1

    case ${OPERATION} in
        install)
            install
            ;;
        *)
            echo "
Usage:
    ./sys.sh install         check/install everything
"
            exit 1
            ;;
    esac

}

if [ "${EUID}" == "0" ]; then
    echo "Naughty naughty!"
    exit 1
fi

main ${1:-}
