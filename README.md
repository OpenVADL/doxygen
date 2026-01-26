Doxygen (OpenVADL Fork)
===============

This repository is a **custom fork of Doxygen** with added support for the **Coco/R ATG language**.

The fork is maintained for **internal documentation generation**.  
It intentionally diverges from upstream and is **not intended to be merged back**.

---

## Branching Model

### `master`
- Tracks **upstream `master`**
- Contains **no fork-specific changes**
- Used only to follow upstream development

### Release branches (`Release_X_Y_Z`)
- Created from the **exact upstream Doxygen release commit**
- Contain **only fork-specific changes**
- This is where **all active development happens**
- **Never rebased or force-pushed**

Examples:
```
Release_1_16_0
Release_1_16_1
```

### Default branch
- Set to the **latest release branch**
- Always represents a **stable, usable version**

---

## Development Workflow (Important)

All changes are applied via **pull requests into the active release branch**.

### Rules
- ❌ No direct pushes to `Release_*`
- ❌ No rebases of published branches
- ✅ All changes go through PRs
- ✅ Cherry-picks are preferred over merges from upstream

This applies even for single-maintainer workflows.

---

## Updating to a New Upstream Doxygen Release

When upstream publishes a new Doxygen release:

1. Create a new release branch at the upstream release commit: `Release_X_Y_Z`
2. Cherry-pick all fork-specific commits from the previous release branch
3. Resolve conflicts (only fork code should conflict)
4. Create a new release tag `X.Y.Z-openvadl1`

Old release branches remain **unchanged and reproducible**.

---

## Versioning Scheme

Versions are derived from the upstream Doxygen version with a fork-specific suffix: `-openvadl`

Examples:
```
1.16.0-openvadl1
1.16.0-openvadl2
1.16.1-openvadl1
```
- `<doxygen-version>`  
  Exact upstream release version

- `cocor<N>`  
  Incremented for fork-specific changes

All versions are created as **Git tags**.

