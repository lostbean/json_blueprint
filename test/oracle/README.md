# Schema oracle

Run the independent comparison from the repository root in its Nix shell:

```sh
nix develop --command python3 test/schema_check.py
nix develop --command python3 test/schema_profile_check.py
```

The [frozen manifest](../schema_manifest.json) and the [checker](../schema_check.py)
own the cases. The reference, its pin, what is compared and the limits of the claim
are in [docs/ORACLE.md](../../docs/ORACLE.md).
