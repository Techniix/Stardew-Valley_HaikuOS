#!/usr/bin/env python3
"""Minimal UDP relay for Stardew Valley direct-IP multiplayer.

Runs on any machine with Python 3 (Windows, macOS, Linux, Haiku). It listens
on a local UDP port and forwards each client's traffic to a target host, so
players who can reach the relay machine (e.g. on the same LAN) can join a
host they can't reach directly (e.g. one that's only reachable over a VPN the
relay machine is connected to, or a tunnel address).

    python3 udp-relay.py --target 100.64.0.7:24642
    python3 udp-relay.py --listen 0.0.0.0:24642 --target host.example:24642

Players then use Co-op > Join > Join LAN Game with the relay machine's
address (add :PORT if --listen isn't port 24642).

Each client gets its own upstream socket, so the host sees one stable peer per
player and replies are routed back to the right client. Idle clients are
dropped after --idle seconds. Standard library only.
"""

import argparse
import selectors
import socket
import sys
import time

DEFAULT_PORT = 24642
MAX_DATAGRAM = 65535


def parse_endpoint(text, default_host=None):
    host, sep, port = text.rpartition(":")
    if not sep:
        host, port = text, str(DEFAULT_PORT)
    if not host:
        if default_host is None:
            raise argparse.ArgumentTypeError(f"missing host in {text!r}")
        host = default_host
    try:
        return host, int(port)
    except ValueError:
        raise argparse.ArgumentTypeError(f"bad port in {text!r}")


class Relay:
    def __init__(self, listen, target, idle, verbose):
        self.target = (socket.gethostbyname(target[0]), target[1])
        self.idle = idle
        self.verbose = verbose
        self.sel = selectors.DefaultSelector()
        self.front = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.front.bind(listen)
        self.front.setblocking(False)
        self.sel.register(self.front, selectors.EVENT_READ, None)
        self.clients = {}  # client addr -> [upstream socket, last activity]

    def log(self, msg):
        print(time.strftime("%H:%M:%S"), msg, flush=True)

    def upstream_for(self, client):
        entry = self.clients.get(client)
        if entry is None:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.bind(("0.0.0.0", 0))
            sock.setblocking(False)
            self.sel.register(sock, selectors.EVENT_READ, client)
            entry = [sock, time.monotonic()]
            self.clients[client] = entry
            self.log(f"client {client[0]}:{client[1]} connected "
                     f"({len(self.clients)} active)")
        entry[1] = time.monotonic()
        return entry[0]

    def drop(self, client, reason):
        sock, _ = self.clients.pop(client)
        self.sel.unregister(sock)
        sock.close()
        self.log(f"client {client[0]}:{client[1]} {reason} "
                 f"({len(self.clients)} active)")

    def run(self):
        local = self.front.getsockname()
        self.log(f"relaying UDP {local[0]}:{local[1]} -> "
                 f"{self.target[0]}:{self.target[1]} (Ctrl+C to stop)")
        last_sweep = time.monotonic()
        while True:
            for key, _ in self.sel.select(timeout=1.0):
                sock, client = key.fileobj, key.data
                try:
                    data, addr = sock.recvfrom(MAX_DATAGRAM)
                except (BlockingIOError, InterruptedError):
                    continue
                except (ConnectionResetError, OSError):
                    # Windows reports ICMP port unreachable this way.
                    continue
                if client is None:
                    # from a player: forward to the host
                    self.upstream_for(addr).sendto(data, self.target)
                    if self.verbose:
                        self.log(f"{addr[0]}:{addr[1]} -> host {len(data)} bytes")
                elif addr == self.target and client in self.clients:
                    # from the host: back to that player
                    self.clients[client][1] = time.monotonic()
                    self.front.sendto(data, client)
                    if self.verbose:
                        self.log(f"host -> {client[0]}:{client[1]} {len(data)} bytes")
            now = time.monotonic()
            if now - last_sweep >= 5:
                last_sweep = now
                for client, (_, seen) in list(self.clients.items()):
                    if now - seen > self.idle:
                        self.drop(client, "timed out")


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--target", required=True, type=parse_endpoint,
                   help="host to forward to, HOST[:PORT] (default port 24642)")
    p.add_argument("--listen", default=f"0.0.0.0:{DEFAULT_PORT}",
                   type=lambda t: parse_endpoint(t, "0.0.0.0"),
                   help="local address to listen on (default 0.0.0.0:24642)")
    p.add_argument("--idle", type=float, default=120,
                   help="drop a client after this many idle seconds (default 120)")
    p.add_argument("-v", "--verbose", action="store_true",
                   help="log every packet")
    args = p.parse_args()
    try:
        Relay(args.listen, args.target, args.idle, args.verbose).run()
    except KeyboardInterrupt:
        return 0
    except OSError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
