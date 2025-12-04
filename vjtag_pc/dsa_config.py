#!/usr/bin/env python3
"""
DSA Configuration Helper - Memory-Mapped Register Access

Provides high-level functions for configuring and monitoring the DSA
via memory-mapped registers (0x0000-0x003F).

Usage:
    from dsa_config import DSAConfig
    
    dsa = DSAConfig('localhost', 2540)
    dsa.configure(width=256, height=256, scale=0.75)
    dsa.start()
    dsa.wait_done()
    perf = dsa.get_performance()
"""

import time
import socket
from typing import Dict, Tuple, Optional

# Register addresses (word-aligned)
REG_CFG_WIDTH       = 0x0000
REG_CFG_HEIGHT      = 0x0004
REG_CFG_SCALE_Q8_8  = 0x0008
REG_CFG_MODE        = 0x000C
REG_STATUS          = 0x0010
REG_SIMD_N          = 0x0014
REG_PERF_FLOPS      = 0x0018
REG_PERF_MEM_RD     = 0x001C
REG_PERF_MEM_WR     = 0x0020
REG_STEP_CTRL       = 0x0024
REG_STEP_EXPOSE     = 0x0028
REG_ERR_CODE        = 0x002C
REG_IMG_IN_BASE     = 0x0030
REG_IMG_OUT_BASE    = 0x0034
REG_CRC_CTRL        = 0x0038
REG_CRC_VALUE       = 0x003C

# CFG_MODE bit definitions
MODE_START          = 0x01
MODE_SIMD           = 0x02

# STEP_CTRL values
STEP_RUN            = 0x00
STEP_SINGLE         = 0x01
STEP_PAUSE          = 0x02

# CRC_CTRL bit definitions
CRC_IN_ENABLE       = 0x01
CRC_OUT_ENABLE      = 0x02


