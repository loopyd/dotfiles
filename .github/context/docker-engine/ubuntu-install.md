# Docker Engine on Ubuntu

## Why this exists

- Keep Docker install guidance aligned with official Ubuntu apt repository docs.
- Preserve security and reproducibility defaults for this repository.

## Recommended install flow

1. Remove conflicting distro packages first (`docker.io`, old compose packages).
2. Add Docker key to `/etc/apt/keyrings/docker.asc`.
3. Configure Docker apt source with `Signed-By`.
4. Install:
   - `docker-ce`
   - `docker-ce-cli`
   - `containerd.io`
   - `docker-buildx-plugin`
   - `docker-compose-plugin`
5. Verify with `docker run hello-world`.

## Security and ops notes

- Docker warns that published container ports can bypass `ufw`/`firewalld` rules.
- Docker supports `iptables-nft` and `iptables-legacy`; direct `nft` rules are not
  supported in the default flow.
- The `docker` group is effectively root-equivalent. Use it intentionally.
- Convenience script (`get.docker.com`) is for testing/dev, not preferred for
  stable reproducible host provisioning.

## Repository fit notes

- `scripts/install-docker-engine.sh` currently uses a `.list` source entry with
  `signed-by`, which is still compatible with apt-secure expectations.
- Official docs now showcase a `.sources` style entry. Migration is optional,
  not required for correctness.

## Sources

- https://docs.docker.com/engine/install/ubuntu/
- https://docs.docker.com/engine/install/linux-postinstall/
