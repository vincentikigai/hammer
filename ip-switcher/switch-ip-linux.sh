#!/bin/bash

# Check if run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script with sudo or as root."
  exit 1
fi

# Check if nmcli is installed
if ! command -v nmcli &> /dev/null; then
    echo "nmcli could not be found. Please ensure NetworkManager is installed."
    exit 1
fi

echo "============================"
echo "   IP Address Switcher      "
echo "============================"
echo ""

# Get available devices
echo "Available Network Interfaces:"
mapfile -t devices < <(nmcli -t -f DEVICE,TYPE device status | grep -v '^lo:' | grep -v 'loopback')
i=1
for dev in "${devices[@]}"; do
    dev_name=$(echo "$dev" | cut -d: -f1)
    dev_type=$(echo "$dev" | cut -d: -f2)
    echo "  [$i] $dev_name ($dev_type)"
    ((i++))
done

read -p "Select an interface (1-${#devices[@]}): " iface_idx
if ! [[ "$iface_idx" =~ ^[0-9]+$ ]] || [ "$iface_idx" -lt 1 ] || [ "$iface_idx" -gt "${#devices[@]}" ]; then
    echo "Invalid selection."
    exit 1
fi

selected_dev=$(echo "${devices[$((iface_idx-1))]}" | cut -d: -f1)

# Get the active connection name for the device
conn_name=$(nmcli -t -f NAME,DEVICE connection show --active | grep ":$selected_dev$" | cut -d: -f1 | head -n 1)

if [ -z "$conn_name" ]; then
    echo "No active connection found for $selected_dev. Creating a new profile..."
    conn_name="custom-$selected_dev"
    nmcli connection add type ethernet ifname "$selected_dev" con-name "$conn_name" >/dev/null 2>&1
fi

# Define Profiles
# Format: Name | Type | IP/Prefix | Gateway | DNS (comma separated)
profiles=(
    "DHCP (Automatic)|DHCP|||"
    "Home Network|Static|192.168.1.100/24|192.168.1.1|8.8.8.8,1.1.1.1"
    "Work Network|Static|10.0.0.50/24|10.0.0.1|10.0.0.2"
)

echo ""
echo "Available Profiles:"
j=1
for prof in "${profiles[@]}"; do
    p_name=$(echo "$prof" | cut -d'|' -f1)
    p_type=$(echo "$prof" | cut -d'|' -f2)
    p_ip=$(echo "$prof" | cut -d'|' -f3)
    if [ "$p_type" == "DHCP" ]; then
        echo "  [$j] $p_name - DHCP"
    else
        echo "  [$j] $p_name - Static ($p_ip)"
    fi
    ((j++))
done

read -p "Select a profile (1-${#profiles[@]}): " prof_idx
if ! [[ "$prof_idx" =~ ^[0-9]+$ ]] || [ "$prof_idx" -lt 1 ] || [ "$prof_idx" -gt "${#profiles[@]}" ]; then
    echo "Invalid selection."
    exit 1
fi

selected_prof="${profiles[$((prof_idx-1))]}"
p_name=$(echo "$selected_prof" | cut -d'|' -f1)
p_type=$(echo "$selected_prof" | cut -d'|' -f2)
p_ip=$(echo "$selected_prof" | cut -d'|' -f3)
p_gw=$(echo "$selected_prof" | cut -d'|' -f4)
p_dns=$(echo "$selected_prof" | cut -d'|' -f5)

echo ""
echo "Applying Profile: $p_name to interface '$selected_dev' (Connection: $conn_name)..."

if [ "$p_type" == "DHCP" ]; then
    nmcli connection modify "$conn_name" ipv4.method auto ipv4.addresses "" ipv4.gateway "" ipv4.dns ""
else
    nmcli connection modify "$conn_name" ipv4.method manual ipv4.addresses "$p_ip" ipv4.gateway "$p_gw" ipv4.dns "$p_dns"
fi

# Bring the connection up to apply changes
echo "Restarting connection to apply changes..."
nmcli connection up "$conn_name" >/dev/null

echo "Profile applied successfully."
echo ""
echo "Current Configuration for '$selected_dev':"
ip -4 addr show dev "$selected_dev" | grep inet
