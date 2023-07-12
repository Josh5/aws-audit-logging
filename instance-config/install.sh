#!/usr/bin/env bash
###
# File: install.sh
# Project: instance-config
# File Created: Wednesday, 12th July 2023 10:14:53 am
# Author: Josh.5 (jsunnex@gmail.com)
# -----
# Last Modified: Wednesday, 12th July 2023 4:52:33 pm
# Modified By: Josh.5 (jsunnex@gmail.com)
###
#
#   RUN:
#       curl -L https://raw.githubusercontent.com/Josh5/aws-audit-logging/master/instance-config/install.sh | sh
#
###
set -euo pipefail

_script_path=""
if [[ -n "${BASH_SOURCE:-}" ]]; then
    _script_path=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
fi

function flexi_downloader {
    local _source=${1}
    local _destination=${2}
    if command -v wget &>/dev/null; then
        wget -O "${_destination}" "${_source}"
    elif command -v curl &>/dev/null; then
        curl --location --remote-header-name --output "${_destination}" "${_source}"
    else
        echo "ERROR! You need either curl or wget installed to run this script." >&2
        exit 1
    fi
}

# Fetch latest repo from Git remote repository. This will be required for all files.
function fetch_data {
    echo "**** Fetching instance-config ****"
    pushd "${@}" &>/dev/null || { echo "ERROR! Failed to change directory." >&2; exit 1; }
    flexi_downloader "https://github.com/Josh5/aws-audit-logging/archive/refs/heads/master.tar.gz" "./master.tar.gz"
    tar -xvf master.tar.gz --strip-components=1
    popd &>/dev/null || { echo "ERROR! Failed to change back to the previous directory." >&2; exit 1; }
    echo "DONE"
    echo
}

#  ____       _                    _             _ _ _      _ 
# / ___|  ___| |_ _   _ _ __      / \  _   _  __| (_) |_ __| |
# \___ \ / _ \ __| | | | '_ \    / _ \| | | |/ _` | | __/ _` |
#  ___) |  __/ |_| |_| | |_) |  / ___ \ |_| | (_| | | || (_| |
# |____/ \___|\__|\__,_| .__/  /_/   \_\__,_|\__,_|_|\__\__,_|
#                      |_|                                    
#
function setup_auditd {
    # Configure Auditd
    echo "**** Configuring Auditd ****"
    cp -rfv "${_script_path}/etc/audit/"* /etc/audit/
    echo "DONE"
    echo

    # -- Set Auditd to run on startup
    echo "**** Starting Auditd service ****"
    systemctl enable auditd
    systemctl restart auditd
    echo "DONE"
    echo
}

