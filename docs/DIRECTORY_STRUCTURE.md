# Aetherlink Contracts Directory Structure

## Overview

The Aetherlink Contracts project is organized with a clear separation of concerns, dividing the codebase into source contracts, scripts, tests, and deployment utilities.

## Root Directory

```
/
├── .git/                    # Git repository data
├── .github/                 # GitHub workflows and configuration
├── artifacts/               # Compiled contract artifacts
├── cache/                   # Build cache
├── contracts/               # Solidity smart contracts
├── contracts-dbg/           # Debugging artifacts
├── deploy/                  # Deployment scripts and configs
├── docs/                    # Project documentation
├── ignition/                # Deployment and initialization modules
├── node_modules/            # Node.js dependencies
├── scripts/                 # Automation and utility scripts
├── test/                    # JavaScript test cases
├── .gitignore               # Git ignore configuration
├── LICENSE                  # License information
├── README.md                # Project documentation
├── azure-pipelines.yml      # Azure CI/CD pipeline config
├── foundry.toml             # Foundry configuration
├── hardhat.config.js        # Hardhat configuration
├── package.json             # Node.js project manifest
├── package-lock.json        # Node.js lockfile
```

## contracts/

```
contracts/
├── RampImplementation.sol   # Core cross-chain ramp contract
├── Proxy.sol                # Upgradeable proxy contract
├── Ramp.sol                 # Entry point contract
├── MockContracts/           # Mock contracts for testing
├── interfaces/              # Solidity interfaces
├── libraries/               # Solidity libraries (empty)
```

## scripts/

Automation scripts for deployment, verification, and contract management.

## test/

JavaScript test cases for validating contract logic and integration.

## ignition/

Deployment and initialization modules (empty by default).

## artifacts/ & cache/

Build outputs and cache for Solidity compilation.

## docs/

Project documentation, including tracker and module documentation.

---

_This file is maintained automatically as part of the development workflow._ 