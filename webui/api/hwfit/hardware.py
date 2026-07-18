"""ARES Hardware Detection — scans the host system for GPU, RAM, and CPU specs.

Ported from Odysseus services/hwfit/hardware.py.
Adapted for ARES: uses subprocess/subprocess for macOS, respects ARES config.
"""

from __future__ import annotations

import logging
import os
import platform
import subprocess
from dataclasses import dataclass, field
from typing import Optional

logger = logging.getLogger(__name__)


@dataclass
class HardwareSpec:
    """Detected hardware specification for model fitting."""
    gpu_name: str = ""
    gpu_vram_gb: float = 0.0
    gpu_cores: int = 0
    gpu_backend: str = ""  # cuda, rocm, metal, cpu_x86, cpu_arm
    total_ram_gb: float = 0.0
    cpu_name: str = ""
    cpu_arch: str = ""
    os_name: str = ""
    os_version: str = ""
    is_apple_silicon: bool = False
    gpu_bandwidth_gb_s: float = 0.0  # memory bandwidth in GB/s
    available_ram_gb: float = 0.0  # total_ram_gb minus OS overhead

    def to_dict(self) -> dict:
        return {
            "gpu_name": self.gpu_name,
            "gpu_vram_gb": self.gpu_vram_gb,
            "gpu_cores": self.gpu_cores,
            "gpu_backend": self.gpu_backend,
            "total_ram_gb": self.total_ram_gb,
            "cpu_name": self.cpu_name,
            "cpu_arch": self.cpu_arch,
            "os_name": self.os_name,
            "os_version": self.os_version,
            "is_apple_silicon": self.is_apple_silicon,
            "gpu_bandwidth_gb_s": self.gpu_bandwidth_gb_s,
            "available_ram_gb": self.available_ram_gb,
        }


def detect_hardware() -> HardwareSpec:
    """Detect the host system's hardware capabilities.

    Returns a HardwareSpec with GPU info, RAM, CPU, and backend details.
    Works on macOS (Apple Silicon + Intel), Linux (NVIDIA + AMD), and Windows.
    """
    spec = HardwareSpec()
    spec.os_name = platform.system()
    spec.os_version = platform.release()
    spec.cpu_arch = platform.machine()

    # Detect total RAM
    spec.total_ram_gb = _detect_total_ram()
    spec.available_ram_gb = spec.total_ram_gb * 0.85  # Reserve 15% for OS

    # Detect GPU
    if spec.os_name == "Darwin":
        _detect_macos_gpu(spec)
    elif spec.os_name == "Linux":
        _detect_linux_gpu(spec)
    elif spec.os_name == "Windows":
        _detect_windows_gpu(spec)

    # Detect CPU name
    spec.cpu_name = _detect_cpu_name()

    return spec


