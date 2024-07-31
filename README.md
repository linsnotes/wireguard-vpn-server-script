# WireGuard VPN Client Management Script

This script is designed to automate the process of generating new WireGuard clients, creating their configuration files, and generating QR codes for easy client setup. Additionally, it includes functions to add and delete clients, list existing clients, and allow or deny local network access for specific clients.

## Features

- Auto-generate client configuration
- Create `<client_name>.conf` files
- Add client and delete client
- List clients
- Generate QR codes for easy client setup
- Allow or deny local network access for clients

## Important Setup Information

Before running the script, ensure you have completed the following steps:

1. **Enable Port Forwarding:** Make sure port forwarding is enabled on your router for WireGuard port 51820.
2. **Setup IPTables Default Policy:** It's recommended to set up an IPTables default policy to enhance security.

## Download the script

1. **Download and edit the Script**

   Save the script to a file, e.g., `wgvpn.sh`.

   ```bash
   wget  https://raw.githubusercontent.com/linsnotes/wireguard-vpn-server-script/main/wgvpn.sh
   ```

   Change the variables in the script
   ```
   nano wgvpn.sh
   ```
   - SERVER_IP=""
   - NET_INTERFACE=""
   - LOCAL_NETWORK=""

3. **Make the Script Executable**

   ```bash
   chmod +x wgvpn.sh
   ```

4. **Run the Script**

   ```bash
   sudo ./wgvpn.sh
   ```
5. **To uninstall**
   ### 6. Uninstall

  ```bash
  wget  https://raw.githubusercontent.com/linsnotes/wireguard-vpn-server-script/main/uninstall-wgvpn.sh
  ```

  ```bash
  chmod +x wgvpn.sh
  ```

  ```bash
  sudo ./uninstall-wgvpn.sh
  ```

## Usage

### 1. Generate a new client

To generate a new client configuration and QR code, run the following command:

```bash
sudo ./wgvpn add <client_name>
```

This will create a `client.conf` file and a QR code image for the specified client.

### 2. Delete a client

To delete an existing client, use the following command:

```bash
sudo ./wgvpn delete <client_name>
```

### 3. List clients

To list all existing clients, use the following command:

```bash
sudo ./wgvpn list all
```

### 4. Allow local network access

To allow a client to access the local network, use the following command:

```bash
sudo ./wgvpn allow <client_name>
```

### 5. Deny network access

To deny a client access to the network, use the following command:

```bash
sudo ./wgvpn deny <client_name>
```


## Example

Here's an example of how to use the script:

```bash
# Generate a new client configuration
sudo ./wgvpn add client1

# Delete an existing client
sudo ./wgvpn delete client1

# List all clients
sudo ./wgvpn list all

# Allow client1 to access the server local network
sudo ./wgvpn allow client1

# Deny client1 access to the server local network
sudo ./wgvpn deny client1
```

## License

This project is licensed under the MIT License.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.
