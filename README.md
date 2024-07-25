# WireGuard VPN Client Management Script

This script is designed to automate the process of generating new WireGuard clients, creating their configuration files, and generating QR codes for easy client setup. Additionally, it includes functions to add and delete clients, list existing clients, and allow or deny local network access for specific clients.

## Features

- Auto-generate client configuration
- Create `client.conf` files
- Add client and delete client
- List clients
- Generate QR codes for easy client setup
- Allow or deny local network access for clients

## Prerequisites

Ensure you have the `wg0.conf` file created with the following initial configuration:

```conf
[Interface]
Address = 10.0.0.1/24
ListenPort = 51820
PrivateKey = your server private key
PostUp = iptables -A INPUT -p udp --dport 51820 -j ACCEPT; iptables -A FORWARD -i wg0 -d <local network address> -j REJECT; iptables -A FORWARD -i wg0 -o <net-interface> -j ACCEPT; iptables -A FORWARD -i <net-interface> -o wg0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT; iptables -t nat -A POSTROUTING -o <net-interface> -j MASQUERADE
PostDown = iptables -D INPUT -p udp --dport 51820 -j ACCEPT; iptables -D FORWARD -i wg0 -d <local network address> -j REJECT; iptables -D FORWARD -i wg0 -o <net-interface> -j ACCEPT; iptables -D FORWARD -i <net-interface> -o wg0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT; iptables -t nat -D POSTROUTING -o <net-interface> -j MASQUERADE
```

Replace `<local network address>` and `<net-interface>` with your actual local network address and network interface respectively.

## Usage

### 1. Generate a new client

To generate a new client configuration and QR code, run the following command:

```bash
./wgvpn add <client_name>
```

This will create a `client.conf` file and a QR code image for the specified client.

### 2. Delete a client

To delete an existing client, use the following command:

```bash
./wgvpn delete <client_name>
```

### 3. List clients

To list all existing clients, use the following command:

```bash
./wgvpn list all
```

### 4. Allow local network access

To allow a client to access the local network, use the following command:

```bash
./wgvpn allow <client_name>
```

### 5. Deny network access

To deny a client access to the network, use the following command:

```bash
./wgvpn deny <client_name>
```

## Example

Here's an example of how to use the script:

```bash
# Generate a new client configuration
./wgvpn add client1

# Delete an existing client
./wgvpn delete client1

# List all clients
./wgvpn list all

# Allow client1 to access the server local network
./wgvpn allow client1

# Deny client1 access to the server local network
./wgvpn deny client1
```

## License

This project is licensed under the MIT License.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.