class DSAConfig:
    """High-level interface to DSA memory-mapped registers"""
    
    def __init__(self, host: str = 'localhost', port: int = 2540):
        """
        Initialize DSA configuration interface
        
        Args:
            host: JTAG server hostname
            port: JTAG server port
        """
        self.host = host
        self.port = port
        self.conn = None
        self.connect()
    
    def connect(self):
        """Establish connection to JTAG server"""
        try:
            self.conn = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.conn.connect((self.host, self.port))
            print(f"✓ Connected to JTAG server at {self.host}:{self.port}")
        except Exception as e:
            print(f"✗ Failed to connect: {e}")
            raise
    
    def disconnect(self):
        """Close connection to JTAG server"""
        if self.conn:
            self.conn.close()
            self.conn = None
    
    def _send_command(self, cmd: str) -> str:
        """Send command to JTAG server and receive response"""
        self.conn.sendall((cmd + '\n').encode('ascii'))
        response = self.conn.recv(1024).decode('ascii').strip()
        return response
    
    def _write_byte(self, addr: int, value: int):
        """Write single byte to address"""
        # SETADDR
        addr_bin = format(addr, '016b')
        self._send_command(f"SETADDR {addr_bin}")
        
        # WRITE
        data_bin = format(value & 0xFF, '08b')
        self._send_command(f"WRITE {data_bin}")
    
    def _read_byte(self, addr: int) -> int:
        """Read single byte from address"""
        # SETADDR
        addr_bin = format(addr, '016b')
        self._send_command(f"SETADDR {addr_bin}")
        
        # READ
        response = self._send_command("READ")
        # Response format: "XX\n" (hex value)
        return int(response, 16)
    
    def write_word16(self, addr: int, value: int):
        """Write 16-bit word (little-endian)"""
        self._write_byte(addr, value & 0xFF)
        self._write_byte(addr + 1, (value >> 8) & 0xFF)
    
    def write_word32(self, addr: int, value: int):
        """Write 32-bit word (little-endian)"""
        for i in range(4):
            self._write_byte(addr + i, (value >> (8 * i)) & 0xFF)
    
    def read_word16(self, addr: int) -> int:
        """Read 16-bit word (little-endian)"""
        low = self._read_byte(addr)
        high = self._read_byte(addr + 1)
        return (high << 8) | low
    
    def read_word32(self, addr: int) -> int:
        """Read 32-bit word (little-endian)"""
        value = 0
        for i in range(4):
            byte_val = self._read_byte(addr + i)
            value |= (byte_val << (8 * i))
        return value
    
    # ========================================================================
    # Configuration Methods
    # ========================================================================
    
    def configure(self, 
                  width: int = 256, 
                  height: int = 256, 
                  scale: float = 0.75,
                  img_in_base: int = 0x0080,
                  img_out_base: int = 0x8000,
                  simd_lanes: int = 1):
        """
        Configure DSA parameters
        
        Args:
            width: Input image width (pixels)
            height: Input image height (pixels)
            scale: Scale factor (0.0-1.0), converted to Q8.8
            img_in_base: Input image base address (default: after registers)
            img_out_base: Output image base address (default: 0x8000)
            simd_lanes: Number of SIMD lanes (1, 4, 8...)
        """
        print("Configuring DSA...")
        
        # CFG_WIDTH
        self.write_word16(REG_CFG_WIDTH, width)
        print(f"  Width: {width}")
        
        # CFG_HEIGHT
        self.write_word16(REG_CFG_HEIGHT, height)
        print(f"  Height: {height}")
        
        # CFG_SCALE_Q8_8 (convert float to Q8.8)
        scale_q8_8 = int(scale * 256)
        self.write_word16(REG_CFG_SCALE_Q8_8, scale_q8_8)
        print(f"  Scale: {scale} (Q8.8: 0x{scale_q8_8:04X})")
        
        # IMG_IN_BASE
        self.write_word32(REG_IMG_IN_BASE, img_in_base)
        print(f"  Input Base: 0x{img_in_base:08X}")
        
        # IMG_OUT_BASE
        self.write_word32(REG_IMG_OUT_BASE, img_out_base)
        print(f"  Output Base: 0x{img_out_base:08X}")
        
        # SIMD_N
        self._write_byte(REG_SIMD_N, simd_lanes)
        print(f"  SIMD Lanes: {simd_lanes}")
        
        print("✓ Configuration complete")
    
    def start(self, simd_mode: bool = False):
        """
        Start DSA processing
        
        Args:
            simd_mode: True for SIMD mode, False for Sequential
        """
        mode_val = MODE_START
        if simd_mode:
            mode_val |= MODE_SIMD
        
        self._write_byte(REG_CFG_MODE, mode_val)
        mode_str = "SIMD" if simd_mode else "Sequential"
        print(f"✓ DSA started in {mode_str} mode")
    
    def reset(self):
        """Reset DSA to idle state"""
        self._write_byte(REG_CFG_MODE, 0x00)
        print("✓ DSA reset")
    
    # ========================================================================
    # Status Monitoring
    # ========================================================================
    
    def get_status(self) -> Dict[str, any]:
        """
        Read DSA status register
        
        Returns:
            Dictionary with: idle, busy, done, error, progress, fsm_state
        """
        status_bytes = [self._read_byte(REG_STATUS + i) for i in range(4)]
        
        status_word = status_bytes[0]
        
        return {
            'idle': bool(status_word & 0x01),
            'busy': bool(status_word & 0x02),
            'done': bool(status_word & 0x04),
            'error': bool(status_word & 0x08),
            'progress': status_bytes[1],
            'fsm_state': (status_bytes[3] << 8) | status_bytes[2]
        }
    
    def wait_done(self, timeout: float = 30.0, poll_interval: float = 0.1) -> bool:
        """
        Wait for DSA to complete processing
        
        Args:
            timeout: Maximum wait time (seconds)
            poll_interval: Status polling interval (seconds)
        
        Returns:
            True if completed successfully, False on error/timeout
        """
        start_time = time.time()
        
        while (time.time() - start_time) < timeout:
            status = self.get_status()
            
            if status['error']:
                err_code = self.read_word16(REG_ERR_CODE)
                print(f"✗ DSA Error: 0x{err_code:04X}")
                return False
            
            if status['done']:
                print(f"✓ DSA completed (Progress: {status['progress']}%)")
                return True
            
            if status['busy']:
                print(f"  Processing... {status['progress']}%", end='\r')
            
            time.sleep(poll_interval)
        
        print(f"✗ Timeout after {timeout}s")
        return False
    
    # ========================================================================
    # Performance Monitoring
    # ========================================================================
    
    def get_performance(self) -> Dict[str, int]:
        """
        Read performance counters
        
        Returns:
            Dictionary with: flops, mem_rd, mem_wr
        """
        return {
            'flops': self.read_word32(REG_PERF_FLOPS),
            'mem_rd': self.read_word32(REG_PERF_MEM_RD),
            'mem_wr': self.read_word32(REG_PERF_MEM_WR)
        }
    
    def print_performance(self):
        """Print performance counters in readable format"""
        perf = self.get_performance()
        print("\n=== Performance Counters ===")
        print(f"  FLOPs:        {perf['flops']:,}")
        print(f"  Memory Reads: {perf['mem_rd']:,}")
        print(f"  Memory Writes:{perf['mem_wr']:,}")
    
    # ========================================================================
    # Advanced Features
    # ========================================================================
    
    def enable_crc(self, input_crc: bool = False, output_crc: bool = False):
        """
        Enable CRC calculation for transfers
        
        Args:
            input_crc: Enable CRC for input transfers
            output_crc: Enable CRC for output transfers
        """
        crc_ctrl = 0
        if input_crc:
            crc_ctrl |= CRC_IN_ENABLE
        if output_crc:
            crc_ctrl |= CRC_OUT_ENABLE
        
        self._write_byte(REG_CRC_CTRL, crc_ctrl)
        print(f"✓ CRC enabled: IN={input_crc}, OUT={output_crc}")
    
    def get_crc(self) -> int:
        """Read calculated CRC32 value"""
        return self.read_word32(REG_CRC_VALUE)
    
    def set_stepping_mode(self, mode: int):
        """
        Set stepping mode for debug
        
        Args:
            mode: STEP_RUN (0), STEP_SINGLE (1), or STEP_PAUSE (2)
        """
        self._write_byte(REG_STEP_CTRL, mode)
        mode_names = {STEP_RUN: "RUN", STEP_SINGLE: "SINGLE", STEP_PAUSE: "PAUSE"}
        print(f"✓ Stepping mode: {mode_names.get(mode, 'UNKNOWN')}")
    
    def get_step_expose(self) -> int:
        """Read step expose pointer for debug"""
        return self.read_word32(REG_STEP_EXPOSE)


# ============================================================================
# Example Usage
# ============================================================================

if __name__ == "__main__":
    # Create DSA interface
    dsa = DSAConfig('localhost', 2540)
    
    try:
        # Configure for 256x256 image with 0.75 scale factor
        dsa.configure(
            width=256,
            height=256,
            scale=0.75,
            simd_lanes=1
        )
        
        # Enable output CRC
        dsa.enable_crc(output_crc=True)
        
        # Start processing
        dsa.start(simd_mode=False)
        
        # Wait for completion
        if dsa.wait_done(timeout=30.0):
            # Print performance
            dsa.print_performance()
            
            # Check CRC
            crc = dsa.get_crc()
            print(f"\nOutput CRC32: 0x{crc:08X}")
        
    finally:
        dsa.disconnect()
