# Main Terragrunt configuration for devgru-infrastructure monorepo
# Automatically generates GCS backend configuration for all environments

remote_state {
  backend = "local"
  config = {
    path = "${get_parent_terragrunt_dir()}/terraform.tfstate"
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

# Input variables available for all modules can be globally defined here,
# e.g. enforcing consistent resource tagging.
