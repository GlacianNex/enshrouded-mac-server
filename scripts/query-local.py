#!/usr/bin/env python3
"""Steam A2S_INFO probe. Does not join or modify the game world."""
import socket
import sys
import ipaddress
host = str(ipaddress.IPv4Address(sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1"))
request = b"\xff\xff\xff\xffTSource Engine Query\x00"
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as connection:
    connection.settimeout(8)
    connection.connect((host, 15637))
    connection.send(request)
    reply = connection.recv(65535)
    if reply[:5] == b"\xff\xff\xff\xffA" and len(reply) >= 9:
        connection.send(request + reply[5:9])
        reply = connection.recv(65535)
    if reply[:5] != b"\xff\xff\xff\xffI":
        raise SystemExit(f"Unexpected query response type: {reply[:5].hex()}")
    print(f"Steam A2S_INFO replied from {host}:15637 ({len(reply)} bytes).")
