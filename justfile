# Task runner. `just` lists recipes.
default:
    @just --list

# Run every pre-commit check on the whole tree
lint:
    pre-commit run --all-files

# Scan the full git history for secrets
scan-history:
    gitleaks git --redact -v .
