#!/bin/bash

WG_DIR="/etc/wireguard"
CLIENTS_DIR="${WG_DIR}/clients"
SERVER_CONFIG="${WG_DIR}/wg0.conf"
SERVER_PRIVATE_KEY=$(sudo cat "${WG_DIR}/server-private.key")
SERVER_PUBLIC_KEY=$(sudo cat "${WG_DIR}/server-public.key")
SERVER_IP="server's ddns or ip" # Change this to your server Domain name or DDNS address or server IP
SERVER_PORT="51820" # Change this to your WireGuard server port, default is 51820
WG_INTERFACE="wg0"
LOCAL_NETWORK="192.168.1.0/24" # Change this to your local network

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

initialize_environment() {
    # Create vpnadmin group if it doesn't exist
    if ! getent group vpnadmin > /dev/null; then
        sudo groupadd vpnadmin
        echo "Group 'vpnadmin' has been created."
    else
        echo "Group 'vpnadmin' already exists."
    fi

    # Add the current user to the vpnadmin group
    sudo usermod -aG vpnadmin $(whoami)
    echo "User '$(whoami)' has been added to the 'vpnadmin' group."

    # Ensure necessary directories exist
    sudo mkdir -p "${CLIENTS_DIR}"
    echo "Directory '${CLIENTS_DIR}' exists or has been created."

    # Set ownership and permissions for WireGuard directories
    sudo chown -R root:vpnadmin "${WG_DIR}"
    echo "Ownership of '${WG_DIR}' and its subdirectories has been set to 'root:vpnadmin'."

    sudo chmod -R 770 "${WG_DIR}"
    echo "Permissions of '${WG_DIR}' and its subdirectories have been set to '770' (rwxrwx---)."

    # Check if qrencode is installed, if not install it
    if ! command -v qrencode &> /dev/null; then
        echo "qrencode is not installed. Installing..."
        sudo apt-get update
        sudo apt-get install -y qrencode
        echo "qrencode has been installed."
    else
        echo "qrencode is already installed."
    fi
}
get_next_ip() {
    if [ ! -f "${SERVER_CONFIG}" ]; then
        echo "Error: Configuration file not found."
        return 1
    fi

    # Extract used IPs from the configuration file
    USED_IPS=$(sudo grep 'AllowedIPs' "${SERVER_CONFIG}" | awk '{print $3}' | cut -d '/' -f 1 | sort)

    # Initialize starting IP address
    BASE_IP="10.0.0."
    START=2
    END=254

    # Check if USED_IPS is empty
    if [ -z "${USED_IPS}" ]; then
        echo "${BASE_IP}${START}"
        return 0
    fi

    # Iterate through the possible IP range to find the first unused IP
    for (( i=START; i<=END; i++ )); do
        NEXT_IP="${BASE_IP}${i}"
        if ! echo "${USED_IPS}" | grep -q "${NEXT_IP}"; then
            echo "${NEXT_IP}"
            return 0
        fi
    done

    echo "Error: No more IP addresses available in the subnet."
    return 1
}

