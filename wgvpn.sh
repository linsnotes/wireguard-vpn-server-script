#!/bin/bash

WG_DIR="/etc/wireguard"
CLIENTS_DIR="${WG_DIR}/clients"
SERVER_CONFIG="${WG_DIR}/wg0.conf"
SERVER_PRIVATE_KEY=""
SERVER_PUBLIC_KEY=""
SERVER_IP="asuscomm.com" # Change this to your server Domain name or DDNS address or server IP
SERVER_PORT="51820" # Change this to your WireGuard server port
WG_INTERFACE="wg0"
NET_INTERFACE="" # Change this to your network interface
LOCAL_NETWORK="192.168.1.0/24" # Change this to your local network
escaped_local_network=$(echo "${LOCAL_NETWORK}" | sed 's/[&/\]/\\&/g')
CLIENT_IP=""

# Ensure the script is run with root privileges
if [ "$EUID" -ne 0 ]; then
    echo "Permission denied: Please run this script as root or with sudo."
    exit 1
fi

validate_client_name() {
    local client_name=$1
    if [[ -z "$client_name" || ! "$client_name" =~ ^[a-zA-Z0-9_]+$ ]]; then
        echo "Invalid client name: $client_name. Client name cannot contain spaces. Only alphanumeric characters and underscores are allowed."
        exit 1
    fi
}

check_permissions() {
    local file=$1
    if [ ! -w "$file" ]; then
        echo "Permission denied: Cannot write to $file"
        exit 1
    fi
}

create_wg0_conf() {
    # Check if the private and public key files exist, if not, create them
    if [ ! -f "${WG_DIR}/server-private.key" ]; then
        wg genkey | tee "${WG_DIR}/server-private.key" | wg pubkey > "${WG_DIR}/server-public.key"
        echo "Server private and public keys generated."
    fi

    # Read the generated keys
    SERVER_PRIVATE_KEY=$(cat "${WG_DIR}/server-private.key")
    SERVER_PUBLIC_KEY=$(cat "${WG_DIR}/server-public.key")

    # Check if the wg0.conf file does not exist or is empty
    if [ ! -f "${SERVER_CONFIG}" ] || [ ! -s "${SERVER_CONFIG}" ]; then
        cat > "${SERVER_CONFIG}" << EOL
[Interface]
Address = 10.0.0.1/24
ListenPort = ${SERVER_PORT}
PrivateKey = ${SERVER_PRIVATE_KEY}
PostUp = sysctl -w net.ipv4.ip_forward=1; iptables -A INPUT -p udp --dport ${SERVER_PORT} -j ACCEPT; iptables -A FORWARD -i wg0 -d ${LOCAL_NETWORK} -j REJECT; iptables -A FORWARD -i wg0 -o ${NET_INTERFACE} -j ACCEPT; iptables -A FORWARD -i ${NET_INTERFACE} -o wg0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT; iptables -t nat -A POSTROUTING -o ${NET_INTERFACE} -j MASQUERADE
PostDown = sysctl -w net.ipv4.ip_forward=0; iptables -D INPUT -p udp --dport ${SERVER_PORT} -j ACCEPT; iptables -D FORWARD -i wg0 -d ${LOCAL_NETWORK} -j REJECT; iptables -D FORWARD -i wg0 -o ${NET_INTERFACE} -j ACCEPT; iptables -D FORWARD -i ${NET_INTERFACE} -o wg0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT; iptables -t nat -D POSTROUTING -o ${NET_INTERFACE} -j MASQUERADE
EOL
        echo "Created ${SERVER_CONFIG}"
    else
        echo "${SERVER_CONFIG} already exists."
    fi
    # Bring up the WireGuard interface
    sudo wg-quick up wg0

}

