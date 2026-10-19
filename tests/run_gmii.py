"""Exercise the actual UDP/ARP/MAC RTL with independent Ethernet packet vectors.
PLL and physical RGMII DDR are bypassed; this is not PHY or board validation.
"""
from pathlib import Path
import random
import struct
import subprocess
import zlib

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT.parent / 'bank/eg4d_udp_20261018/sim'
OUT.mkdir(parents=True, exist_ok=True)
HOST_MAC = bytes.fromhex('020000000001')
BOARD_MAC = bytes.fromhex('020000000002')
HOST_IP = bytes([192, 168, 50, 1])
BOARD_IP = bytes([192, 168, 50, 2])

def checksum(data):
    data += b'\0' * (len(data) % 2)
    total = sum(struct.unpack('!' + 'H' * (len(data) // 2), data))
    while total >> 16:
        total = (total & 65535) + (total >> 16)
    return (~total) & 65535

def ethernet(dst, kind, payload):
    body = dst + HOST_MAC + struct.pack('!H', kind) + payload
    body = body.ljust(60, b'\0')
    return b'\x55' * 7 + b'\xd5' + body + struct.pack('<I', zlib.crc32(body))

def arp(op=1):
    return ethernet(b'\xff' * 6, 0x806, struct.pack('!HHBBH', 1, 0x800, 6, 4, op)
                    + HOST_MAC + HOST_IP + b'\0' * 6 + BOARD_IP)

def udp(data, seq):
    header = struct.pack('!BBHHHBBH4s4s', 0x45, 0, 28 + len(data), seq, 0, 64, 17, 0, HOST_IP, BOARD_IP)
    header = header[:10] + struct.pack('!H', checksum(header)) + header[12:]
    return ethernet(BOARD_MAC, 0x800, header + struct.pack('!HHHH', 6001, 6002, 8 + len(data), 0) + data)

PING_PAYLOADS = [b'EG4D20 independent ICMP echo test', bytes(range(32))]

def ping(data):
    icmp = struct.pack('!BBHHH', 8, 0, 0, 0x1234, 1) + data
    icmp = icmp[:2] + struct.pack('!H', checksum(icmp)) + icmp[4:]
    ip = struct.pack('!BBHHHBBH4s4s', 0x45, 0, 20 + len(icmp), 20, 0, 64, 1, 0, HOST_IP, BOARD_IP)
    ip = ip[:10] + struct.pack('!H', checksum(ip)) + ip[12:]
    return ethernet(BOARD_MAC, 0x800, ip + icmp)

lengths = [1, 17, 18, 32, 255, 512, 1024, 1472]
payloads = [random.Random(i).randbytes(n) for i, n in enumerate(lengths)]
bad_fcs = bytearray(udp(b'must not echo corrupted Ethernet frame', 99))
bad_fcs[-1] ^= 1
packets = [arp()] + [ping(data) for data in PING_PAYLOADS] + [udp(data, i) for i, data in enumerate(payloads)] + [bytes(bad_fcs)]
# Confirm a rejected frame is drained, without corrupting the following frame.
payloads.append(b'valid packet after bad FCS')
packets.append(udp(payloads[-1], 100))
for i, packet in enumerate(packets):
    (OUT / f'in{i}.hex').write_text('\n'.join(f'{b:02x}' for b in packet))

tb = '''`timescale 1ns/1ps
module tb;
reg clk=0, rx_clk=0, reset=1, rx_valid=0;
reg [7:0] rx_data=0;
reg [7:0] packet[0:4095];
integer f, i;
reg tx_previous=0;
always #4 clk=~clk;
// Independent RX clock: exercise FIFO CDC, not only identical clock edges.
always #4.001 rx_clk=~rx_clk;
udp_transmit_test dut(.I_sys_clk(clk), .I_a_rgmii_rxd(4'b0),
 .I_a_rgmii_rxc(clk), .I_a_rgmii_rx_ctl(1'b0));
always @(posedge clk) begin
 #1;
 if(dut.gmii_tvalid) $fwrite(f,"%02x ",dut.gmii_tdata);
 if(!dut.gmii_tvalid && tx_previous) $fwrite(f,"\\n");
 tx_previous=dut.gmii_tvalid;
end
task send_packet;
input integer count;
begin
 for(i=0;i<count;i=i+1) begin
  @(negedge rx_clk); rx_valid=1; rx_data=packet[i];
 end
 @(negedge rx_clk); rx_valid=0; rx_data=0;
 repeat(5000) @(negedge rx_clk);
end
endtask
initial begin
 f=$fopen("tx.hex","w");
 force dut.reset=reset;
 force dut.gmii_rclk=rx_clk;
 force dut.gmii_rvalid=rx_valid;
 force dut.gmii_rdata=rx_data;
 repeat(50) @(negedge clk); reset=0;
 // The MAC RX reset sequencer holds reset for 128 RX clocks.
 repeat(512) @(negedge clk);
'''
for i, packet in enumerate(packets):
    tb += f'$readmemh("in{i}.hex", packet, 0, {len(packet)-1}); send_packet({len(packet)});\n'
tb += '$fclose(f); $display("SIM_DONE"); $finish; end\nendmodule\n'
tb += '''module pll(input refclk,reset,output extlock,clk0_out,clk1_out,clk2_out);
assign extlock=~reset; assign clk0_out=refclk; assign clk1_out=refclk; assign clk2_out=refclk;
endmodule
module rgmii_interface(input speed_10_100,gmii_tx_clk_d,gmii_tx_reset_d,gmii_tx_reset,
gmii_tx_clk,gmii_tx_en,gmii_tx_er,gmii_rx_reset,rgmii_rx_ctl,rgmii_rxc,
input [7:0] gmii_txd,input [3:0] rgmii_rxd,
output gmii_rx_clk,gmii_rx_dv,gmii_rx_er,rgmii_tx_ctl,rgmii_txc,
gmii_crs,gmii_col,link_status,duplex_status,
output [7:0] gmii_rxd,output [3:0] rgmii_txd,output [1:0] clock_speed);
endmodule
'''
(OUT/'tb.sv').write_text(tb)
sources = [(ROOT / s).as_posix() for s in (ROOT/'tools/sources.txt').read_text().splitlines()
           if not s.startswith('al_ip/') and not s.endswith('/rgmii_interface.v')]
commands = [ [r'E:\iverilog\bin\iverilog.exe','-g2012','-s','tb','-o','sim.vvp',str(OUT/'tb.sv')] + sources,
             [r'E:\iverilog\bin\vvp.exe','sim.vvp'] ]
with (OUT/'run.log').open('w') as log:
    for command in commands:
        result = subprocess.run(command,cwd=OUT,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=90)
        log.write(result.stdout); log.flush()
        if result.returncode:
            raise RuntimeError(result.stdout[-4000:])
received=[]; arp_reply=False; ping_replies=[]
for line in (OUT/'tx.hex').read_text().splitlines():
    data=bytes.fromhex(line)
    start=data.index(b'\xd5')+1
    frame=data[start:]
    assert zlib.crc32(frame[:-4]) == struct.unpack('<I',frame[-4:])[0], 'Ethernet FCS mismatch'
    assert frame[:6] == HOST_MAC and frame[6:12] == BOARD_MAC, 'MAC mismatch'
    if frame[12:14] == b'\x08\x06':
        arp_reply |= frame[20:22] == b'\x00\x02'
    elif frame[12:14] == b'\x08\x00':
        ip=frame[14:]; ihl=(ip[0]&15)*4
        assert checksum(ip[:ihl]) == 0, 'IP checksum mismatch'
        assert ip[12:16] == BOARD_IP and ip[16:20] == HOST_IP
        if ip[9] == 17:
            src,dst,length,cs=struct.unpack('!HHHH',ip[ihl:ihl+8])
            assert (src,dst) == (6002,6001)
            received.append(ip[ihl+8:ihl+length])
        elif ip[9] == 1:
            icmp = ip[ihl:struct.unpack('!H', ip[2:4])[0]]
            assert checksum(icmp) == 0, 'ICMP checksum mismatch'
            assert icmp[:2] == b'\0\0' and icmp[4:8] == bytes.fromhex('12340001')
            ping_replies.append(icmp[8:])
assert arp_reply, 'No ARP reply'
assert ping_replies == PING_PAYLOADS, 'ICMP echo payload mismatch'
assert received == payloads, f'Echo mismatch: expected lengths {lengths}, got {[len(x) for x in received]}'
result = f'PASS asynchronous RX/TX clocks, ARP, odd/even ICMP echo, {len(received)} UDP echoes {[len(x) for x in received]}, addresses/checksums/FCS, bad-FCS rejection and recovery'
(OUT/'result.txt').write_text(result+'\n')
print(result)
