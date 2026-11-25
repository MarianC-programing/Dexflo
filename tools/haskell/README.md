# dexflo-report — Módulo Haskell (Fase 10)

CLI independiente que lee el archivo JUnit (`results/junit.xml`) producido por
la suite de Playwright de Dexflo y genera un JSON con:

- totales (tests, pasados, fallados, omitidos)
- desglose por tag (`@smoke`, `@e2e`, `@api`, `@web3`)
- tests más lentos (umbral configurable)
- comparación con la ejecución anterior

## Requisitos previos

Este módulo está escrito en Haskell y requiere la toolchain de GHC/cabal.
Instalar con [ghcup](https://www.haskell.org/ghcup/):

```bash
# Instalar ghcup (si no está instalado)
curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh

# Instalar GHC y cabal
ghcup install ghc 9.6
ghcup install cabal 3.10
ghcup set ghc 9.6
ghcup set cabal 3.10
```

## Compilación

```bash
cd tools/haskell
cabal build
```

## Uso

```bash
cabal run dexflo-report -- --junit results/junit.xml --previous results/junit.previous.xml --slow-threshold 5.0 -o report.json
```

Opciones:

| Opción                   | Descripción                         | Por defecto         |
| ------------------------ | ----------------------------------- | ------------------- |
| `--junit FILE`           | Archivo JUnit de entrada            | `results/junit.xml` |
| `--previous FILE`        | JUnit previo para comparación       | (ninguno)           |
| `--slow-threshold SEG`   | Umbral para tests lentos (segundos) | `5.0`               |
| `-o FILE, --output FILE` | Archivo de salida JSON              | stdout              |
| `--help`                 | Muestra la ayuda                    | —                   |

## Salida JSON

El CLI emite un JSON con la siguiente estructura:

```json
{
  "name": "dexflo-run",
  "tests": 82,
  "passed": 80,
  "failed": 0,
  "skipped": 2,
  "time_seconds": 11.2,
  "tags": [
    { "tag": "@smoke", "tests": 12, "passed": 12, "failed": 0 },
    { "tag": "@e2e", "tests": 14, "passed": 14, "failed": 0 },
    { "tag": "@api", "tests": 31, "passed": 31, "failed": 0 },
    { "tag": "@web3", "tests": 14, "passed": 14, "failed": 0 }
  ],
  "slow_tests": [
    { "name": "swap de tokens — flujo completo", "time_seconds": 1.2, "tags": ["@e2e"] }
  ],
  "tests": [
    {
      "name": "...",
      "status": "passed",
      "time_seconds": 0.4,
      "tags": ["@api"],
      "file": "tests/api/rpc-jsonrpc.spec.ts",
      "line": 12
    }
  ]
}
```

Si se pasa `--previous`, la salida incluye además `previous`, `current` y `delta` para comparar con la corrida anterior.

## Integración con CI

El job `contractuales` en `.github/workflows/playwright.yml` ejecuta los contractuales
opcionales en schedule (cron diario). Este módulo puede usarse como paso opcional
después de la suite de tests para generar el reporte JSON.

## Nota sobre este run

Este módulo fue escrito sin poder compilarlo en el entorno actual (no hay
`ghcup`/`ghc`/`cabal` instalados). Se debe instalar la toolchain de Haskell
antes de poder compilar y probar. Véase `docs/ROADMAP.md` (Fase 10).
