Wise Linux Studio

Run Windows 11 on Fedora from one simple window, with experimental GPU passthrough preparation.

"status" (https://img.shields.io/badge/status-early%20beta-orange) "platform" (https://img.shields.io/badge/platform-Fedora-51A2DA) "license" (https://img.shields.io/badge/license-MIT-blue)

Wise Linux Studio is a small GUI (Python/Tkinter + shell scripts) that builds and runs a Windows 11 virtual machine on Fedora using libvirt, QEMU and KVM, with a fully unattended install. On desktops with two GPUs it can also prepare a dedicated GPU for VFIO passthrough.

Linux already has powerful tools for virtualization and GPU passthrough, but they are scattered and complicated to configure. This project puts the essential steps in one window, with safety checks and a restore button.

«🧪 Early beta (v0.1). The VM-only workflow (buttons 5 and 6) is the main usable feature. GPU isolation (buttons 1 to 3) edits your boot configuration as root, is experimental, and has not been tested on real dual-GPU hardware yet. Please read the Safety & status section before using it.»

✨ Features

🖥 Windows 11 virtual machine

- Zero-touch install: pick a Windows 11 ISO and press one button.
- UEFI, Secure Boot and a software TPM 2.0 are configured for you.
- Automatic resources: 50% of your RAM and a 60 GB thin-provisioned disk, or set your own values.
- Build once, launch any time. Your Windows files and apps persist between sessions.
- Host protection: the builder refuses to run with less than 12 GB of host RAM, always leaves at least 4.5 GB to Fedora, and needs at least 25 GB of free disk space.

🎮 GPU passthrough (VFIO), experimental

VFIO lets a virtual machine use real hardware directly, which is how near-native GPU performance is reached.

- Buttons 1 to 3 prepare a secondary GPU on a dual-GPU desktop (it is bound to "vfio-pci" at boot).
- When you build the VM after isolating a GPU, the builder attaches it (together with its audio function) only if all checks pass: it is not the boot GPU, IOMMU is active for it, and its current driver is "vfio-pci". Otherwise the VM uses emulated QXL graphics.
- None of this has been tested on real dual-GPU hardware yet.
- Windows shows its output on the monitor connected to the passed-through GPU. The viewer window only shows the emulated display.

🔍 GPU & IOMMU scanner

- Read-only: it changes nothing and needs no root.
- Lists every GPU with its "boot_vga" flag, IOMMU group and whether it can be isolated.
- Warns when a GPU shares its IOMMU group with other devices.

🛡 Safety features

- Safety lock: GPU isolation stays locked unless exactly one suitable secondary GPU is found. The GPU driving your display is never a candidate.
- Verify before changing: the GRUB and initramfs scripts re-scan the hardware by themselves and abort if it changed since your scan.
- Backups: the original GRUB configuration is saved in "/var/lib/wise-linux/" before the first change and is never overwritten.
- Restore System: one button removes what the tool added.
- Least privilege: scanning needs no root; every system-changing step asks for your authentication through "pkexec".
- Script checks: the GUI refuses to run scripts that are symlinks or group/world-writable.
- Sleep protection: the viewer runs under "systemd-inhibit" so the machine does not suspend while the VM runs.

🎯 Anti-cheat compatibility (untested)

The VM builder hides the hypervisor flag and passes your host's motherboard and BIOS identifiers to Windows, so the VM looks less like a VM. This is intended to help with some games that detect virtual machines.

- Compatibility has not been tested.
- Kernel-level anti-cheats such as Riot Vanguard (Valorant) are expected to block virtual machines.
- Results can change with any game or anti-cheat update.
- These techniques may violate a game's terms of service. Use them at your own risk, and check your specific game first.

🎯 Which buttons do I need?

Goal| Buttons
A Windows desktop inside Fedora (most users)| 5. Build Ghost VM once, then 6. Launch Gaming VM
Check your hardware (changes nothing)| 1. Scan GPU
Turn on IOMMU in the kernel (when the scan asks for it)| 2a. Enable IOMMU, reboot, scan again
Isolate a secondary GPU for passthrough| 1, 2, 3, reboot, scan again, then 5 (experimental)
Undo what the tool changed| 4. Restore System, then reboot
Check resources without building anything| Test Mode (Dry-Run)

VM-only workflow (recommended)

1. Press 5. Build Ghost VM and wait for Windows to install itself.
2. Press 6. Launch Gaming VM whenever you want Windows.

GPU passthrough workflow (experimental)

1. In the BIOS: enable VT-d / AMD-Vi, use UEFI, and connect your monitor to the motherboard (iGPU) port.
2. Press 1. Scan GPU. If it reports that IOMMU is off in the kernel, press 2a. Enable IOMMU, reboot, and scan again.
3. Read the scan table yourself. Your dedicated GPU must be marked as a candidate and the GPU driving your screen must not.
4. Press 2. Setup GRUB, then 3. Build Initramfs, then reboot.
5. Press 1. Scan GPU again. The build step only receives the GPU address from a scan made in the same session.
6. Press 5. Build Ghost VM. Connect a cable or switch your monitor input to the dedicated GPU, and install its driver inside Windows.

🖥 Supported platform & recommended hardware

Operating system: Fedora only (tested on Fedora KDE). The scripts use Fedora tools and paths: "grubby", "grub2-mkconfig", BLS boot entries, "dracut", "dnf" and "systemd". Other distributions are not supported.

For buttons 5 and 6: hardware virtualization enabled in the BIOS (VT-x / AMD-V), at least 12 GB of RAM, at least 25 GB of free disk space (about 80 GB recommended), UEFI, and a Windows 11 ISO.

For GPU isolation (buttons 1 to 3): a desktop with two GPUs, the CPU's integrated GPU (iGPU) plus a dedicated NVIDIA or AMD GPU, UEFI, VT-d / AMD-Vi enabled, and the monitor connected to the iGPU port.

Configuration| Status
Fedora laptop with a single Intel iGPU| VM-only workflow tested
Desktop with iGPU + dedicated GPU| Not tested yet
Real GPU isolation and attaching| Not tested on dual-GPU hardware
AMD GPUs| Untested
Two dedicated GPUs| Untested
Single dedicated GPU without an iGPU| Not supported ("single_gpu_hooks.sh" is unfinished and unused)
Other Linux distributions| Unsupported

🚀 Install & run

git clone https://github.com/t11man/Wise-Linux-studio.git

cd Wise-Linux-studio

chmod 755 *.sh      # the GUI refuses scripts that are group/world-writable

python3 wise_linux_gui.py

Install the dependencies first:

sudo dnf install -y @virtualization python3-tkinter virt-viewer swtpm edk2-ovmf xorriso

Optional, for development: "sudo dnf install ShellCheck".

Downloads

- Windows 11 ISO from Microsoft: https://www.microsoft.com/software-download/windows11
- VirtIO drivers (put "virtio-win.iso" in the project folder): https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso

🪟 What the unattended Windows install does

- Needs an English (en-US) Windows 11 ISO that includes the Pro edition. Other languages or editions are not supported yet.
- Wipes the VM's virtual disk only. Your real disks are never touched.
- Creates a local administrator account named after your Linux username, with an empty password and automatic login.
- Windows is not activated. You need your own license.
- Turns off Windows telemetry and the SysMain service.
- Currently installs Steam and starts it in Big Picture mode at logon.

🛡 Safety & status

Understand the risks before using buttons 1 to 4. They change your boot configuration as root. A mistake can stop your PC from booting normally.

- Keep a Linux live USB ready and back up important files.
- Do not experiment on your only machine.
- Read the scan table carefully before pressing 2. Setup GRUB.

Area| Status
GUI, read-only scan, safety lock, unattended Windows 11 install| Tested on a Fedora laptop with a single Intel iGPU
GRUB / initramfs steps and GPU isolation| Not tested on dual-GPU hardware
Attaching the isolated GPU to the VM| Not tested
Anti-cheat compatibility| Not tested
AMD GPUs and other distributions| Untested / unsupported

Treat GPU isolation as experimental until it has been tested and reviewed on real dual-GPU hardware. See How this project was built below for how the code was written and reviewed.

🆘 Recovery: the PC won't boot properly after GPU isolation

1. Boot once without the VFIO arguments. At the GRUB menu:

1. Select your Fedora entry and press "e".
2. On the line starting with "linux", delete "vfio-pci.ids=...", "intel_iommu=on", "iommu=pt" and "rd.driver.pre=vfio-pci".
3. Press Ctrl + X to boot once.

If that still fails, pick an older kernel in the GRUB menu: only the initramfs of the current kernel is rebuilt by the tool.

2. Undo the changes. Once Fedora starts, press 4. Restore System in the tool and reboot. To do it manually:

sudo cp /var/lib/wise-linux/grub.default.orig /etc/default/grub
sudo grubby --info=DEFAULT | grep -o 'vfio-pci.ids=[^ "]*'      # note the value
sudo grubby --update-kernel=ALL --remove-args="intel_iommu=on iommu=pt rd.driver.pre=vfio-pci"
sudo grubby --update-kernel=ALL --remove-args="vfio-pci.ids=XXXX:XXXX,XXXX:XXXX"   # use the value printed above
sudo rm -f /etc/modprobe.d/wise_linux_vfio.conf /etc/dracut.conf.d/wise_linux_vfio.conf
sudo dracut -f
sudo grub2-mkconfig -o /boot/grub2/grub.cfg
sudo reboot

3. If Fedora cannot reach a desktop: boot a Linux live USB, mount your Fedora root partition, and restore "/etc/default/grub" from "/var/lib/wise-linux/grub.default.orig". Remove the two config files above and rebuild the boot configuration for your installation.

⚠️ Known issues

- Suspending the host while the VM runs froze the desktop during early testing. "systemd-inhibit" now prevents automatic suspend, but closing a laptop lid needs more testing.
- Save & Pause VM is blocked when a GPU is passed through, because saving the state of a passed-through GPU is generally unsupported.
- Boot arguments are applied with "grubby" (Fedora BLS entries) and "grub2-mkconfig". This has not been verified on real dual-GPU hardware.
- Some AMD GPUs have a reset bug and may need a host reboot to come back.
- GPU detection relies on "boot_vga". If your BIOS makes the dedicated GPU primary, the scanner may choose the other GPU. Always read the scan table.
- The builder only attaches a GPU that is already bound to "vfio-pci". Isolate and reboot before building the VM.
- Rebuilding the VM deletes the existing one (the GUI asks first).
- Only English (en-US) Windows 11 ISOs with the Pro edition are supported.
- Fedora only. Other distributions and init systems are not supported.

📁 Project layout

File| Purpose
"wise_linux_gui.py"| The graphical interface
"gpu_detect.sh"| Read-only GPU and IOMMU scanner
"iommu_enable.sh"| Adds the IOMMU kernel arguments only (button 2a)
"grub_setup.sh"| Adds VFIO boot arguments, re-verifies hardware, keeps backups
"initramfs_setup.sh"| Rebuilds the initramfs for VFIO
"restore_system.sh"| Removes what the tool added
"vm_builder.sh"| Builds the Windows 11 VM (unattended)
"create_debloat_iso.sh"| Builds the Windows answer ISO
"single_gpu_hooks.sh"| Unfinished single-GPU experiment, not used by the GUI

🧠 How this project was built

Wise Linux Studio is the idea and design of its author, "@t11man" (https://github.com/t11man). The author designed the workflow and the safety model, directed the development, tested the tool on a real Fedora machine, and found the problems that shaped it, such as a desktop freeze when the host suspended while the VM was running, and a scan step that wrote to disk when it should have been read-only.

The code was written with AI assistance (Gemini) under the author's direction. It was then reviewed repeatedly with Claude (Anthropic), which pointed out bugs and risky behavior that were fixed afterwards.

Reviews like these reduce mistakes, but they are not a guarantee of stability or safety. The code has been tested manually only on a Fedora laptop and has not been audited by a human expert. That is why real hardware testing and expert review are what the project needs most.

🤝 Contributing

Wise Linux Studio is an early beta, and real hardware testing is the most valuable contribution right now. Reviews from people who know VFIO, libvirt/QEMU, Fedora boot internals (GRUB, BLS, dracut) and NVIDIA/AMD behavior are very welcome.

When you open an issue, please include:

- CPU model and GPU models
- Fedora version
- Whether the PC has an iGPU or several dedicated GPUs
- The scan table printed by 1. Scan GPU
- Relevant logs and error messages

📜 License

MIT, see "LICENSE" (LICENSE). Provided as is, with no warranty. You use it at your own risk.
