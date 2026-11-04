# Wise-Linux-studio
# Wise Linux Studio (Alpha/Beta Release)
> **Automated GPU VFIO Passthrough & Zero-Touch Ghost Windows 11 VM Manager**
> Wise Linux Studio is a simple GUI that builds and runs a Windows 11 virtual machine on Fedora (libvirt / QEMU / KVM), with a fully unattended install. For users with two GPUs, it can also prepare (isolate) a secondary GPU for VFIO. Attaching that GPU to the VM is the next milestone.
Linux has great tools for each of these steps, but they are scattered and complex. This project puts them in one simple window.
🧪 Early beta (v0.1). GPU isolation (buttons 1–4) edits boot settings and is experimental. See Safety before using it.
✨ Features
GPU passthrough (VFIO), in progress: on a dual-GPU desktop, the tool can prepare your dedicated GPU for VFIO (Virtual Function I/O), the technique that lets a Windows VM use real hardware at near-native performance. Attaching the isolated GPU to the VM is not implemented yet: the VM currently uses a virtual display. (Experimental, see Safety & status.)
Anti-cheat games (untested): The VM builder hides the hypervisor flag and passes your host's motherboard and BIOS identifiers to Windows so the VM looks less like a VM. This is designed to let many anti-cheat games run. Kernel-level anti-cheats such as Riot Vanguard (Valorant) block virtual machines and are expected to fail. Results vary per game and can change with any update, and using these techniques may violate a game's terms of service, so use them at your own risk. Not tested yet: check your game before relying on it.
Zero-touch Windows 11 install: pick an ISO, press one button. TPM and UEFI are handled for you.
Auto or manual resources: 50% of RAM and 60 GB thin-provisioned disk by default, or set your own.
Daily-use workflow: build once, then launch your Windows VM with one click. Your files and apps stay.
Read-only GPU & IOMMU scanner: shows every GPU, its IOMMU group, and whether it can be isolated. Writes nothing.
Built-in safety lock: GPU isolation stays locked unless a safe secondary GPU is found. The GPU running your screen is never touched.
Verify before change: the GRUB step re-scans by itself and aborts if the hardware changed since you scanned.
Backups and Restore: the original GRUB config is saved permanently, and one button undoes the tool's changes.
Least privilege: scanning needs no root; every system-changing action asks for your authentication via pkexec.
Sleep protection: the viewer runs under systemd-inhibit so the laptop doesn't suspend with the VM running.
🎯 Which buttons do I need?
You want
Use
A Windows desktop inside Fedora (most users)
5. Build Ghost VM once, then 6. Launch Gaming VM
Windows with a real GPU for gaming
Not available yet: buttons 1 → 2 → 3 only prepare the GPU, attaching it to the VM is still being built
Right now the VM always uses emulated graphics (QXL): fine for office work and apps, weak for games.
🖥 Supported platform & recommended hardware
Distro: Fedora only (tested on Fedora KDE). The scripts rely on Fedora tools and paths (grubby, grub2-mkconfig, BLS boot entries, dnf). Other distributions are not supported.
VM only (buttons 5–6): any Fedora PC or laptop with virtualization enabled.
GPU passthrough (buttons 1–3), recommended setup: a desktop with two GPUs: the CPU's integrated GPU (iGPU) plus a dedicated GPU (NVIDIA or AMD). Plug your monitor into the motherboard (iGPU) port so Linux keeps a display, and the dedicated GPU is handed to Windows.
Needs UEFI, and VT-d / AMD-Vi enabled in BIOS.
Laptops and PCs with only an integrated GPU: passthrough is intentionally locked, because isolating the only GPU would leave the host without a display. Use the VM-only path.
Single dedicated GPU (no iGPU): single_gpu_hooks.sh exists as an unfinished script and is not connected to the VM builder.
Two dedicated GPUs and AMD-only systems are untested.
🚀 Quick start
git clone https://github.com/<your-username>/wise-linux.git
cd wise-linux
chmod 755 *.sh          # the GUI refuses scripts that are group/world-writable
python3 wise_linux_gui.py
You need:
Fedora with virtualization enabled in BIOS (VT-x / AMD-V), 12 GB+ RAM (the builder refuses to run below that), ~80 GB free disk
A Windows 11 ISO from Microsoft: https://www.microsoft.com/software-download/windows11
virtio-win.iso in the project folder: https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso
For GPU isolation only: IOMMU on in BIOS (VT-d / AMD-Vi), a second GPU, and your monitor plugged into the GPU you keep for Linux (e.g. the motherboard port)
sudo dnf install @virtualization python3-tkinter virt-viewer swtpm edk2-ovmf xorriso ShellCheck
🛡 Safety & status
Be honest with yourself before using buttons 1–4:
They edit boot arguments as root. A mistake can stop your PC from booting normally.
Keep a Linux live USB and a backup ready. Don't try it on your only machine.
Buttons 5–6 (VM only) do not touch GRUB and are much lower risk.
The code was written with AI assistance and only partially reviewed.
What has been tested:
Area
Status
Fedora laptop, single Intel iGPU
✅ GUI, read-only scan, safety lock, Windows 11 unattended install
Desktop with two GPUs
❌ Not tested yet
Real GPU isolation (Setup GRUB / Initramfs)
❌ Not tested on dual-GPU hardware yet
AMD GPUs / other distros
❌ Not tested
🆘 Rescue: PC won't boot properly after isolation
At the GRUB menu press e on the boot entry.
On the linux line, delete vfio-pci.ids=... (and intel_iommu=on iommu=pt rd.driver.pre=vfio-pci).
Press Ctrl+X to boot once without them.
Run Restore System in the tool, or copy /var/lib/wise-linux/grub.default.orig back to /etc/default/grub and regenerate GRUB.
No desktop at all? Boot a Linux live USB, mount your root partition and restore the same file.
Known issues
Suspending while the VM runs froze the desktop in testing. systemd-inhibit is used, but lid-close behaviour needs more testing.
"Save & Pause VM" (managedsave) is blocked with a passed-through GPU, as it is generally unsupported.
Fedora uses BLS boot entries. Whether grub2-mkconfig alone updates them correctly is still being verified; grubby may replace it.
Some AMD GPUs have a reset bug and may need a host reboot.
Boot-GPU detection uses boot_vga. If your BIOS makes the dedicated GPU primary, the other GPU becomes the candidate. Read the scan table before pressing Setup GRUB.
Single-GPU mode (single_gpu_hooks.sh) is unfinished and not connected to anything. Do not use it.
📁 Project layout
wise_linux_gui.py      GUI
gpu_detect.sh          Read-only GPU / IOMMU scanner
grub_setup.sh          Adds VFIO boot args (re-verifies, backs up)
initramfs_setup.sh     Rebuilds initramfs for VFIO
restore_system.sh      Undo changes
vm_builder.sh          Builds the Windows 11 VM (unattended)
create_debloat_iso.sh  Builds the answer ISO
🤝 Contributing
Reviews from people who know VFIO, libvirt or Fedora boot internals are very welcome. Open an issue with your hardware (CPU, GPUs, Fedora version) and the scan output. Logs from real machines are the most valuable contribution right now.
