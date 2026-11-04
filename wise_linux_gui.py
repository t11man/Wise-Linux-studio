#!/usr/bin/env python3
# Wise Linux Studio - Hardened GUI with Stdout Candidate Verification & Safe Guards
import os
import re
import stat
import subprocess
import threading
import tkinter as tk
from tkinter import filedialog, messagebox, scrolledtext


class WiseLinuxGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("Wise Linux - GPU VFIO & Ghost VM Manager")
        self.root.geometry("900x680")
        self.root.configure(bg="#1e1e2e")

        self.script_dir = os.path.dirname(os.path.abspath(__file__))
        self.candidate_bdf = None
        self.candidate_ids = None

        tk.Label(
            root, text="Wise Linux Studio", font=("Sans", 18, "bold"),
            bg="#1e1e2e", fg="#cdd6f4"
        ).pack(pady=(10, 5))

        # --- Phase 1: Host Hardware Isolation ---
        phase1_frame = tk.LabelFrame(
            root, text=" Phase 1: Host Hardware Isolation (Dual-GPU Desktops Only) ",
            font=("Sans", 10, "bold"), bg="#1e1e2e", fg="#89b4fa", padx=10, pady=8
        )
        phase1_frame.pack(fill="x", padx=15, pady=5)

        btn_style = {"font": ("Sans", 9, "bold"), "width": 14, "pady": 5}

        self.btn_scan = tk.Button(
            phase1_frame, text="1. Scan GPU", bg="#313244", fg="#cdd6f4",
            command=self.scan_gpu, **btn_style
        )
        self.btn_scan.grid(row=0, column=0, padx=4, pady=5)

        self.btn_iommu = tk.Button(
            phase1_frame, text="2a. Enable IOMMU", bg="#45475a", fg="#cdd6f4",
            state="disabled", command=self.setup_iommu, **btn_style
        )
        self.btn_iommu.grid(row=0, column=1, padx=4, pady=5)

        self.btn_grub = tk.Button(
            phase1_frame, text="2. Setup GRUB", bg="#45475a", fg="#cdd6f4",
            state="disabled", command=self.setup_grub, **btn_style
        )
        self.btn_grub.grid(row=0, column=2, padx=4, pady=5)

        self.btn_initramfs = tk.Button(
            phase1_frame, text="3. Build Initramfs", bg="#45475a", fg="#cdd6f4",
            state="disabled", command=self.setup_initramfs, **btn_style
        )
        self.btn_initramfs.grid(row=0, column=3, padx=4, pady=5)

        self.btn_restore = tk.Button(
            phase1_frame, text="4. Restore System", bg="#f38ba8", fg="#11111b",
            command=self.restore_system, **btn_style
        )
        self.btn_restore.grid(row=0, column=4, padx=4, pady=5)

        # --- Phase 2: Ghost Windows 11 Studio ---
        phase2_frame = tk.LabelFrame(
            root, text=" Phase 2: Zero-Touch Ghost Windows 11 Studio ",
            font=("Sans", 10, "bold"), bg="#1e1e2e", fg="#a6e3a1", padx=10, pady=8
        )
        phase2_frame.pack(fill="x", padx=15, pady=6)

        tk.Label(
            phase2_frame, text="Win11 ISO:", font=("Sans", 10),
            bg="#1e1e2e", fg="#cdd6f4"
        ).grid(row=0, column=0, padx=5, sticky="w")

        self.iso_path_var = tk.StringVar()
        self.iso_entry = tk.Entry(
            phase2_frame, textvariable=self.iso_path_var, width=50,
            bg="#313244", fg="#cdd6f4", insertbackground="white"
        )
        self.iso_entry.grid(row=0, column=1, padx=5, pady=5)

        self.btn_browse = tk.Button(
            phase2_frame, text="Browse", bg="#45475a", fg="#cdd6f4",
            command=self.browse_iso, width=10
        )
        self.btn_browse.grid(row=0, column=2, padx=5, pady=5)

        # --- Resource Allocation Row (Auto vs Manual) ---
        res_frame = tk.Frame(phase2_frame, bg="#1e1e2e")
        res_frame.grid(row=1, column=0, columnspan=3, pady=5, sticky="w")

        self.auto_res_var = tk.BooleanVar(value=True)
        self.chk_auto = tk.Checkbutton(
            res_frame, text="Auto Resources (50% RAM / 60GB Disk)",
            variable=self.auto_res_var, command=self.toggle_resource_inputs,
            bg="#1e1e2e", fg="#89b4fa", selectcolor="#313244",
            activebackground="#1e1e2e", activeforeground="#89b4fa", font=("Sans", 9, "bold")
        )
        self.chk_auto.grid(row=0, column=0, padx=(5, 15))

        tk.Label(res_frame, text="RAM (GB):", bg="#1e1e2e", fg="#cdd6f4", font=("Sans", 9)).grid(row=0, column=1)
        self.ram_gb_var = tk.StringVar(value="8")
        self.entry_ram = tk.Entry(res_frame, textvariable=self.ram_gb_var, width=6, bg="#313244", fg="#cdd6f4", state="disabled")
        self.entry_ram.grid(row=0, column=2, padx=(4, 15))

        tk.Label(res_frame, text="Disk (GB):", bg="#1e1e2e", fg="#cdd6f4", font=("Sans", 9)).grid(row=0, column=3)
        self.disk_gb_var = tk.StringVar(value="120")
        self.entry_disk = tk.Entry(res_frame, textvariable=self.disk_gb_var, width=6, bg="#313244", fg="#cdd6f4", state="disabled")
        self.entry_disk.grid(row=0, column=4, padx=4)

        # --- Action Buttons Row ---
        action_frame = tk.Frame(phase2_frame, bg="#1e1e2e")
        action_frame.grid(row=2, column=0, columnspan=3, pady=(8, 2))

        self.btn_dryrun = tk.Button(
            action_frame, text="Test Mode (Dry-Run)", bg="#89b4fa", fg="#11111b",
            font=("Sans", 9, "bold"), width=18, pady=5, command=self.run_dry_test
        )
        self.btn_dryrun.grid(row=0, column=0, padx=4)

        self.btn_build_vm = tk.Button(
            action_frame, text="5. Build Ghost VM (1st Time)", bg="#a6e3a1", fg="#11111b",
            font=("Sans", 9, "bold"), width=22, pady=5, command=self.build_vm
        )
        self.btn_build_vm.grid(row=0, column=1, padx=4)

        self.btn_launch_vm = tk.Button(
            action_frame, text="6. Launch Gaming VM", bg="#f9e2af", fg="#11111b",
            font=("Sans", 9, "bold"), width=18, pady=5, command=self.launch_existing_vm
        )
        self.btn_launch_vm.grid(row=0, column=2, padx=4)

        self.btn_save_vm = tk.Button(
            action_frame, text="7. Save & Pause VM", bg="#cba6f7", fg="#11111b",
            font=("Sans", 9, "bold"), width=16, pady=5, command=self.save_vm_state
        )
        self.btn_save_vm.grid(row=0, column=3, padx=4)

        # --- Output Console Log ---
        self.log_area = scrolledtext.ScrolledText(
            root, width=100, height=18, bg="#11111b", fg="#a6e3a1",
            font=("Monospace", 9), state="disabled"
        )
        self.log_area.pack(padx=15, pady=10, fill="both", expand=True)

        self.log("[*] Wise Linux Studio Ready.")
        self.log("[*] Note: All changes inside Windows VM are automatically saved to disk.")
        self.log("[*] Start by clicking '1. Scan GPU' to check your hardware topology!\n")

    def toggle_resource_inputs(self):
        state = "disabled" if self.auto_res_var.get() else "normal"
        self.entry_ram.config(state=state)
        self.entry_disk.config(state=state)

    def get_resource_args(self):
        if self.auto_res_var.get():
            return ["auto", "auto"]
        ram_str = self.ram_gb_var.get().strip()
        disk_str = self.disk_gb_var.get().strip()
        if not (ram_str.isdigit() and disk_str.isdigit()):
            messagebox.showerror("Invalid Input", "RAM and Disk values must be positive whole numbers (integers).")
            return None
        if int(ram_str) < 4 or int(disk_str) < 40:
            messagebox.showerror("Invalid Input", "Minimum allowed values: 4 GB RAM and 40 GB Disk.")
            return None
        return [ram_str, disk_str]

    def log(self, message):
        self.log_area.config(state="normal")
        self.log_area.insert(tk.END, message + "\n")
        self.log_area.see(tk.END)
        self.log_area.config(state="disabled")

    def browse_iso(self):
        filename = filedialog.askopenfilename(
            title="Select Windows 11 ISO",
            filetypes=[("ISO Files", "*.iso"), ("All Files", "*.*")]
        )
        if filename:
            self.iso_path_var.set(filename)

    def verify_script_security(self, script_path):
        if os.path.islink(script_path):
            self.log(f"[!] SECURITY BLOCK: Refusing to run symlinked script: {script_path}")
            return False
        st = os.stat(script_path)
        if bool(st.st_mode & (stat.S_IWGRP | stat.S_IWOTH)) or st.st_uid not in (0, os.getuid()):
            self.log(f"[!] SECURITY BLOCK: Insecure permissions/ownership on {script_path}")
            return False
        return True

    def run_script_async(self, cmd_list, on_success=None):
        if len(cmd_list) > 1 and cmd_list[0] == "pkexec" and cmd_list[1].endswith(".sh"):
            if not self.verify_script_security(cmd_list[1]):
                return

        def task():
            captured_lines = []
            try:
                process = subprocess.Popen(
                    cmd_list, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
                )
                for line in process.stdout:
                    clean_line = line.rstrip()
                    captured_lines.append(clean_line)
                    self.root.after(0, self.log, clean_line)
                process.wait()
                if process.returncode == 0 and on_success:
                    self.root.after(0, lambda: on_success(captured_lines))
                elif process.returncode != 0:
                    self.root.after(0, self.log, f"[!] Process exited with code {process.returncode}")
            except Exception as e:
                self.root.after(0, self.log, f"[!] Execution Error: {str(e)}")

        threading.Thread(target=task, daemon=True).start()

    def scan_gpu(self):
        script = os.path.join(self.script_dir, "gpu_detect.sh")
        self.candidate_bdf = None
        self.candidate_ids = None
        self.btn_iommu.config(state="disabled", bg="#45475a", fg="#cdd6f4")
        self.btn_grub.config(state="disabled", bg="#45475a", fg="#cdd6f4")
        self.btn_initramfs.config(state="disabled", bg="#45475a", fg="#cdd6f4")

        self.log("\n[*] Running Read-Only GPU & IOMMU Topology Scan...")

        def evaluate_scan_output(lines):
            joined_out = "\n".join(lines)

            if "IOMMU_KERNEL_OFF=1" in joined_out:
                self.log("[!] IOMMU is disabled in the kernel. Click '2a. Enable IOMMU', then REBOOT and re-scan.")
                self.log("[*] (If IOMMU remains disabled after reboot, enable VT-d / AMD-Vi in your BIOS).")
                self.btn_iommu.config(state="normal", bg="#f9e2af", fg="#11111b")
                return

            pattern = re.compile(r"^CANDIDATE_BDF=(\S+)\s+CANDIDATE_IDS=([0-9a-fA-F:,]+)$")
            for line in lines:
                match = pattern.match(line.strip())
                if match:
                    self.candidate_bdf = match.group(1)
                    self.candidate_ids = match.group(2)
                    break

            if self.candidate_bdf and self.candidate_ids:
                self.log(f"[+] Dual-GPU Unlocked: Verified secondary GPU {self.candidate_bdf} ({self.candidate_ids})")
                self.log("[*] NEXT STEP: Click '2. Setup GRUB' -> '3. Build Initramfs' -> REBOOT your PC before building VM!")
                self.btn_grub.config(state="normal", bg="#89b4fa", fg="#11111b")
                self.btn_initramfs.config(state="normal", bg="#89b4fa", fg="#11111b")
            else:
                if "IOMMU Disabled" in joined_out:
                    self.log("[!] SAFETY LOCK: Secondary GPU detected, but IOMMU is disabled.")
                    self.log("[*] NEXT STEP: Enable VT-d (Intel) or AMD-Vi (AMD) in BIOS and kernel parameters, then re-scan.")
                elif "Multiple" in joined_out:
                    self.log("[!] SAFETY LOCK: Multiple secondary GPUs detected. Manual selection is not supported yet.")
                    self.log("[*] Phase 1 automatic isolation remains locked.")
                else:
                    self.log("[!] SAFETY LOCK: Single GPU detected.")
                    self.log("[*] Phase 1 buttons are locked to protect your screen from going black.")
                    self.log("[*] NEXT STEP: Skip Phase 1 completely! Select your ISO below and click '5. Build Ghost VM' directly.")

        if not self.verify_script_security(script):
            return
        self.run_script_async([script], on_success=evaluate_scan_output)

    def setup_iommu(self):
        script = os.path.join(self.script_dir, "iommu_enable.sh")
        self.run_script_async(
            ["pkexec", script],
            on_success=lambda _lines: self.log("[+] SUCCESS: IOMMU added to GRUB/BLS. Please REBOOT your system now, then run '1. Scan GPU' again!")
        )

    def setup_grub(self):
        if not self.candidate_bdf or not self.candidate_ids:
            messagebox.showwarning("Not Verified", "Please run '1. Scan GPU' and verify a candidate GPU first.")
            return
        script = os.path.join(self.script_dir, "grub_setup.sh")
        self.run_script_async(["pkexec", script, self.candidate_bdf, self.candidate_ids])

    def setup_initramfs(self):
        if not self.candidate_bdf or not self.candidate_ids:
            messagebox.showwarning("Not Verified", "Please run '1. Scan GPU' and verify a candidate GPU first.")
            return
        script = os.path.join(self.script_dir, "initramfs_setup.sh")
        self.run_script_async(
            ["pkexec", script, self.candidate_bdf, self.candidate_ids],
            on_success=lambda _lines: self.log("[!] IMPORTANT: Now REBOOT your PC so VFIO can claim the secondary GPU before clicking '5. Build Ghost VM'!")
        )

    def restore_system(self):
        self.log("\n[*] Running Ultimate System Restore Shield...")
        self.run_script_async(["pkexec", os.path.join(self.script_dir, "restore_system.sh")])

    def run_dry_test(self):
        iso_path = self.iso_path_var.get().strip()
        if not iso_path or not os.path.isfile(iso_path):
            messagebox.showwarning("Missing ISO", "Please select a valid Windows 11 ISO file first!")
            return
        res_args = self.get_resource_args()
        if not res_args:
            return
        ram_arg, disk_arg = res_args
        script = os.path.join(self.script_dir, "vm_builder.sh")
        self.log("\n[*] Starting SAFE DRY-RUN Test (Zero RAM / No VM Launch)...")
        bdf_arg = self.candidate_bdf if self.candidate_bdf else ""
        self.run_script_async(["pkexec", script, iso_path, "--dry-run", ram_arg, disk_arg, bdf_arg])

    def build_vm(self):
        iso_path = self.iso_path_var.get().strip()
        if not iso_path or not os.path.isfile(iso_path):
            messagebox.showwarning("Missing ISO", "Please select a valid Windows 11 ISO file first!")
            return

        res_args = self.get_resource_args()
        if not res_args:
            return
        ram_arg, disk_arg = res_args

        if os.path.exists("/var/lib/libvirt/images/WiseGhost_Win11.qcow2"):
            confirm = messagebox.askyesno(
                "Overwrite Warning",
                "WiseGhost_Win11 already exists!\n\n"
                "If you already installed Windows, use '6. Launch Gaming VM' instead.\n"
                "Do you really want to wipe it and build from scratch?"
            )
            if not confirm:
                return

        script = os.path.join(self.script_dir, "vm_builder.sh")
        self.log("\n[*] Starting Zero-Touch Ghost VM Builder...")

        def launch_viewer(_lines=None):
            subprocess.Popen([
                "systemd-inhibit", "--what=sleep:idle:handle-lid-switch",
                "--who=WiseLinux", "--why=Running Windows Gaming VM",
                "virt-viewer", "--connect", "qemu:///system", "--reconnect", "WiseGhost_Win11"
            ])

        bdf_arg = self.candidate_bdf if self.candidate_bdf else ""
        self.run_script_async(["pkexec", script, iso_path, "--build", ram_arg, disk_arg, bdf_arg], on_success=launch_viewer)

    def launch_existing_vm(self):
        self.log("\n[*] Launching existing WiseGhost_Win11 Gaming VM...")

        def start_and_view():
            res = subprocess.run(
                ["pkexec", "virsh", "--connect", "qemu:///system", "start", "WiseGhost_Win11"],
                capture_output=True, text=True
            )
            if res.returncode == 0 or "already active" in res.stderr:
                subprocess.Popen([
                    "systemd-inhibit", "--what=sleep:idle:handle-lid-switch",
                    "--who=WiseLinux", "--why=Running Windows Gaming VM",
                    "virt-viewer", "--connect", "qemu:///system", "--reconnect", "WiseGhost_Win11"
                ])
                self.root.after(0, self.log, "[+] VM Viewer Connected! Your files & apps are intact.")
            else:
                self.root.after(0, self.log, f"[!] Could not start VM: {res.stderr.strip()}")

        threading.Thread(target=start_and_view, daemon=True).start()

    def save_vm_state(self):
        xml_check = subprocess.run(
            ["virsh", "--connect", "qemu:///system", "dumpxml", "WiseGhost_Win11"],
            capture_output=True, text=True
        )
        if "<hostdev" in xml_check.stdout:
            messagebox.showwarning(
                "VFIO Passthrough Active",
                "Saving RAM state (managedsave) is not supported while a physical GPU is passed through.\nPlease shut down Windows normally from inside the VM."
            )
            return
        self.log("\n[*] Saving VM RAM state to disk (Hibernate)...")
        self.run_script_async(
            ["pkexec", "virsh", "--connect", "qemu:///system", "managedsave", "WiseGhost_Win11"],
            on_success=lambda _lines: self.log("[+] VM State Saved! Next '6. Launch Gaming VM' will resume instantly.")
        )


if __name__ == "__main__":
    root = tk.Tk()
    app = WiseLinuxGUI(root)
    root.mainloop()