

variable "project_name" {
  type    = string
  default = "sagemaker-logs-poc"
}

variable "github_repo_name" {
  description = "GitHub repository name (e.g., 'username/repository')"
  type        = string
}

variable "github_branch" {
  description = "GitHub branch to monitor"
  type        = string
  default     = "main"
}