terraform {
  backend "s3" {
    bucket       = "gitea-runner-hectic-lab"
    key          = "gitea-runners/kube-hetzner/terraform.tfstate"
    region       = "fsn1"
    encrypt      = true
    use_lockfile = true
  }
}

check "remote_state_contract" {
  assert {
    condition     = local.production_remote_state
    error_message = "Production OpenTofu state must use the configured S3 backend; local production state is forbidden."
  }
}
