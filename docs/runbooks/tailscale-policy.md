# Tailnet policy

`tailscale/policy.hujson` is the tailnet policy, applied by the
`Tailscale policy` workflow. Why: [ADR 0008](../adr/0008-tailscale-policy-as-code.md).

## Changing the policy

1. Edit `tailscale/policy.hujson` on a branch and open a pull request. Use
   autogroups and tags, never emails, device names or IPs.
2. The workflow's `test` run validates the file against the Tailscale API.
3. Merge. The `apply` run on `main` makes it live.

## One-time setup

1. In the Tailscale admin console, under **Settings > Trust credentials**,
   create a federated identity:
   - Issuer: GitHub, `https://token.actions.githubusercontent.com`
   - Subject: `repo:<owner>@<owner-id>/<repo>@<repo-id>:*`. GitHub puts the
     numeric account and repository IDs in this repository's OIDC subject;
     print them with
     `gh api repos/<owner>/<repo> --jq '"\(.owner.id) \(.id)"'`.
   - Scopes: **Custom scopes**, then **Policy File** set to write. Leave
     every other scope off.
2. Add the identity's client ID and audience as repository Actions secrets:

   ```sh
   gh secret set TS_OAUTH_ID
   gh secret set TS_AUDIENCE
   ```

3. Merge the pull request that adds the workflow and confirm the `apply` run
   on `main` succeeds.
4. Under **Access controls**, turn on the setting that prevents editing the
   policy in the admin console, so the file stays the only source.

## Recovering from a lockout

If an applied policy cuts off access, unlock console editing, fix the policy
in the console, then commit the same fix to `tailscale/policy.hujson`. The
next `apply` fails because the live policy no longer matches the cached
version; clear the `tailscale-version-cache-` entries under **Actions >
Caches** and re-run it.
