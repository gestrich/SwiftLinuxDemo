# Build provenance attestation

A four-line YAML step turns an ordinary release into a cryptographically
verifiable one. Here's what those four lines actually do.

## The step

```yaml
- name: Attest build provenance
  uses: actions/attest-build-provenance@v2
  with:
    subject-path: 'swift-linux-demo-*.tar.gz'
```

When this step runs, it:

1. Computes the SHA-256 hash of each file matching the glob (the "subject
   digest").
2. Uses the runner's `id-token: write` permission to request an OIDC token
   from GitHub. The token's claims include `repository`, `ref`, `workflow`,
   `job_workflow_ref`, `sha`, and `run_id`.
3. Sends the OIDC token to Sigstore's Fulcio CA, which issues a short-lived
   (~10 min) X.509 certificate whose subject identifies the workflow run.
4. Generates an in-toto attestation in SLSA Provenance v1.0 format — a JSON
   document linking the artifact digest to the builder identity, source
   repo, commit, and workflow inputs.
5. Signs the attestation with the ephemeral private key, throws the key
   away, and submits the signature + public key to Rekor (Sigstore's
   transparency log).
6. Registers the bundle (cert + signature + Rekor inclusion proof +
   statement) with GitHub via the Attestations REST API.

## Permissions

Three scopes have to be granted at the workflow or job level:

```yaml
permissions:
  attestations: write   # register the provenance statement with GitHub
  contents: write       # let `gh release create` push assets
  id-token: write       # request the OIDC token Sigstore needs
```

If you remove `id-token: write`, attestation fails with a confusing error
that doesn't mention OIDC. Always remember the three together.

Note that a *job-level* `permissions:` block fully **replaces** the
workflow-level one — it doesn't merge. Anything not listed at the job level
is set to `none` for that job, even if the workflow level granted it. Two
safe patterns:

- Workflow-level grants, no job-level blocks (this repo's choice).
- Workflow-level `permissions: {}` (deny all) with each job opting in to
  exactly the scopes it needs (the GitHub-hardened pattern).

Avoid the middle ground where some jobs have blocks and others don't, with
the workflow level granting permissively — that's how a future job ends up
silently inheriting more than it should.

## Why it's "keyless"

Traditional code signing requires a long-lived private key you keep secret
forever. Sigstore replaces that with three short-lived things:

- An OIDC token (valid minutes) proving identity.
- An X.509 certificate (~10 min) issued by Fulcio in exchange for the OIDC
  token.
- A signing keypair generated in memory and destroyed after one use.

Trust is rooted not in "who held the private key" but in "who could obtain
an OIDC token with these claims." The OIDC token can *only* have
`repository: gestrich/SwiftLinuxDemo` and `ref: refs/tags/v0.1.0` if it was
actually minted for a run in this repo on this tag. GitHub's OIDC issuer is
the trust anchor.

## What attestation gives you that a checksum cannot

| | Checksum | Attestation |
|---|---|---|
| Verifies bytes are unchanged | yes | yes |
| Verifies which repo built them | no | yes |
| Verifies which commit | no | yes |
| Verifies which workflow file | no | yes |
| Visible in a public transparency log | no | yes (Rekor) |
| Forgeable by a stolen GitHub account | yes | no |

A stolen account can delete a release asset, upload a poisoned tarball, and
edit `checksums.txt` to match — every user who runs `sha256sum --check` sees
✓ because the attacker controls both files. The attacker *cannot* mint a
valid attestation for the poisoned tarball: the attestation is a
Sigstore-signed statement whose signing certificate is issued by Fulcio in
exchange for an OIDC token, and that OIDC token can only be minted by
GitHub's OIDC issuer in response to a real workflow run. There is no "edit
the attestation" button.

## End-user verification

```bash
gh attestation verify swift-linux-demo-linux-x86_64.tar.gz \
  --repo gestrich/SwiftLinuxDemo
```

Under the hood, that command:

1. Computes the SHA-256 of your local file.
2. Fetches the attestation bundle from GitHub for that digest.
3. Validates the Sigstore certificate chain back to Fulcio's root.
4. Confirms the Rekor transparency-log inclusion proof.
5. Checks that the certificate's identity claims match
   `gestrich/SwiftLinuxDemo`.
6. Prints the workflow path, commit SHA, and run ID that produced the file.

## See Also

- <doc:04-DocC-On-Pages>
