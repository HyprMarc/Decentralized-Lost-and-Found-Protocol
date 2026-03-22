# Seiji: Decentralized Lost and Found System Protocol 🔍📦

![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)
![Solidity](https://img.shields.io/badge/Solidity-%5E0.8.19-363636?logo=solidity)
![Network](https://img.shields.io/badge/Network-Ethereum%20%7C%20Sepolia-627EEA?logo=ethereum)

Seiji is a **Decentralized Physical Infrastructure Network (DePIN)** designed to replace centralized lost-and-found systems. By utilizing programmable smart contracts, zero-knowledge proofs, and game theories, Seiji creates a trustless, privacy-centered, and highly efficient global market for recovering lost physical assets.

## 🌟 Core Features

* **Absolute Location Privacy:** Utilizes **Geohash** to map lost items to regional grids, ensuring users never have to broadcast their exact GPS coordinates to the public ledger.
* **Zero-Knowledge Proximity Verification (zk-SNARKs):** Finders must submit cryptographic proofs mathematically guaranteeing they are physically near the lost item's location, preventing remote spoofing without compromising their safety.
* **Trustless Escrow:** Financial bounties are locked in deterministic smart contracts. Finders are guaranteed payment upon successful return, and owners are protected from extortion.
* **Anti-Griefing Mechanisms:** Finders must lock a small financial stake (e.g., `0.01 ETH`) to report an item as found. This makes spamming the network or submitting false claims economically unviable.
* **Decentralized DAO Arbitration:** Edge cases and disputes are resolved by a decentralized pool of validators using a Schelling-point voting mechanism. Malicious actors face "slashing" penalties where their staked funds are confiscated.

---

## 🏗️ Protocol Lifecycle

1. **Register (`registerItem`):** An owner loses an item, hashes its private description, provides a regional Geohash, and deposits a reward into the contract's escrow.
2. **Discover (`reportFound`):** A finder locates the item, deposits an anti-spam stake, and submits a ZK-proof of proximity. The item state transitions to `FOUND` and a 7-day timeout clock begins.
3. **Settle (`confirmReturn`):** The physical handover occurs. The owner cryptographically signs the release, transferring the reward and returning the stake to the honest finder (minus a small protocol fee).
4. **Timeout (`claimTimeoutReward`):** If the owner vanishes after the item is reported found, the finder can claim the escrowed funds after a 7-day waiting period.
5. **Dispute (`raiseDispute` & `resolveDispute`):** If the handover fails, the owner can freeze the contract. The DAO Arbitrator votes on the outcome, slashing the funds of the dishonest party and rewarding the honest one.

---

## 💻 Developer Guide & Local Setup

### Prerequisites
* [Node.js](https://nodejs.org/) (v16+ recommended)
* [Hardhat](https://hardhat.org/)
* A wallet like [MetaMask](https://metamask.io/) for testnet deployment

### Installation
Clone the repository and install the required dependencies:

```bash
git clone [https://github.com/yourusername/seiji-protocol.git](https://github.com/yourusername/seiji-protocol.git)
cd seiji-protocol
npm install