def _detect_total_ram() -> float:
    """Detect total system RAM in GB."""
    try:
        if platform.system() == "Darwin":
            result = subprocess.run(
                ["sysctl", "-n", "hw.memsize"],
                capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0:
                return int(result.stdout.strip()) / (1024 ** 3)
        elif platform.system() == "Linux":
            with open("/proc/meminfo") as f:
                for line in f:
                    if line.startswith("MemTotal:"):
                        return int(line.split()[1]) / (1024 ** 2)  # KB to GB
    except Exception as e:
        logger.debug(f"RAM detection failed: {e}")
    return 0.0


def _detect_cpu_name() -> str:
    """Detect CPU model name."""
    try:
        if platform.system() == "Darwin":
            result = subprocess.run(
                ["sysctl", "-n", "machdep.cpu.brand_string"],
                capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0:
                return result.stdout.strip()
        elif platform.system() == "Linux":
            with open("/proc/cpuinfo") as f:
                for line in f:
                    if line.startswith("model name"):
                        return line.split(":", 1)[1].strip()
    except Exception:
        pass
    return platform.processor() or "Unknown"


def _detect_macos_gpu(spec: HardwareSpec):
    """Detect Apple Silicon GPU info on macOS."""
    try:
        # Check for Apple Silicon
        result = subprocess.run(
            ["sysctl", "-n", "hw.optional.arm64"],
            capture_output=True, text=True, timeout=5
        )
        is_arm = result.returncode == 0 and result.stdout.strip() == "1"

        if is_arm or platform.machine() == "arm64":
            spec.is_apple_silicon = True
            spec.gpu_backend = "metal"

            # Get chip name from system_profiler
            result = subprocess.run(
                ["system_profiler", "SPHardwareDataType"],
                capture_output=True, text=True, timeout=10
            )
            if result.returncode == 0:
                for line in result.stdout.splitlines():
                    line = line.strip()
                    if "Chip:" in line:
                        spec.gpu_name = line.split("Chip:", 1)[1].strip()
                    elif "Memory:" in line:
                        mem_str = line.split("Memory:", 1)[1].strip()
                        # Parse "16 GB" etc.
                        try:
                            spec.total_ram_gb = float(mem_str.split()[0])
                            spec.available_ram_gb = spec.total_ram_gb * 0.85
                        except (ValueError, IndexError):
                            pass
                    elif "Total Number of Cores:" in line:
                        try:
                            spec.gpu_cores = int(line.split(":")[-1].strip())
                        except ValueError:
                            pass

            # Apple Silicon uses unified memory — GPU VRAM = total RAM
            if spec.total_ram_gb > 0 and spec.is_apple_silicon:
                # Reserve some RAM for system; GPU can use ~75% of total for large models
                spec.gpu_vram_gb = spec.total_ram_gb * 0.75
                if not spec.gpu_name:
                    spec.gpu_name = f"Apple Silicon ({spec.total_ram_gb:.0f}GB unified)"

            # Look up bandwidth
            from api.hwfit.fit import _lookup_bandwidth
            bw = _lookup_bandwidth(spec.to_dict())
            if bw:
                spec.gpu_bandwidth_gb_s = bw

        else:
            # Intel Mac — check for discrete GPU
            spec.gpu_backend = "cpu_x86"
            _detect_discrete_gpu(spec)

    except Exception as e:
        logger.debug(f"macOS GPU detection failed: {e}")
        spec.gpu_backend = "cpu_x86"


def _detect_linux_gpu(spec: HardwareSpec):
    """Detect GPU on Linux (NVIDIA/AMD)."""
    # Try nvidia-smi first
    try:
        result = subprocess.run(
            ["nvidia-smi", "--query-gpu=name,memory.total", "--format=csv,noheader"],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0 and result.stdout.strip():
            parts = result.stdout.strip().split(",")
            spec.gpu_name = parts[0].strip()
            spec.gpu_backend = "cuda"
            if len(parts) >= 2:
                mem_str = parts[1].strip()
                # Parse "16384 MiB" etc.
                try:
                    spec.gpu_vram_gb = float(mem_str.split()[0]) / 1024
                except (ValueError, IndexError):
                    pass
            return
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass

    # Try AMD ROCm
    try:
        result = subprocess.run(
            ["rocm-smi", "--showproductname"],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0:
            spec.gpu_backend = "rocm"
            for line in result.stdout.splitlines():
                if "Card" in line or "GPU" in line:
                    spec.gpu_name = line.split(":")[-1].strip()
                    break
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass

    if not spec.gpu_backend:
        spec.gpu_backend = "cpu_x86"


def _detect_windows_gpu(spec: HardwareSpec):
    """Detect GPU on Windows."""
    try:
        result = subprocess.run(
            ["nvidia-smi", "--query-gpu=name,memory.total", "--format=csv,noheader"],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0 and result.stdout.strip():
            parts = result.stdout.strip().split(",")
            spec.gpu_name = parts[0].strip()
            spec.gpu_backend = "cuda"
            if len(parts) >= 2:
                mem_str = parts[1].strip()
                try:
                    spec.gpu_vram_gb = float(mem_str.split()[0]) / 1024
                except (ValueError, IndexError):
                    pass
            return
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass

    spec.gpu_backend = "cpu_x86"


def _detect_discrete_gpu(spec: HardwareSpec):
    """Try to detect a discrete GPU (for Intel Macs or secondary GPUs)."""
    try:
        result = subprocess.run(
            ["system_profiler", "SPDisplaysDataType"],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0:
            for line in result.stdout.splitlines():
                line = line.strip()
                if "Chipset Model:" in line:
                    if not spec.gpu_name or "Apple" not in spec.gpu_name:
                        spec.gpu_name = line.split("Chipset Model:", 1)[1].strip()
                elif "VRAM (Total):" in line or "VRAM (Dynamic, Max):" in line:
                    try:
                        vram_str = line.split(":", 1)[1].strip()
                        if "MB" in vram_str:
                            spec.gpu_vram_gb = float(vram_str.split()[0]) / 1024
                        elif "GB" in vram_str:
                            spec.gpu_vram_gb = float(vram_str.split()[0])
                    except (ValueError, IndexError):
                        pass
    except Exception:
        pass