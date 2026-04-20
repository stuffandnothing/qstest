#!/usr/bin/env python3
"""
OpenRGB SDK helper for noctalia-openrgb-control plugin.
Uses the OpenRGB TCP SDK protocol directly - no dependencies required.
Protocol reference: https://github.com/CalcProgrammer1/OpenRGB/blob/master/Documentation/OpenRGBSDK.md
"""
import socket
import struct
import sys

MAGIC = b'ORGB'

# Packet IDs
PKT_SET_CLIENT_NAME    = 50
PKT_REQUEST_PROTO_VER  = 40
PKT_LOAD_PROFILE       = 152

def make_header(dev_idx, pkt_id, data_len):
    # Header: magic(4) + dev_idx(4) + pkt_id(4) + data_size(4) = 16 bytes
    return struct.pack('<4sIII', MAGIC, dev_idx, pkt_id, data_len)

def send_packet(sock, dev_idx, pkt_id, data=b''):
    sock.sendall(make_header(dev_idx, pkt_id, len(data)) + data)

def recv_packet(sock):
    header = b''
    while len(header) < 16:
        chunk = sock.recv(16 - len(header))
        if not chunk:
            raise ConnectionError("Server closed connection")
        header += chunk
    magic, dev_idx, pkt_id, data_len = struct.unpack('<4sIII', header)
    if magic != MAGIC:
        raise ValueError(f"Bad magic: {magic}")
    data = b''
    while len(data) < data_len:
        chunk = sock.recv(data_len - len(data))
        if not chunk:
            raise ConnectionError("Server closed connection")
        data += chunk
    return pkt_id, dev_idx, data

def connect(host, port):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5)
    s.connect((host, port))

    # Set client name
    name = b'noctalia-openrgb\x00'
    send_packet(s, 0, PKT_SET_CLIENT_NAME, name)

    # Negotiate protocol version (we support up to 3)
    send_packet(s, 0, PKT_REQUEST_PROTO_VER, struct.pack('<I', 3))
    pkt_id, _, data = recv_packet(s)
    # server responds with its max version, we don't need to store it

    return s

def load_profile(host, port, profile_name):
    import os

    if not profile_name.strip():
        print("Error: no profile name given", file=sys.stderr)
        sys.exit(1)

    config_dir = os.path.expanduser('~/.config/OpenRGB')
    profile_path = os.path.join(config_dir, profile_name + '.orp')
    if not os.path.isfile(profile_path):
        print(f"Error: profile '{profile_name}' not found at {profile_path}", file=sys.stderr)
        sys.exit(1)

    s = connect(host, port)
    try:
        data = profile_name.encode('utf-8') + b'\x00'
        send_packet(s, 0, PKT_LOAD_PROFILE, data)
        print("Profile loaded successfully")
    finally:
        s.close()

