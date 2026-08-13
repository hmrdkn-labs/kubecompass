# KubeCompass topology reference coverage policy

- The manifest is a planning contract for the original KubeCompass topology
  route, not a production media bundle.
- Every required scenario has a mandatory wide and narrow desktop frame:
  outline-ready, selected-workload detail, scoped map, path details, partial
  RBAC, loading, empty, and error.
- A frame must retain route context, viewport, shell state, interaction state,
  data state, required controls, and provenance. A ready-state frame does not
  cover loading, empty, error, or partial RBAC.
- Trigger/result pairs and lifecycle sequences are recorded where selection or
  state changes the meaning of the screen. Keep each pair at the exact same
  represented viewport.
- All frames start as `planned-reference`. A planning PASS is not visual
  approval. A completion claim requires local PNG captures, strict validation,
  and a dated human visual review for every captured frame.
- Capture only the original KubeCompass route. Do not copy third-party
  screenshots, logos, images, or reference media into `captures/` or production.
- Traffic remains unavailable unless explicit telemetry evidence is present;
  Kubernetes selectors, owner references, Routes, and EndpointSlices must not
  be represented as traffic.
- The manifest and Interface IR's `codex.local` schema URIs are intentional
  stable local identifiers. Repository validators resolve schemas from
  checkout-relative files, so these identifiers are not network dependencies
  and must remain stable when the documents are copied between checkouts.
- Use the bundled validator from the engineer-interfaces skill:

  ```sh
  python3 "${ENGINEER_INTERFACES_SKILL:?Set this to the checked-out engineer-interfaces skill directory}/scripts/validate_reference_coverage.py" \
    docs/interface/reference-topology-v2/reference-coverage.json
  ```

  Use `--require-captured` only after every planned frame has a valid local PNG
  and an approved visual review entry.
