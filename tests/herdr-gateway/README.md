# Herdr and Gateway skill checks

Run `node tests/herdr-gateway/run.cjs` from any directory with Node 24.5 or later. The runner copies only the two skills' JavaScript templates into a private temporary directory. It does not install skills, connect to live Herdr/Gateway/Library, or expire artifacts. TLS tests use a generated loopback certificate and proxy; OpenSSL must be available.

The suite covers the installed protocol-22 schema (103 methods), fragmented socket replies, configured proxy and NO_PROXY behavior, byte integrity, metadata identity, artifact expiry, bounded pagination, concurrent writers, lost acquisition/release receipts, explicit session resumption, run-ID boundaries, selector overrides, output collisions, receipt tampering, completed capture identity, independent pinned Library readback, and descendant deadlines. Mutations use isolated mock services. The capture environment in the offline process-group fixture is simulated; it does not prove a managed Herdr environment.

The captured coverage reference records earlier managed-pane observations. These offline checks do not reproduce or establish that live evidence. Never run fixtures against an existing user's pane. Any separately authorized live validation requires a task-owned workspace, preserved focus, and fresh explicit bindings.

To run a subset, append test filenames, for example `node tests/herdr-gateway/run.cjs test-gateway-library.cjs test-gateway-purge.cjs`. Each test process has a 60-second limit. Temporary fixture files are removed after the run.

The schema fixture records the installed API shape, not live coverage of destructive, agent, graphics or context-dependent methods. Artifact expiration has preview/mock coverage only; actual expiration requires exact action-time confirmation. Small local CLI reads can outperform Node discovery; lossless artifact transport has job and transfer overhead. Report cloud and desktop evidence separately.