def set_color(host, port, hex_color):
    # Pad to 6 chars if needed
    hex_color = hex_color.zfill(6)
    r = int(hex_color[0:2], 16)
    g = int(hex_color[2:4], 16)
    b = int(hex_color[4:6], 16)
    # RGBColor is stored as 0x00BBGGRR (little-endian uint32)
    color = struct.pack('<I', (b << 16) | (g << 8) | r)

    s = connect(host, port)
    try:
        # Request controller count first
        send_packet(s, 0, 0)  # NET_PACKET_ID_REQUEST_CONTROLLER_COUNT
        pkt_id, _, data = recv_packet(s)
        count = struct.unpack('<I', data)[0]

        # For each device, set custom mode then update all LEDs to the color
        # We need controller data to know LED count per device
        for dev_idx in range(count):
            # Request controller data (protocol 3)
            send_packet(s, dev_idx, 1, struct.pack('<I', 3))
            pkt_id, _, ctrl_data = recv_packet(s)

            # Parse just enough to get LED count
            # data_size(4) + type(4) + name_len(2) + name + vendor_len(2) + vendor +
            # desc_len(2) + desc + ver_len(2) + ver + serial_len(2) + serial +
            # location_len(2) + location + num_modes(2) + active_mode(4) + modes +
            # num_zones(2) + zones + num_leds(2)
            # This is complex to parse fully, so we use a simpler approach:
            # just send SetCustomMode and UpdateLEDs with a guessed LED count
            # Actually we'll use the simpler direct color packet approach

            # Set custom mode for this device
            send_packet(s, dev_idx, 1100)  # NET_PACKET_ID_RGBCONTROLLER_SETCUSTOMMODE

        # Re-request count and set LEDs
        # Parse ctrl_data to get num_leds for each device
        # For simplicity, re-request each controller
        send_packet(s, 0, 0)
        pkt_id, _, data = recv_packet(s)
        count = struct.unpack('<I', data)[0]

        for dev_idx in range(count):
            send_packet(s, dev_idx, 1, struct.pack('<I', 3))
            pkt_id, _, ctrl_data = recv_packet(s)
            num_leds = parse_num_leds(ctrl_data)
            if num_leds > 0:
                # Build UpdateLEDs packet: data_size(4) + num_colors(2) + colors(4*n)
                colors = color * num_leds
                payload = struct.pack('<IH', 4 + 2 + len(colors), num_leds) + colors
                send_packet(s, dev_idx, 1050, payload)  # NET_PACKET_ID_RGBCONTROLLER_UPDATELEDS

        print("Color set successfully")
    finally:
        s.close()

def parse_num_leds(data):
    """Parse controller data block to extract num_leds."""
    try:
        offset = 0
        offset += 4  # data_size
        offset += 4  # type

        def read_string(off):
            slen = struct.unpack_from('<H', data, off)[0]
            return off + 2 + slen

        # name, vendor, description, version, serial, location
        for _ in range(6):
            offset = read_string(offset)

        num_modes = struct.unpack_from('<H', data, offset)[0]
        offset += 2
        offset += 4  # active_mode

        # Skip modes - each mode has variable size, need to parse each one
        for _ in range(num_modes):
            # mode_name
            mname_len = struct.unpack_from('<H', data, offset)[0]
            offset += 2 + mname_len
            offset += 4   # mode_value
            offset += 4   # mode_flags
            offset += 4   # mode_speed_min
            offset += 4   # mode_speed_max
            offset += 4   # mode_brightness_min (proto 3)
            offset += 4   # mode_brightness_max (proto 3)
            offset += 4   # mode_colors_min
            offset += 4   # mode_colors_max
            offset += 4   # mode_speed
            offset += 4   # mode_brightness (proto 3)
            offset += 4   # mode_direction
            offset += 4   # mode_color_mode
            num_mode_colors = struct.unpack_from('<H', data, offset)[0]
            offset += 2
            offset += 4 * num_mode_colors  # mode_colors

        num_zones = struct.unpack_from('<H', data, offset)[0]
        offset += 2

        # Skip zones
        for _ in range(num_zones):
            zname_len = struct.unpack_from('<H', data, offset)[0]
            offset += 2 + zname_len
            offset += 4   # zone_type
            offset += 4   # zone_leds_min
            offset += 4   # zone_leds_max
            offset += 4   # zone_leds_count
            matrix_len = struct.unpack_from('<H', data, offset)[0]
            offset += 2
            if matrix_len > 0:
                offset += matrix_len

        num_leds = struct.unpack_from('<H', data, offset)[0]
        return num_leds
    except Exception as e:
        print(f"Warning: could not parse LED count: {e}", file=sys.stderr)
        return 0

if __name__ == '__main__':
    if len(sys.argv) < 4:
        print("Usage: openrgb-helper.py <profile|color> <host> <port> <name|hexcolor>")
        sys.exit(1)

    cmd     = sys.argv[1]
    host    = sys.argv[2]
    port    = int(sys.argv[3])
    arg     = sys.argv[4] if len(sys.argv) > 4 else ""

    try:
        if cmd == 'profile':
            load_profile(host, port, arg)
        elif cmd == 'color':
            set_color(host, port, arg)
        else:
            print(f"Unknown command: {cmd}", file=sys.stderr)
            sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
