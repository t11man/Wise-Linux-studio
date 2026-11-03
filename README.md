# Wise-Linux-studio
# Wise Linux Studio (Alpha/Beta Release)
> **Automated GPU VFIO Passthrough & Zero-Touch Ghost Windows 11 VM Manager**

Wise Linux Studio is a hardened, production-grade automated framework designed to empower Linux gamers, creators, and engineers. By eliminating the manual complexity of setting up Dual-GPU VFIO passthrough, it brings bare-metal Windows 11 performance (95-99% native GPU utilization) directly into your Linux environment with a single, streamlined 4-step GUI.

---

## 🚀 CORE BENEFITS & WHAT IT CAN RUN
By unlocking full bare-metal hardware passthrough, this framework theoretically bridges the final gap between Linux and Windows, giving you native-like GPU acceleration. 

* **The Complete Adobe Creative Cloud Suite:** Run software like *Adobe Premiere Pro*, *After Effects*, *Photoshop*, and *Illustrator* at maximum graphics card capability for hardware-accelerated rendering and video production.
* **Native Microsoft Office Desktop Apps:** Seamless execution of full desktop versions of *Word*, *Excel*, and *PowerPoint* without layout corruption or compatibility issues.
* **Pro-Grade CAD & 3D Engineering Software:** Native acceleration for heavy industry-standard tools like *SolidWorks*, *Autodesk AutoCAD*, *Revit*, *Maya*, and *3ds Max*.
* **Heavyweight Windows Gaming Ecosystem:** Enjoy maximum performance and ray-tracing capabilities on hardware-intensive single-player games (e.g., *Cyberpunk 2077*, *Black Myth: Wukong*).

---

## ⚠️ ANTICHEAT COMPATIBILITY NOTICE (THEORETICAL ONLY)
While many online multiplayer games are designed to run seamlessly on a native Windows kernel environment, **we explicitly state that anti-cheat compatibility has NOT been heavily tested in a live environment yet. All claims regarding online multiplayer games remain purely theoretical [1, 2].**

* **EAC & BattlEye Games (e.g., Fortnite, Apex Legends):** These systems are structurally capable of running within an optimized VM provided that robust hypervisor cloaking and hardware spoofing are initialized, though success depends heavily on active anti-cheat signatures.
* **Kernel-Level Intrusive Anti-Cheats (e.g., Valorant / Riot Vanguard):** Due to deep hypervisor clock-timing and microsecond latency analysis executed by kernel drivers, running Valorant inside this VM has a near-zero success rate. Do not expect intrusive kernel anti-cheats to work out of the box.

---

## 🛑 CRITICAL SAFETY WARNING & DISCLAIMER
**USE THIS SOFTWARE AT YOUR OWN RISK.** 
This software interacts directly with low-level kernel modules, bootloaders (GRUB/Initramfs), and host hardware isolation protocols. While the software includes aggressive hardware mitigation checks, misconfiguration or unexpected hardware layouts can potentially result in a **host black screen** or system boot failures.

* Always ensure you have a verified system backup or a Live Linux USB standby before updating kernel and bootloader states.
* **Licensing & Liability:** This project is provided "as is" without warranty of any kind, either expressed or implied. The developers assume zero liability for any data loss, hardware damage, or bootloader corruption.

---

## 🔒 HARDENED SAFEGUARDS (Why Wise Linux is Different)
Unlike standard blind shell scripts found online, Wise Linux Studio prioritizes host stability and security first:
1. **Hardware-Enforced Safety Lock:** The framework actively verifies `boot_vga` and `GPU_COUNT`. If it detects a single-GPU system (e.g., standard laptops), it strictly **locks out** GRUB/Initramfs isolation commands to prevent catastrophic host blackouts.
2. **Privilege Escalation Protection:** The GUI parses script signatures and explicitly blocks symlinks, enforcing strict root ownership checks before executing dynamic actions through `pkexec`.
3. **Fail-Safe Ultimate Restore Shield:** Features a fully automated runtime rollback hook that purges configurations from `/etc/modprobe.d/` and safely reverts the kernel boot parameters to their stable state.
4. **Virtualization Anti-Freeze:** Leverages `systemd-inhibit` to prevent host power saving, suspend states, or laptop lid triggers from freezing or interrupting the active virtual machine during intense gaming sessions.
5. **Fedora BLS Configuration Integrity:** The system utilizes `grubby --update-kernel=ALL` to safely overwrite Fedora Bootloader Spec entries, ensuring active boot configs get flashed successfully on reboot without breaking existing boot entries.
6.
