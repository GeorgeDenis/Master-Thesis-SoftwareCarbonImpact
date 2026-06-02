# outputs.tf — What you need after `terraform apply`.

# --- m7i-flex.large (good hardware, full speed) ---
output "net_m7i_ip" {
  description = ".NET on m7i-flex.large"
  value       = aws_instance.net_m7i.public_ip
}

output "flask_m7i_ip" {
  description = "Flask on m7i-flex.large"
  value       = aws_instance.flask_m7i.public_ip
}

# --- c7i-flex.large (medium hardware, use with cpulimit) ---
output "net_c7i_ip" {
  description = ".NET on c7i-flex.large"
  value       = aws_instance.net_c7i.public_ip
}

output "flask_c7i_ip" {
  description = "Flask on c7i-flex.large"
  value       = aws_instance.flask_c7i.public_ip
}

# --- t3.small (weak hardware, natural bottleneck) ---
output "net_t3_ip" {
  description = ".NET on t3.small"
  value       = aws_instance.net_t3.public_ip
}

output "flask_t3_ip" {
  description = "Flask on t3.small"
  value       = aws_instance.flask_t3.public_ip
}

# --- SSH commands ---
output "ssh_commands" {
  description = "Ready-to-paste SSH commands for all 6 VMs."
  value = <<-EOT

    ============================================================
    SSH commands for all 6 VMs:
    ============================================================

    # m7i-flex.large (8GB RAM, full speed)
    ssh -i ~/.ssh/petrescue_oci ubuntu@${aws_instance.net_m7i.public_ip}          # .NET
    ssh -i ~/.ssh/petrescue_oci ubuntu@${aws_instance.flask_m7i.public_ip}    # Flask

    # c7i-flex.large (4GB RAM, use with --cpulimit 50)
    ssh -i ~/.ssh/petrescue_oci ubuntu@${aws_instance.net_c7i.public_ip}            # .NET
    ssh -i ~/.ssh/petrescue_oci ubuntu@${aws_instance.flask_c7i.public_ip}          # Flask

    # t3.small (2GB RAM, natural bottleneck)
    ssh -i ~/.ssh/petrescue_oci ubuntu@${aws_instance.net_t3.public_ip}             # .NET
    ssh -i ~/.ssh/petrescue_oci ubuntu@${aws_instance.flask_t3.public_ip}           # Flask

    ============================================================
    After SSH, run:
      cd ~/Master-Thesis-SoftwareCarbonImpact/petrescue-{flask,net}-slice1
      bash scripts/run_full.sh              # m7i (full speed)
      bash scripts/run_full.sh --cpulimit 50  # c7i (throttled)
      bash scripts/run_full.sh              # t3 (natural bottleneck)
    ============================================================

  EOT
}
