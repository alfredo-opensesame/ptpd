#!/usr/bin/env python3
import csv
import sys
import numpy as np
from pathlib import Path

def analyze_ptp_stats(csv_file):
    """Analyze PTP statistics from CSV file with flexible filtering."""
    
    if not Path(csv_file).exists():
        print(f"Error: File {csv_file} not found")
        return
    
    offsets = []
    delays = []
    
    with open(csv_file, 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            if len(row) < 10 or 'slv' not in row[1]:
                continue
            
            try:
                offset_s = float(row[4])
                delay_s = float(row[5])
                
                # Convert to microseconds
                offset_us = offset_s * 1e6
                delay_us = delay_s * 1e6
                
                offsets.append(offset_us)
                if abs(delay_us) < 1000000:  # Filter extreme delay outliers
                    delays.append(delay_us)
                    
            except (ValueError, IndexError):
                continue
    
    if not offsets:
        print("No valid offset data found")
        return
        
    offsets = np.array(offsets)
    
    print("=" * 60)
    print("PTP Performance Analysis - Detailed")
    print("=" * 60)
    print(f"\nTotal slave state samples: {len(offsets)}")
    
    print(f"\nOffset From Master (all data):")
    print(f"  Min: {np.min(offsets):.3f} μs")
    print(f"  Max: {np.max(offsets):.3f} μs")
    print(f"  Mean: {np.mean(offsets):.3f} μs")
    print(f"  Median: {np.median(offsets):.3f} μs")
    print(f"  Std Dev: {np.std(offsets):.3f} μs")
    print(f"  RMS: {np.sqrt(np.mean(offsets**2)):.3f} μs")
    print(f"  Peak-to-Peak: {np.max(offsets) - np.min(offsets):.3f} μs")
    
    # Analyze by magnitude
    under_1ms = np.sum(np.abs(offsets) < 1000)
    under_10ms = np.sum(np.abs(offsets) < 10000)
    under_100ms = np.sum(np.abs(offsets) < 100000)
    
    print(f"\nOffset Distribution:")
    print(f"  < 1ms:   {under_1ms:4d} samples ({100*under_1ms/len(offsets):5.1f}%)")
    print(f"  < 10ms:  {under_10ms:4d} samples ({100*under_10ms/len(offsets):5.1f}%)")
    print(f"  < 100ms: {under_100ms:4d} samples ({100*under_100ms/len(offsets):5.1f}%)")
    
    # Analyze well-synchronized data (< 1ms)
    synced = offsets[np.abs(offsets) < 1000]
    if len(synced) > 10:
        print(f"\n--- Well-Synchronized Period (|offset| < 1ms) ---")
        print(f"  Samples: {len(synced)}")
        print(f"  Mean: {np.mean(synced):.3f} μs")
        print(f"  Median: {np.median(synced):.3f} μs")
        print(f"  Std Dev: {np.std(synced):.3f} μs")
        print(f"  RMS: {np.sqrt(np.mean(synced**2)):.3f} μs")
        print(f"  Peak-to-Peak: {np.max(synced) - np.min(synced):.3f} μs")
        
        # Jitter for synchronized data
        if len(synced) > 1:
            jitter = np.diff(synced)
            print(f"  Jitter (mean): {np.mean(np.abs(jitter)):.3f} μs")
            print(f"  Jitter (std): {np.std(jitter):.3f} μs")
    
    # Path delay statistics
    if len(delays) > 0:
        delays = np.array(delays)
        print(f"\nPath Delay:")
        print(f"  Samples: {len(delays)}")
        print(f"  Mean: {np.mean(delays):.3f} μs")
        print(f"  Median: {np.median(delays):.3f} μs")
        print(f"  Std Dev: {np.std(delays):.3f} μs")
        print(f"  Range: {np.min(delays):.3f} to {np.max(delays):.3f} μs")
    
    print("=" * 60)

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 analyze_ptp.py <csv_file>")
        sys.exit(1)
    
    analyze_ptp_stats(sys.argv[1])
