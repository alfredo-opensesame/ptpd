#!/bin/bash
# Comprehensive PTP packet capture analysis script

PCAP_FILE="$1"

if [ ! -f "$PCAP_FILE" ]; then
    echo "Usage: $0 <pcap_file>"
    exit 1
fi

echo "========================================================================"
echo "             PTP Packet Capture Analysis"
echo "========================================================================"
echo ""

# Basic capture info
echo "--- Capture Summary ---"
TOTAL_PKTS=$(tcpdump -r "$PCAP_FILE" 2>/dev/null | wc -l)
echo "Total packets: $TOTAL_PKTS"

# Capture duration
FIRST=$(tcpdump -r "$PCAP_FILE" -ttt 2>/dev/null | head -1 | awk '{print $1}')
LAST=$(tcpdump -r "$PCAP_FILE" -ttt 2>/dev/null | tail -1 | awk '{print $2, $3, $4, $5}')
echo "First packet: $(tcpdump -r "$PCAP_FILE" -nn 2>/dev/null | head -1 | awk '{print $1}')"
echo "Last packet:  $(tcpdump -r "$PCAP_FILE" -nn 2>/dev/null | tail -1 | awk '{print $1}')"
echo ""

# PTP Message Types
echo "--- PTP Message Types ---"
tcpdump -r "$PCAP_FILE" -nn 2>/dev/null | grep -o "msg type : [^,]*" | sort | uniq -c | sort -rn | \
    awk '{
        type=$5" "$6" "$7;
        gsub(/msg/, "", type);
        printf "  %-20s %4d packets\n", type, $1
    }'
echo ""

# Clock Identities
echo "--- PTP Clock Identities ---"
echo "Master Clock:"
tcpdump -r "$PCAP_FILE" -nn 2>/dev/null | grep "announce msg" | head -1 | \
    grep -o "clock identity : 0x[a-f0-9]*" | awk '{print "  ID: " $4}'

tcpdump -r "$PCAP_FILE" -nn 2>/dev/null | grep "announce msg" | head -1 | \
    grep -oE "192\.168\.[0-9]+\.[0-9]+" | head -1 | awk '{print "  IP: " $0}'

echo ""
echo "Slave Clock:"
tcpdump -r "$PCAP_FILE" -nn 2>/dev/null | grep "delay req msg" | head -1 | \
    grep -o "clock identity : 0x[a-f0-9]*" | awk '{print "  ID: " $4}'

tcpdump -r "$PCAP_FILE" -nn 2>/dev/null | grep "delay req msg" | head -1 | \
    grep -oE "192\.168\.[0-9]+\.[0-9]+" | head -1 | awk '{print "  IP: " $0}'
echo ""

# Grandmaster Properties
echo "--- Grandmaster Clock Properties ---"
tcpdump -r "$PCAP_FILE" -nn 2>/dev/null | grep "announce msg" | head -1 | \
    grep -o "gm clock class : [0-9]*" | awk '{print "  Clock Class: " $5 " (GPS/atomic clock based)"}'
tcpdump -r "$PCAP_FILE" -nn 2>/dev/null | grep "announce msg" | head -1 | \
    grep -o "gm clock accuracy : [0-9]*" | awk '{
        acc=$5;
        if (acc == 32) ns="250ns";
        else if (acc == 33) ns="1us";
        else if (acc == 34) ns="2.5us";
        else if (acc == 35) ns="10us";
        else ns="unknown";
        print "  Clock Accuracy: " acc " (" ns ")"
    }'
tcpdump -r "$PCAP_FILE" -nn 2>/dev/null | grep "announce msg" | head -1 | \
    grep -o "gm priority_1 : [0-9]*" | awk '{print "  Priority 1: " $4}'
tcpdump -r "$PCAP_FILE" -nn 2>/dev/null | grep "announce msg" | head -1 | \
    grep -o "gm priority_2 : [0-9]*" | awk '{print "  Priority 2: " $4}'
