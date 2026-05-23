# outputs.tf — What you need after `terraform apply`.

output "public_ip" {
  description = "Public IPv4 address of the PetRescue VM."
  value       = aws_instance.petrescue.public_ip
}

output "ssh_command" {
  description = "Ready-to-paste SSH command."
  value       = "ssh -i ~/.ssh/petrescue_oci ubuntu@${aws_instance.petrescue.public_ip}"
}

output "next_steps" {
  description = "What to do after the VM comes up."
  value = <<-EOT

    ============================================================
    VM provisioned on AWS. Public IP: ${aws_instance.petrescue.public_ip}
    ============================================================

    1. WAIT 2-3 MINUTES for cloud-init to finish. Check progress:

         ssh -i ~/.ssh/petrescue_oci ubuntu@${aws_instance.petrescue.public_ip} \
             'tail -f /var/log/cloud-init-output.log'

       Wait until you see "PetRescue bootstrap complete."

    2. SSH into the instance:

         ssh -i ~/.ssh/petrescue_oci ubuntu@${aws_instance.petrescue.public_ip}

    3. Clone your repo and cd into the app folder:

         git clone https://github.com/<your-user>/<your-repo>.git
         cd <your-repo>/<dotnet-folder>

       If the repo is private, use a personal access token:
         git clone https://<TOKEN>@github.com/<your-user>/<your-repo>.git

    4. Start the app (e.g. docker compose up -d, or dotnet run, etc.)

    Endpoints:
      API:     http://${aws_instance.petrescue.public_ip}:8080
      Sidecar: http://${aws_instance.petrescue.public_ip}:5055

  EOT
}