initialize_environment() {
    local group_name="vpnadmin"
    # Check if SERVER_PUBLIC_KEY, SERVER_IP, SERVER_PORT, SERVER_CONFIG, and WG_INTERFACE are set
    local missing_vars=()

    [ -z "${SERVER_IP}" ] && missing_vars+=("SERVER_IP\n")
    [ -z "${SERVER_PORT}" ] && missing_vars+=("SERVER_PORT\n")
    [ -z "${WG_INTERFACE}" ] && missing_vars+=("WG_INTERFACE\n")
    [ -z "${NET_INTERFACE}" ] && missing_vars+=("NET_INTERFACE\n")
    [ -z "${LOCAL_NETWORK}" ] && missing_vars+=("LOCAL_NETWORK\n")

    if [ ${#missing_vars[@]} -ne 0 ]; then
        echo -e "Error: The following required variables are not set:\n${missing_vars[*]}"
        echo "Please change or set the necessary variables in the script and then run it again."
        exit 1
    fi

    # Check if WireGuard is installed, if not, install it
    if ! command -v wg &> /dev/null; then
        echo "WireGuard is not installed. Installing..."
        apt-get update
        if apt-get install -y wireguard; then
            echo "WireGuard has been installed."
        else
            echo "Error installing WireGuard. Please check your package manager and try again."
            exit 1
        fi
    else
        echo "WireGuard is already installed."
    fi

    # Create vpnadmin group if it doesn't exist
    if ! getent group "$group_name" > /dev/null; then
        groupadd "$group_name"
        echo "Group '$group_name' has been created."
    else
        echo "Group '$group_name' already exists."
    fi

    # Add the current user to the vpnadmin group
    # Get the original user who ran the script with sudo
    local original_user="$SUDO_USER"

    # Check if original_user is empty
    if [ -z "$original_user" ]; then
    echo "Unable to determine the original user."
    exit 1
    fi
    # Add non-root user to the vpnadmin group
    if [ "$original_user" != "root" ]; then
    usermod -aG "$group_name" "$original_user"
    echo "User '$original_user' has been added to the '$group_name' group."
    fi

    # Create wg0.conf if it doesn't exist
    create_wg0_conf

    # Ensure necessary directories exist
    mkdir -p "${CLIENTS_DIR}"
    echo "Directory '${CLIENTS_DIR}' exists or has been created."

    # Set ownership and permissions for WireGuard directories
    chown -R root:"$group_name" "${WG_DIR}"
    echo "Ownership of '${WG_DIR}' and its subdirectories has been set to 'root:$group_name'."

    chmod -R 770 "${WG_DIR}"
    echo "Permissions of '${WG_DIR}' and its subdirectories have been set to '770' (rwxrwx---)."

    # Check if qrencode is installed, if not install it
    if ! command -v qrencode &> /dev/null; then
        echo "qrencode is not installed. Installing..."
        apt-get update
        apt-get install -y qrencode
        echo "qrencode has been installed."
    else
        echo "qrencode is already installed."
    fi

}


get_next_ip() {
    # Ensure SERVER_CONFIG exist.

    if [ ! -f "${SERVER_CONFIG}" ]; then
        echo "Error: Configuration file 'wg0.conf' not found in '/etc/wireguard'."
        return 1
    fi

    # Extract used IPs from the configuration file
    local used_ips
    used_ips=$(sudo grep 'AllowedIPs' "${SERVER_CONFIG}" | awk '{print $3}' | cut -d '/' -f 1 | sort -V)

    # Initialize starting IP address
    local base_ip="10.0.0."
    local start=2
    local end=254

    # Check if used_ips is empty
    if [ -z "${used_ips}" ]; then
        echo "${base_ip}${start}"
        return 0
    fi

    # Iterate through the possible IP range to find the first unused IP
    local next_ip
    for ((i=start; i<=end; i++)); do
        next_ip="${base_ip}${i}"
        if ! grep -qw "${next_ip}" <<< "${used_ips}"; then
            echo "${next_ip}"
            return 0
        fi
    done

    echo "Error: No more IP addresses available in the subnet."
    return 1
}

qrcode() {
    local client_name=$1
    local client_config="${CLIENTS_DIR}/${client_name}.conf"

    # Generate QR code
    if ! type qrencode >/dev/null 2>&1; then
        echo "Error: qrencode is not installed."
        return 1
    fi
    echo "${client_config} QR code:" 
    qrencode -t ansiutf8 < "${client_config}"
}

generate_client() {
    local client_name=$1
    local client_config="${CLIENTS_DIR}/${client_name}.conf"
    echo "Creating client '$client_name'......"

    # Check if CLIENTS_DIR is defined and exists
    if [ -z "${CLIENTS_DIR}" ] || [ ! -d "${CLIENTS_DIR}" ]; then
        echo "Error: CLIENTS_DIR is not defined or does not exist."
        return 1
    fi

    # Generate client keys
    local client_private_key=$(wg genkey) || { echo "Error generating private key"; return 1; }
    local client_public_key=$(echo "${client_private_key}" | wg pubkey) || { echo "Error generating public key"; return 1; }
    local client_address="$(get_next_ip)/32"

    # Create client configuration
    cat > "${client_config}" << EOL
[Interface]
PrivateKey = ${client_private_key}
Address = ${client_address}
DNS = 1.1.1.1

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
Endpoint = ${SERVER_IP}:${SERVER_PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOL

    # Check if the configuration file was created successfully
    if [ ! -f "${client_config}" ]; then
        echo "Error creating client configuration file in '/etc/wireguard/clients'."
        return 1
    else
        echo "Client configuration created at '${client_config}'"
    fi

    # Set correct permissions for the client configuration file
    chown root:vpnadmin "${client_config}" || { echo "Error setting file ownwer and group permissions"; return 1; }
    chmod -R 770 "${client_config}" || { echo "Error setting file file permission"; return 1; }
    # Add client to server configuration with a comment
    echo -e "\n# ${client_name}\n[Peer]\nPublicKey = ${client_public_key}\nAllowedIPs = ${client_address}" | tee -a "${SERVER_CONFIG}" > /dev/null || { echo "Error updating server configuration"; return 1; }

    # Remove multiple empty lines and keep only one
    sed -i '/^$/N;/\n$/D' "${SERVER_CONFIG}"

    # Apply new configuration
    wg set ${WG_INTERFACE} peer ${client_public_key} allowed-ips ${client_address} || { echo "Error applying configuration"; return 1; }

    # Checking for qrencode installation
    type qrencode >/dev/null 2>&1 || { echo "Error: qrencode is not installed."; return 1; }

    # Generate QR code
    qrencode -t ansiutf8 < "${client_config}"

    echo "Client configuration created at: '${client_config}'"
}

delete_client() {
    local client_name=$1
    local client_config="${CLIENTS_DIR}/${client_name}.conf"

    if [ ! -f "${client_config}" ]; then
        echo "Client configuration not found: ${client_config}"
        exit 1
    fi

    local client_public_key=$(grep PublicKey "${client_config}" | cut -d " " -f 3)

    # Remove client from server configuration using the updated comment marker
    sed -i "/# ${client_name}/,/^\s*$/d" "${SERVER_CONFIG}" || { echo "Error updating server configuration"; exit 1; }

    # Apply new configuration to remove the client
    wg set ${WG_INTERFACE} peer ${client_public_key} remove || { echo "Error removing client from WireGuard"; exit 1; }

    # Remove client configuration file
    rm -f "${client_config}"

    echo "Client configuration deleted: '${client_config}'"
}

list_clients() {
    echo "Existing clients:"
    grep -oP '# \K\S+' "${SERVER_CONFIG}" | sed 's/^# //'
}

get_client_address() {
    local client_name=$1

    if [ -z "${client_name}" ]; then
        echo "Error: No client name provided."
        return 1
    fi

    # Fetch client information
    local client_info=$(sudo grep -A 3 -E "^# ${client_name}\b" "${SERVER_CONFIG}")

    local grep_exit_code=$?
    if [ ${grep_exit_code} -ne 0 ]; then
        echo "Error: grep command failed. Failed to fetch client information."
        return 1
    fi

    if [ -z "${client_info}" ]; then
        echo "Error: Client info for ${client_name} not found."
        return 1
    fi

    # Extract client address
    local client_address=$(echo "${client_info}" | grep 'AllowedIPs' | awk '{print $NF}' | cut -d '/' -f 1)

    if [ -z "${client_address}" ]; then
        echo "Error: Client address for ${client_name} not found."
        return 1
    fi
    # Assign the address to a global variable without printing
    CLIENT_IP="${client_address}"
    return 0
}

allow_client() {
    local client_name=$1
    get_client_address "${client_name}"

    if [ -z "${CLIENT_IP}" ]; then
        echo "Error: Client address not found for ${client_name}."
        return 1
    fi


    # Check if the rule already exists
    if grep -q "iptables -A FORWARD -i wg0 -s ${CLIENT_IP} -d ${escaped_local_network} -j ACCEPT;" "${SERVER_CONFIG}"; then
        echo "Access to the local network is already ALLOWED for '${client_name}' with address ${CLIENT_IP}."
        return 0
    fi

    # Bring down the wireguard to remove iptables rules.
    wg-quick down wg0
    echo "Wireguard Down"

    # Edit local network access rules
    sed -i "s|iptables -A INPUT -p udp --dport ${SERVER_PORT} -j ACCEPT;|iptables -A INPUT -p udp --dport ${SERVER_PORT} -j ACCEPT; iptables -A FORWARD -i wg0 -s ${CLIENT_IP} -d ${escaped_local_network} -j ACCEPT;|" "${SERVER_CONFIG}"
    sed -i "s|iptables -D INPUT -p udp --dport ${SERVER_PORT} -j ACCEPT;|iptables -D INPUT -p udp --dport ${SERVER_PORT} -j ACCEPT; iptables -D FORWARD -i wg0 -s ${CLIENT_IP} -d ${escaped_local_network} -j ACCEPT;|" "${SERVER_CONFIG}"

    # Remove multiple empty lines and keep only one
    sed -i '/^$/N;/\n$/D' "${SERVER_CONFIG}"

    # Apply the updated WireGuard configuration and update iptables.
    wg-quick up wg0
    echo "Wireguard Up"
    echo "Access to the local network has been ALLOWED for'${client_name}' with address ${CLIENT_IP}"
}

deny_client() {
    local client_name=$1
    get_client_address "${client_name}"

    if [ $? -ne 0 ]; then
        echo "Error: Client address not found for ${client_name}."
        return 1
    fi

    # Bring down the wireguard to remove iptables rules.
    wg-quick down wg0
    echo "WireGuard Down"
    # Remove specific part of the local network access rules
    sed -i "s|iptables -A FORWARD -i wg0 -s ${CLIENT_IP} -d ${escaped_local_network} -j ACCEPT; ||" "${SERVER_CONFIG}"
    sed -i "s|iptables -D FORWARD -i wg0 -s ${CLIENT_IP} -d ${escaped_local_network} -j ACCEPT; ||" "${SERVER_CONFIG}"

    # Remove multiple empty lines and keep only one
    sed -i '/^$/N;/\n$/D' "${SERVER_CONFIG}"

    # Apply the updated WireGuard configuration and update iptables.
    wg-quick up wg0
    echo "WireGuard Up"
    echo "Access to the local network has been BLOCKED for'${client_name}' with address ${CLIENT_IP}"
}


if [[ "$#" -ne 2 ]]; then
    echo "Usage: $0 {add|delete|list|local} <client_name>"
    echo "To add a new client: $0 add <client_name>"
    echo "to delete a existing client: $0 delete <client_name>"
    echo "to list clients: $0 list all"
    exit 1
fi

COMMAND=$1
CLIENT_NAME=$2

validate_client_name "$CLIENT_NAME"

case "$COMMAND" in
    add)
        initialize_environment
        check_permissions "$SERVER_CONFIG"
        check_permissions "$CLIENTS_DIR"
        generate_client "$CLIENT_NAME"
        ;;
    delete)
        check_permissions "$SERVER_CONFIG"
        check_permissions "$CLIENTS_DIR"
        deny_client "$CLIENT_NAME"
        delete_client "$CLIENT_NAME"
        ;;
    list)
        if [[ "$CLIENT_NAME" == "all" ]]; then
            list_clients
        else
            echo "Usage: to list all clients '$0 list all'"
            exit 1
        fi
        ;;
    allow)
        allow_client "$CLIENT_NAME"
        ;;
    deny)
        deny_client "$CLIENT_NAME"
        ;;
    qr)
        qrcode "$CLIENT_NAME"
        ;;
    *)
        echo "Usage: $0 {add|delete|list|allow|deny|qr} <client_name>"
        exit 1
        ;;
esac
