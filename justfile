# Task runner. `just` lists recipes.
default:
    @just --list

# Run every pre-commit check on the whole tree
lint:
    pre-commit run --all-files

# Scan the full git history for secrets
scan-history:
    gitleaks git --redact -v .

# Install the Ansible collections the playbooks need
provision-deps:
    cd provision && ansible-galaxy collection install -r requirements.yml

# Fail fast instead of letting Ansible match no hosts and exit 0
[private]
require-inventory:
    @test -f provision/inventory.yml || { echo "provision/inventory.yml is missing; copy inventory.example.yml and fill it in" >&2; exit 1; }

# Dry-run the node provisioning
provision-check: require-inventory
    cd provision && ansible-playbook playbooks/site.yml --check --diff

# Provision the node (idempotent)
provision *args: require-inventory
    cd provision && ansible-playbook playbooks/site.yml {{ args }}

# Fetch the cluster kubeconfig to ~/.kube/homeserver.yaml
kubeconfig: require-inventory
    cd provision && ansible-playbook playbooks/kubeconfig.yml
