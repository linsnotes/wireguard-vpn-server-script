#!/bin/bash

# Stop WireGuard
wg-quick down wg0

# Check if the script is run with sudo
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root. Please use 'sudo'."
  exit 1
fi

# Completely remove wireguard and qrencode
apt purge --auto-remove -y wireguard qrencode

# Completely remove wireguard and qrencode
rm -rf /etc/wireguard
echo "removed '/etc/wireguard' directory"


# Remove the user from the vpnadmin group
echo "Removing user $USERNAME from vpnadmin group..."
deluser "$USERNAME" vpnadmin

# Change vpnadmin user's primary group to nogroup
echo "Changing vpnadmin user's primary group to nogroup..."
usermod -g nogroup vpnadmin

# Delete the vpnadmin group
echo "Deleting the vpnadmin group..."
groupdel vpnadmin

# Delete the vpnadmin user
echo "Deleting the vpnadmin user..."
userdel vpnadmin