qrcode() {
    CLIENT_NAME=$1
    CLIENT_CONFIG="${CLIENTS_DIR}/${CLIENT_NAME}.conf"

    # Generate QR code
    if ! type qrencode >/dev/null 2>&1; then
        echo "Error: qrencode is not installed."
        return 1
    fi
    echo "${CLIENT_CONFIG} QR code:\n" 
    qrencode -t ansiutf8 < "${CLIENT_CONFIG}"

}
generate_client() {
    CLIENT_NAME=$1
    CLIENT_CONFIG="${CLIENTS_DIR}/${CLIENT_NAME}.conf"
    echo "running generate_client"
    # Check if CLIENTS_DIR is defined and exists
    if [ -z "${CLIENTS_DIR}" ] || [ ! -d "${CLIENTS_DIR}" ]; then
        echo "Error: CLIENTS_DIR is not defined or does not exist."
        return 1
    fi

    # Check if SERVER_PUBLIC_KEY, SERVER_IP, SERVER_PORT, SERVER_CONFIG, and WG_INTERFACE are set
    if [ -z "${SERVER_PUBLIC_KEY}" ] || [ -z "${SERVER_IP}" ] || [ -z "${SERVER_PORT}" ] || [ -z "${SERVER_CONFIG}" ] || [ -z "${WG_INTERFACE}" ]; then
        echo "Error: One or more required variables are not set."
        return 1
    fi

    # Check if get_next_ip function is defined
    if ! type get_next_ip >/dev/null 2>&1; then
        echo "Error: get_next_ip function is not defined."
        return 1
    fi

    # Generate client keys
    CLIENT_PRIVATE_KEY=$(wg genkey) || { echo "Error generating private key"; return 1; }
    CLIENT_PUBLIC_KEY=$(echo "${CLIENT_PRIVATE_KEY}" | wg pubkey) || { echo "Error generating public key"; return 1; }
    CLIENT_ADDRESS="$(get_next_ip)/32"

    # Create client configuration
    cat > "${CLIENT_CONFIG}" << EOL
[Interface]
PrivateKey = ${CLIENT_PRIVATE_KEY}
Address = ${CLIENT_ADDRESS}
DNS = 1.1.1.1

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
Endpoint = ${SERVER_IP}:${SERVER_PORT}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOL

    # Check if the configuration file was created successfully
    if [ ! -f "${CLIENT_CONFIG}" ]; then
        echo "Error creating client configuration file."
        return 1
    fi

    # Set correct permissions for the client configuration file
    sudo chown root:vpnadmin "${CLIENT_CONFIG}" || { echo "Error setting file permissions"; return 1; }
    sudo chmod -R 770 "${CLIENT_CONFIG}"
    # Add client to server configuration with a comment
    echo -e "\n# ${CLIENT_NAME}\n[Peer]\nPublicKey = ${CLIENT_PUBLIC_KEY}\nAllowedIPs = ${CLIENT_ADDRESS}" | sudo tee -a "${SERVER_CONFIG}" > /dev/null || { echo "Error updating server configuration"; return 1; }

    # Remove multiple empty lines and keep only one
    sudo sed -i '/^$/N;/\n$/D' "${SERVER_CONFIG}"

    # Apply new configuration
    sudo wg set ${WG_INTERFACE} peer ${CLIENT_PUBLIC_KEY} allowed-ips ${CLIENT_ADDRESS} || { echo "Error applying configuration"; return 1; }

    # Generate QR code
    if ! type qrencode >/dev/null 2>&1; then
        echo "Error: qrencode is not installed."
        return 1
    fi
    qrencode -t ansiutf8 < "${CLIENT_CONFIG}"

    echo "Client configuration created at: ${CLIENT_CONFIG}"
}

delete_client() {
    CLIENT_NAME=$1
    CLIENT_CONFIG="${CLIENTS_DIR}/${CLIENT_NAME}.conf"

    if [ ! -f "${CLIENT_CONFIG}" ]; then
        echo "Client configuration not found: ${CLIENT_CONFIG}"
        exit 1
    fi

    CLIENT_PUBLIC_KEY=$(grep PublicKey "${CLIENT_CONFIG}" | cut -d " " -f 3)

    # Remove client from server configuration using the updated comment marker
    sudo sed -i "/# ${CLIENT_NAME}/,/^\s*$/d" "${SERVER_CONFIG}" || { echo "Error updating server configuration"; exit 1; }

    # Apply new configuration to remove the client
    sudo wg set ${WG_INTERFACE} peer ${CLIENT_PUBLIC_KEY} remove || { echo "Error removing client from WireGuard"; exit 1; }

    # Remove client configuration file
    sudo rm -f "${CLIENT_CONFIG}"

    echo "Client configuration deleted: ${CLIENT_CONFIG}"
}

list_clients() {
    echo "Existing clients:"
    sudo grep -oP '# \K\S+' "${SERVER_CONFIG}" | sed 's/^# //'
}


