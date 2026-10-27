# Schema oracle

[![CI](https://github.com/lostbean/json_blueprint/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/lostbean/json_blueprint/actions/workflows/test.yml)
[![json_blueprint on Hex](https://img.shields.io/hexpm/v/json_blueprint?label=Hex%3A%20json_blueprint)](https://hex.pm/packages/json_blueprint)
[![Gleam](https://img.shields.io/badge/Gleam-FFAFF3?logo=gleam&logoColor=000000)](https://gleam.run/)

Run the independent comparison from the repository root in its Nix shell:

```sh
nix develop --command python3 test/schema_check.py
nix develop --command python3 test/schema_profile_check.py
```

The [frozen manifest](../schema_manifest.json) and the [checker](../schema_check.py)
own the cases. The reference, its pin, what is compared and the limits of the claim
are in [docs/ORACLE.md](../../docs/ORACLE.md).