tcpdump -r "$PCAP_FILE" -nn 2>/dev/null | grep "announce msg" | head -1 | \
    grep -o "time source : 0x[0-9a-f]*" | awk '{
        src=$4;
        if (src == "0x20") name="INTERNAL_OSCILLATOR";
        else if (src == "0x10") name="ATOMIC_CLOCK";
        else if (src == "0xa0") name="GPS";
        else name="unknown";
        print "  Time Source: " src " (" name ")"
    }'
echo ""

# Transport & Addressing
echo "--- Transport & Multicast ---"
echo "Transport: UDP/IPv4 Multicast"
tcpdump -r "$PCAP_FILE" -nn 2>/dev/null | grep "224.0.1.129" | head -1 | \
    grep -o "224\.0\.1\.[0-9]*:[0-9]*" | head -1 | awk '{print "  Event Messages: " $0 " (PTP event multicast)"}'
tcpdump -r "$PCAP_FILE" -nn 2>/dev/null | grep "224.0.1.129" | grep "general" | head -1 | \
    grep -o "224\.0\.1\.[0-9]*:[0-9]*" | head -1 | awk '{print "  General Messages: " $0 " (PTP general multicast)"}'
echo ""

# Domain and Flags
echo "--- PTP Domain & Configuration ---"
tcpdump -r "$PCAP_FILE" -nn 2>/dev/null | grep "sync msg" | head -1 | \
    grep -o "domain : [0-9]*" | awk '{print "  Domain: " $3}'
tcpdump -r "$PCAP_FILE" -nn 2>/dev/null | grep "sync msg" | head -1 | \
    grep -o "Flags \[[^]]*\]" | awk '{gsub(/Flags /, ""); print "  Sync Flags: " $0}'
tcpdump -r "$PCAP_FILE" -nn 2>/dev/null | grep "announce msg" | head -1 | \
    grep -o "Flags \[[^]]*\]" | awk '{gsub(/Flags /, ""); print "  Announce Flags: " $0}'
echo ""

# Timing Analysis
echo "--- Timing Intervals (first 10 sync messages) ---"
tcpdump -r "$PCAP_FILE" -ttt -nn 2>/dev/null | grep "sync msg" | head -10 | \
    awk '{
        interval=$1;
        if (NR == 1) print "  Initial sync";
        else {
            gsub(/00:00:/, "", interval);
            gsub(/-00:00:/, "-", interval);
            printf "  Δt = %s\n", interval
        }
    }'
echo ""

# Sequence numbers
echo "--- Message Sequence Analysis ---"
SYNC_FIRST=$(tcpdump -r "$PCAP_FILE" -nn 2>/dev/null | grep "sync msg" | head -1 | grep -o "seq id : [0-9]*" | awk '{print $4}')
SYNC_LAST=$(tcpdump -r "$PCAP_FILE" -nn 2>/dev/null | grep "sync msg" | tail -1 | grep -o "seq id : [0-9]*" | awk '{print $4}')
SYNC_COUNT=$(tcpdump -r "$PCAP_FILE" -nn 2>/dev/null | grep "sync msg" | wc -l)
echo "  Sync messages: seq $SYNC_FIRST to $SYNC_LAST ($SYNC_COUNT packets)"

ANNOUNCE_FIRST=$(tcpdump -r "$PCAP_FILE" -nn 2>/dev/null | grep "announce msg" | head -1 | grep -o "seq id : [0-9]*" | awk '{print $4}')
ANNOUNCE_LAST=$(tcpdump -r "$PCAP_FILE" -nn 2>/dev/null | grep "announce msg" | tail -1 | grep -o "seq id : [0-9]*" | awk '{print $4}')
ANNOUNCE_COUNT=$(tcpdump -r "$PCAP_FILE" -nn 2>/dev/null | grep "announce msg" | wc -l)
echo "  Announce messages: seq $ANNOUNCE_FIRST to $ANNOUNCE_LAST ($ANNOUNCE_COUNT packets)"

DELAY_COUNT=$(tcpdump -r "$PCAP_FILE" -nn 2>/dev/null | grep "delay req msg" | wc -l)
echo "  Delay request/response pairs: $DELAY_COUNT exchanges"

echo ""
echo "========================================================================"
