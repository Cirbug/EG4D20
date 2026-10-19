"""Stop-and-wait hardware UDP echo test. No adapter/firewall configuration changes."""
import argparse
import random
import socket
import time

def payload(length, seq):
    rng = random.Random(seq)
    return bytes(rng.randrange(256) for _ in range(length))

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--local', default='192.168.50.1')
    p.add_argument('--board', default='192.168.50.2')
    p.add_argument('--count', type=int, default=20)
    p.add_argument('--timeout', type=float, default=3.0)
    args = p.parse_args()
    if args.count <= 0:
        p.error('--count must be positive')
    lengths = [1, 17, 18, 32, 64, 255, 512, 1024, 1400, 1472]
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind((args.local, 6001))
        sock.settimeout(args.timeout)
        for seq in range(args.count):
            data = payload(lengths[seq % len(lengths)], seq)
            start = time.perf_counter()
            sock.sendto(data, (args.board, 6002))
            reply, addr = sock.recvfrom(65535)
            if addr != (args.board, 6002) or reply != data:
                raise RuntimeError(f'MISMATCH seq={seq} peer={addr} sent={len(data)} received={len(reply)}')
            print(f'PASS seq={seq} len={len(data)} rtt_ms={(time.perf_counter()-start)*1000:.3f}', flush=True)
            time.sleep(0.05)
    print(f'PASS {args.count} packets; byte-for-byte echo verified')

if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError) as error:
        raise SystemExit(f'FAIL: {error}\nCheck wired link=1Gbps, PC IP=192.168.50.1/24, FPGA bitstream and UDP 6001 firewall permission.')
