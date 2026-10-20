# Finds YOUR compartment from your email. labctl (the instructor's tool) made
# one per participant under the workshop compartment, named from your email:
#   jsmith@example.com  ->  lab:jsmith_example.com
# You can only create things in that compartment, so everything goes there.

locals {
  email_lc = lower(trimspace(var.email))
  # Same rule labctl uses: lowercase, @ -> _, anything else odd -> -
  compartment_name = replace(replace(local.email_lc, "@", "_"), "/[^a-z0-9._-]/", "-")
  # Short resource prefix from the part before @, e.g. ckad-jsmith
  name = "ckad-${substr(replace(split("@", local.email_lc)[0], "/[^a-z0-9]/", ""), 0, 20)}"

  compartment_id = one(data.oci_identity_compartments.mine.compartments[*].id)
}

data "oci_identity_compartments" "mine" {
  compartment_id = var.lab_compartment_ocid
  name           = local.compartment_name
  state          = "ACTIVE"

  lifecycle {
    postcondition {
      condition     = length(self.compartments) == 1
      error_message = "No compartment named '${local.compartment_name}' under the workshop compartment. Check that email in terraform.tfvars is exactly the address your invite was sent to, and that your instructor has run labctl for you."
    }
  }
}