get_client_address() {
    CLIENT_NAME=$1
    local client_address

    if [ -z "${CLIENT_NAME}" ]; then
        echo "Error: No client name provided."
        return 1
    fi

    # Fetch client information
    client_info=$(sudo grep -A 3 "# ${CLIENT_NAME}" "${SERVER_CONFIG}")
    grep_exit_code=$?

    if [ ${grep_exit_code} -ne 0 ]; then
        echo "Error: grep command failed."
        return 1
    fi

    if [ -z "${client_info}" ]; then
        echo "Error: Client info for ${CLIENT_NAME} not found."
        return 1
    fi

    # Extract client address
    client_address=$(echo "${client_info}" | grep 'AllowedIPs' | awk '{print $NF}' | cut -d '/' -f 1)
    awk_exit_code=$?

    if [ ${awk_exit_code} -ne 0 ]; then
        echo "Error: Parsing client address failed."
        return 1
    fi

    if [ -z "${client_address}" ]; then
        echo "Error: Client address for ${CLIENT_NAME} not found."
        return 1
    fi

    echo "${client_address}"
    return 0
}

allow_client() {
    CLIENT_NAME=$1
    CLIENT_ADDRESS=$(get_client_address "${CLIENT_NAME}")

    if [ $? -ne 0 ]; then
        echo "Error: Client address not found for ${CLIENT_NAME}."
        exit 1
    fi
    sudo wg-quick down wg0
    # Edit local network access rules

    sudo sed -i "s|iptables -A INPUT -p udp --dport 51820 -j ACCEPT;|iptables -A INPUT -p udp --dport 51820 -j ACCEPT; iptables -A FORWARD -i wg0 -s ${CLIENT_ADDRESS} -d ${LOCAL_NETWORK} -j ACCEPT;|" "${SERVER_CONFIG}"
    sudo sed -i "s|iptables -D INPUT -p udp --dport 51820 -j ACCEPT;|iptables -D INPUT -p udp --dport 51820 -j ACCEPT; iptables -D FORWARD -i wg0 -s ${CLIENT_ADDRESS} -d ${LOCAL_NETWORK} -j ACCEPT;|" "${SERVER_CONFIG}"

    # Remove multiple empty lines and keep only one
    sudo sed -i '/^$/N;/\n$/D' "${SERVER_CONFIG}"

    # Apply the updated WireGuard configuration
    sudo wg-quick up wg0
    echo "Client ${CLIENT_NAME} allowed with address ${CLIENT_ADDRESS}."
}

deny_client() {
    CLIENT_NAME=$1
    CLIENT_ADDRESS=$(get_client_address "${CLIENT_NAME}")

    if [ $? -ne 0 ]; then
        echo "Error: Client address not found for ${CLIENT_NAME}."
        exit 1
    fi

    sudo wg-quick down wg0

    # Remove specific part of the local network access rules
    sudo sed -i "s|iptables -A FORWARD -i wg0 -s ${CLIENT_ADDRESS} -d ${LOCAL_NETWORK} -j ACCEPT; ||" "${SERVER_CONFIG}"
    sudo sed -i "s|iptables -D FORWARD -i wg0 -s ${CLIENT_ADDRESS} -d ${LOCAL_NETWORK} -j ACCEPT; ||" "${SERVER_CONFIG}"

    # Remove multiple empty lines and keep only one
    sudo sed -i '/^$/N;/\n$/D' "${SERVER_CONFIG}"

    # Apply the updated WireGuard configuration
    sudo wg-quick up wg0

    echo "Client ${CLIENT_NAME} denied with address ${CLIENT_ADDRESS}."

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
        # Prompt the user to confirm if they have changed the SERVER_IP
        read -p "Have you changed the SERVER_IP in the script to your DDNS address or IP address, as well as LOCAL_NETWORK in the script to your local network address? (y/n): " confirm
        if [[ "${confirm,,}" != "y" ]]; then
        echo "Please change the SERVER_IP in the script and then run it again."
        exit 1
        fi
        initialize_environment
        check_permissions "$SERVER_CONFIG"
        check_permissions "$CLIENTS_DIR"
        generate_client "$CLIENT_NAME"
        ;;
    delete)
        check_permissions "$SERVER_CONFIG"
        check_permissions "$CLIENTS_DIR"
        delete_client "$CLIENT_NAME"
        ;;
    list)
        if [[ "$CLIENT_NAME" == "all" ]]; then
            list_clients
        else
            echo "Usage: $0 {add|delete|list|local} <client_name>"
            echo "to list all clients: $0 list all"
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
        echo "Usage: $0 {add|delete} <client_name>"
        exit 1
        ;;
esac
