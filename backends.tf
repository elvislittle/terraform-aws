terraform {
  cloud {
    organization = "organization-elvislittle"
    workspaces {
      name = "workspace-aws"
    }
  }
}
