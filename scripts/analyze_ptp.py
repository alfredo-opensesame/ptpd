#!/usr/bin/env python3
import csv
import sys
import numpy as np
from pathlib import Path

def analyze_ptp_stats(csv_file):
    """Analyze PTP statistics from CSV file."""
    
    if not Path(csv_file).exists():
        print(f"Error: File {csv_file} not found")
        return
    
    offsets = []
    delays = []
    
    with open(csv_file, 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            if len(row) < 10 or row[1] != 'slv':  # Only analyze slave state
                continue
            
            try:
                # Assuming offset is in column 4 and delay in column 5 (in seconds)
                offset_s = float(row[4])
                delay_s = float(row[5])
                
                # Convert to microseconds
                offset_us = offset_s * 1e6
                delay_us = delay_s * 1e6
                
                # Filter out obvious outliers (> 10ms)
                if abs(offset_us) < 10000:
                    offsets.append(offset_us)
                if abs(delay_us) < 10000:
                    delays.append(delay_us)
                    
            except (ValueError, IndexError):
                continue
    
    if not offsets:
        print("No valid offset data found")
        return
        
    offsets = np.array(offsets)
    delays = np.array(delays)
    
    print("=" * 60)
    print("PTP Performance Analysis (Baseline - Kalman Filter Disabled)")
    print("=" * 60)
    
    print(f"\nOffset From Master")
    print(f"  Count: {len(offsets)}")
    print(f"  Mean: {np.mean(offsets):.3f} μs | Median: {np.median(offsets):.3f} μs")
    print(f"  Std Dev: {np.std(offsets):.3f} μs | RMS: {np.sqrt(np.mean(offsets**2)):.3f} μs")
    print(f"  Peak-to-Peak: {np.max(offsets) - np.min(offsets):.3f} μs")
    
    # Calculate jitter (difference between consecutive samples)
    if len(offsets) > 1:
        jitter = np.diff(offsets)
        print(f"  Jitter (mean): {np.mean(np.abs(jitter)):.3f} μs | Jitter (std): {np.std(jitter):.3f} μs")
    
    # Allan Deviation approximation (simplified)
    if len(offsets) > 10:
        allan_dev = np.std(offsets) / np.sqrt(2)
        print(f"  Allan Deviation: {allan_dev:.3f} μs")
    
    if len(delays) > 0:
        print(f"\nPath Delay")
        print(f"  Count: {len(delays)}")
        print(f"  Mean: {np.mean(delays):.3f} μs | Median: {np.median(delays):.3f} μs")
        print(f"  Std Dev: {np.std(delays):.3f} μs")
    
    print("=" * 60)

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 analyze_ptp.py <csv_file>")
        sys.exit(1)
    
    analyze_ptp_stats(sys.argv[1])