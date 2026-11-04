# Wise-Linux-studio
# Wise Linux Studio (Alpha/Beta Release)
> **Automated GPU VFIO Passthrough & Zero-Touch Ghost Windows 11 VM Manager**
Wise Linux Studio

A simple GUI for building and running Windows 11 virtual machines on Fedora Linux, with experimental GPU passthrough preparation.

Wise Linux Studio brings the tools needed to create and manage a Windows 11 virtual machine into one simple graphical interface.

It uses libvirt, QEMU, and KVM to build Windows VMs with a fully unattended installation. On desktop systems with two GPUs, it can also prepare a secondary GPU for VFIO passthrough.

Linux already provides powerful tools for virtualization and GPU passthrough, but configuring them can be complicated. This project aims to make the process easier by bringing the essential steps together in one window.

«🧪 Early beta — v0.1

GPU isolation is experimental. Attaching a passed-through GPU to the VM is not implemented yet.

See "Safety & Status" (#-safety--status) before using GPU isolation.»

---

✨ Features

🖥️ Windows 11 Virtual Machine

- Zero-touch installation: Select a Windows 11 ISO and start the installation with one button.
- Automatic UEFI and TPM: The VM is configured with the requirements needed for Windows 11.
- Automatic resource allocation: Uses 50% of available RAM and a 60 GB thin-provisioned disk by default.
- Manual configuration: Choose your own RAM and disk settings.
- One-click launch: Build the VM once, then launch it whenever you need Windows.
- Persistent installation: Your Windows files, applications, and VM configuration stay available between sessions.

🎮 GPU Passthrough (VFIO) — In Progress

On supported dual-GPU desktops, Wise Linux Studio can prepare a dedicated GPU for VFIO.

VFIO allows a virtual machine to access real hardware directly, potentially providing near-native GPU performance.

Current status:

- GPU detection and IOMMU scanning are implemented.
- GPU isolation preparation is available through buttons 1–3.
- GPU isolation modifies boot configuration and is experimental.
- Attaching the isolated GPU to the Windows VM is not implemented yet.
- The VM currently uses emulated QXL graphics.

Important: The current VM is suitable for office work and applications, but its emulated graphics are not suitable for demanding gaming.

🔍 GPU & IOMMU Scanner

- Read-only GPU detection.
- Displays detected GPUs and their IOMMU groups.
- Shows whether a GPU can potentially be isolated.
- Scanning does not modify system configuration.
- Does not require root privileges.

🛡️ Safety Features

- Built-in safety lock: GPU isolation remains locked unless a suitable secondary GPU is detected.
- Host GPU protection: The GPU currently driving the Linux display is never selected for isolation.
- Verify before changing: The GRUB setup script rescans hardware and aborts if the configuration has changed since the initial scan.
- Automatic backups: The original GRUB configuration is saved before modification.
- Restore System: A dedicated option restores the original boot configuration.
- Least privilege: System-changing operations request authentication through "pkexec".
- Sleep protection: The VM viewer uses "systemd-inhibit" to prevent automatic suspension while the VM is running.

🎯 Anti-Cheat Compatibility — Untested

The VM builder hides the hypervisor flag and passes the host motherboard and BIOS identifiers to Windows.

These techniques are intended to improve compatibility with some games that detect virtual machines.

However:

- Anti-cheat compatibility has not been tested.
- Kernel-level anti-cheats such as Riot Vanguard are expected to block virtual machines.
- Compatibility can change after game or anti-cheat updates.
- These techniques may violate individual games' terms of service.

Do not rely on anti-cheat compatibility without checking the specific game.

---

🎯 Which Buttons Do I Need?

Goal| Buttons
Build a Windows desktop inside Fedora| 5. Build Ghost VM
Launch the Windows VM| 6. Launch Gaming VM
Prepare a secondary GPU for passthrough| 1 → 2 → 3
Attach a real GPU to the Windows VM| Not available yet

VM-Only Workflow

For most users, the recommended workflow is:

1. Press 5. Build Ghost VM to create the Windows VM.
2. Press 6. Launch Gaming VM whenever you want to use Windows.

Buttons 5–6 do not modify GRUB and are significantly lower risk than GPU isolation.

GPU Passthrough Workflow

Buttons 1–3 prepare the secondary GPU for VFIO.

However, the actual GPU attachment and gaming workflow are still under development.

---

🖥️ Supported Platform & Recommended Hardware

Operating System

- Fedora Linux only.
- Tested on Fedora KDE.
- Other distributions are currently unsupported.

The scripts rely on Fedora-specific tools and paths, including:

- "grubby"
- "grub2-mkconfig"
- BLS boot entries
- "dnf"

Virtual Machine Requirements

For buttons 5–6:

- Fedora Linux.
- Hardware virtualization enabled in BIOS.
- At least 12 GB of RAM.
- Approximately 80 GB of free disk space.
- A Windows 11 ISO.

The VM builder refuses to run with less than 12 GB of RAM.

Recommended GPU Passthrough Setup

For buttons 1–3, the recommended configuration is:

- A desktop PC with two GPUs.
- An integrated GPU (iGPU) for Fedora.
- A dedicated NVIDIA or AMD GPU for Windows.
- UEFI firmware.
- VT-d or AMD-Vi enabled in BIOS.

Connect your monitor to the motherboard's display output so Fedora continues using the integrated GPU while the dedicated GPU is prepared for Windows.

Unsupported or Untested Configurations

Configuration| Status
Fedora laptop with a single Intel iGPU| VM-only workflow tested
Desktop with two GPUs| Not tested yet
Real GPU isolation| Not tested on dual-GPU hardware
AMD GPUs| Untested
Two dedicated GPUs| Untested
Other Linux distributions| Unsupported
Single dedicated GPU without an iGPU| Unfinished

The single-GPU implementation ("single_gpu_hooks.sh") is unfinished and is not connected to the VM builder.

---

🚀 Quick Start

1. Clone the Repository

git clone https://github.com/<your-username>/wise-linux.git
cd wise-linux

2. Prepare the Scripts

chmod 755 *.sh

The GUI refuses to run scripts that are group- or world-writable.

3. Install Dependencies

sudo dnf install @virtualization python3-tkinter virt-viewer swtpm edk2-ovmf xorriso ShellCheck

4. Download the Required ISOs

Windows 11 ISO

Download it from Microsoft:

https://www.microsoft.com/software-download/windows11

VirtIO Windows Drivers

Download the VirtIO driver ISO:

https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso

Place "virtio-win.iso" in the project folder.

5. Launch Wise Linux Studio

python3 wise_linux_gui.py

Requirements Summary

Requirement| VM Only| GPU Isolation
Fedora Linux| Required| Required
Virtualization enabled| Required| Required
12 GB+ RAM| Required| Required
Windows 11 ISO| Required| Required
VirtIO ISO| Required| Required
UEFI| Required| Required
IOMMU enabled| Not required| Required
Secondary GPU| Not required| Required
Monitor connected to host GPU| Not required| Recommended

---

🛡️ Safety & Status

Please understand the risks before using buttons 1–4.

These operations modify boot configuration as root. An incorrect configuration can prevent your system from booting normally.

Before using GPU isolation:

- Keep a Linux live USB ready.
- Back up important files.
- Make sure you can recover your system.
- Do not experiment on your only machine.
- Read the GPU scan results carefully.

Current Testing Status

Area| Status
Fedora laptop with a single Intel iGPU| GUI, read-only scan, safety lock, and unattended Windows 11 installation tested
Desktop with two GPUs| Not tested
GPU isolation and GRUB setup| Not tested on dual-GPU hardware
Initramfs VFIO configuration| Not tested on dual-GPU hardware
AMD GPUs| Untested
Other distributions| Unsupported

The project was developed with AI assistance and has only been partially reviewed.

GPU isolation should be considered experimental until it has been tested and reviewed on real dual-GPU hardware.

---

🆘 Recovery: PC Won't Boot Properly After GPU Isolation

If the system fails to boot normally after GPU isolation, you may be able to boot once without the VFIO boot arguments.

1. Boot Without the VFIO Arguments

At the GRUB menu:

1. Select your Linux boot entry.
2. Press "e" to edit it.
3. Find the line beginning with "linux".
4. Remove the VFIO-related arguments:

vfio-pci.ids=...
intel_iommu=on
iommu=pt
rd.driver.pre=vfio-pci

5. Press "Ctrl + X" to boot once with the modified entry.

2. Restore the Original Configuration

After successfully booting Fedora:

Use Restore System in Wise Linux Studio.

Alternatively, restore the original configuration manually:

sudo cp /var/lib/wise-linux/grub.default.orig /etc/default/grub

Then regenerate the GRUB configuration:

sudo grub2-mkconfig -o /boot/grub2/grub.cfg

Note: Fedora uses Boot Loader Specification (BLS) entries. Whether "grub2-mkconfig" alone correctly updates every relevant boot entry is still being verified. Fedora's boot configuration may require additional recovery steps.

3. If Fedora Cannot Reach the Desktop

Boot from a Linux live USB.

Mount your Fedora root partition and restore the original GRUB configuration from:

/var/lib/wise-linux/grub.default.orig

Then regenerate the boot configuration as appropriate for your Fedora installation.

---

⚠️ Known Issues

- Suspending the system while the VM is running caused the desktop to freeze during testing.
- "systemd-inhibit" is used to prevent automatic suspension, but lid-close behavior still needs more testing.
- Save & Pause VM ("managedsave") is blocked when a GPU is passed through, because this is generally unsupported.
- Fedora uses BLS boot entries. Whether "grub2-mkconfig" alone updates them correctly is still being verified.
- "grubby" may replace or modify boot configuration differently from "grub2-mkconfig".
- Some AMD GPUs have reset issues and may require a host reboot.
- GPU detection uses the "boot_vga" attribute to identify the boot GPU.
- If the BIOS makes the dedicated GPU primary, the scanner may select the other GPU as the candidate.
- Always review the scan table before pressing Setup GRUB.
- Single-GPU mode ("single_gpu_hooks.sh") is unfinished and is not connected to the VM builder.

---

📁 Project Layout

File| Purpose
"wise_linux_gui.py"| Main graphical interface
"gpu_detect.sh"| Read-only GPU and IOMMU scanner
"grub_setup.sh"| Adds VFIO boot arguments, verifies hardware, and creates backups
"initramfs_setup.sh"| Rebuilds initramfs for VFIO
"restore_system.sh"| Restores the original system configuration
"vm_builder.sh"| Builds the Windows 11 VM with unattended installation
"create_debloat_iso.sh"| Builds the Windows answer ISO
"single_gpu_hooks.sh"| Unfinished single-GPU implementation

---

🤝 Contributing

Wise Linux Studio is an early beta, and real hardware testing is one of the most valuable contributions right now.

Reviews and contributions from people familiar with the following are especially welcome:

- VFIO and GPU passthrough.
- libvirt and QEMU.
- Fedora boot internals.
- GRUB and BLS boot entries.
- Initramfs configuration.
- NVIDIA and AMD GPU compatibility.

Reporting Hardware & Testing Results

When opening an issue, please include:

- CPU model.
- GPU models.
- Fedora version.
- Whether the system uses an iGPU or multiple dedicated GPUs.
- The GPU scanner output.
- Relevant logs and error messages.

Real-world testing on dual-GPU desktops will help identify compatibility problems and improve the project's safety.

---

📌 Project Status

Wise Linux Studio is currently an early beta focused on simplifying Windows virtualization on Fedora.

The VM-only workflow is the primary usable feature.

GPU passthrough preparation is experimental, and attaching a real GPU to the VM remains a future milestone.

The goal is to make Windows virtualization on Linux easier without hiding the complexity or risks of the underlying system.