#  ____       _                 _____ _                  _     ____  _ _   
# / ___|  ___| |_ _   _ _ __   |  ___| |_   _  ___ _ __ | |_  | __ )(_) |_ 
# \___ \ / _ \ __| | | | '_ \  | |_  | | | | |/ _ \ '_ \| __| |  _ \| | __|
#  ___) |  __/ |_| |_| | |_) | |  _| | | |_| |  __/ | | | |_  | |_) | | |_ 
# |____/ \___|\__|\__,_| .__/  |_|   |_|\__,_|\___|_| |_|\__| |____/|_|\__|
#                      |_|                                                 
#
function setup_fluent_bit {
    # Install Fluent Bit
    echo "**** Installing Fluent Bit ****"
    curl https://raw.githubusercontent.com/fluent/fluent-bit/master/install.sh | sh
    echo "DONE"
    echo

    # Configure Fluent Bit
    echo "**** Configuring Fluent Bit ****"
    cp -rfv "${_script_path}/etc/fluent-bit/"* /etc/fluent-bit/

    # -- Configure the ID of this Fluent Bit installation
    echo "FLUENT_INSTALLATION_ID=${FLUENT_INSTALLATION_ID:-$HOSTNAME}" > /etc/sysconfig/fluent-bit
    chown root:root /etc/sysconfig/fluent-bit
    chmod 600 /etc/sysconfig/fluent-bit

    # -- Install configured plugins
    # ---- Logz.io
    if [[ -z "${LOGZ_IO_LICENSE_KEY:-}" || -z "${LOGZ_IO_LISTENER_URL:-}" ]]; then
        rm /etc/fluent-bit/outputs/logzio.conf
    else
        echo "  - Enabling Logz.io plugin for Fluent Bit"
        # ------ Download the plugin
        mkdir -p /etc/fluent-bit/plugin
        flexi_downloader "https://github.com/logzio/fluent-bit-logzio-output/raw/master/build/out_logzio-linux.so" "/etc/fluent-bit/plugins/out_logzio.so"
        # ------ Configure Fluent Bit to use the plugin
        sed -i "s|#\s*Path /etc/fluent-bit/plugins/out_logzio.so|Path /etc/fluent-bit/plugins/out_logzio.so|" /etc/fluent-bit/plugins.conf
        # ------ Configure the Fluent Bit service environment with the Logz.io license key
        if grep "LOGZ_IO_LICENSE_KEY" /etc/sysconfig/fluent-bit &>/dev/null; then
            echo "  - Reconfigure Logz.io plugin license key"
            sed -i "s|^LOGZ_IO_LICENSE_KEY=.*$|LOGZ_IO_LICENSE_KEY=${LOGZ_IO_LICENSE_KEY}|" /etc/sysconfig/fluent-bit
        else
            echo "  - Configure Logz.io plugin license key"
            echo "LOGZ_IO_LICENSE_KEY=${LOGZ_IO_LICENSE_KEY}" >> /etc/sysconfig/fluent-bit
        fi
        # ------ Configure the Fluent Bit service environment with the Logz.io listener URL
        if grep "LOGZ_IO_LISTENER_URL" /etc/sysconfig/fluent-bit &>/dev/null; then
            echo "  - Reconfigure Logz.io plugin listener URL"
            sed -i "s|^LOGZ_IO_LISTENER_URL=.*$|LOGZ_IO_LISTENER_URL=${LOGZ_IO_LISTENER_URL}|" /etc/sysconfig/fluent-bit
        else
            echo "  - Configure Logz.io plugin listener URL"
            echo "LOGZ_IO_LISTENER_URL=${LOGZ_IO_LISTENER_URL}" >> /etc/sysconfig/fluent-bit
        fi
    fi

    # -- Configure audit logging
    if [[ ! -e /var/log/audit/audit.log ]]; then
        rm /etc/fluent-bit/inputs/audit.conf
    else
        echo "  - Enabling Auditd input for Fluent Bit"
    fi

    # -- Configure monitor of sshd service logs
    if ! systemctl list-units --full -all | grep -Fq "sshd.service"; then
        rm /etc/fluent-bit/inputs/sshd.conf
    else
        echo "  - Enabling SSH Systemd service log monitoring input for Fluent Bit"
    fi

    # -- Configure monitor of docker service logs
    if ! systemctl list-units --full -all | grep -Fq "docker.service"; then
        rm /etc/fluent-bit/inputs/docker.conf
    else
        echo "  - Enabling SSH Systemd service log monitoring input for Fluent Bit"
    fi

    echo "DONE"
    echo

    # -- Set Fluent Bit to run on startup
    echo "**** Starting Fluent Bit service ****"
    systemctl enable fluent-bit
    systemctl restart fluent-bit
    echo "DONE"
    echo
}

# Fetch project and re-run script
if [[ ! -f "${_script_path}/.fetched" ]]; then
    _temp_dir=$(mktemp -d)
    fetch_data "${_temp_dir}"
    chmod +x "${_temp_dir}/instance-config/install.sh"
    # Ensure the script is run as root
    if [[ $(id -u) -gt 0 ]]; then
        _run_sudo=sudo
    fi
    ${_run_sudo:-} "${_temp_dir}/instance-config/install.sh"
    exit $?
elif [[ $(id -u) -gt 0 ]]; then
    ${_run_sudo:-} "${_script_path}/install.sh"
fi

# Run
# Configure Auditd
setup_auditd
# Install and confiure Fluent Bit
setup_fluent_bit

echo
echo "ALL DONE!"
echo
