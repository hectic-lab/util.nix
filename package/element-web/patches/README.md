# Element Web patches

Put ordered local patch files in this directory as `*.patch`.

- Files are applied in lexical order.
- Use zero-padded numeric prefixes when patch order matters, e.g. `0001-...patch`.
- Keep non-patch files out of the order by using a different extension; `README.md` is ignored by the Nix filter.

## Regenerating a patch

Create a clean checkout of upstream Element Web, make the change under `apps/web`, then run from the repository root:

```sh
git diff -- apps/web > package/element-web/patches/0001-description.patch
```

Use one patch per logical change so the sequence stays reproducible and reviewable.
