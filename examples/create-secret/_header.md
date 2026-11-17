# Create secret

This example shows how to deploy the module and create a secret using Azure RBAC.

It creates secrets through the Key Vault data plane, with a plain and a write-only value, and one
secret through Azure Resource Manager (`control_plane_enabled = true`), whose write-only value is sent
in a write-only request body that AzAPI keeps out of the plan and the state. Azure Resource Manager
cannot delete a secret: destroying the example only removes that secret from the state, and it goes
with the key vault.
