const crypto = require('crypto');

// Colors for console output
const colors = {
    reset: "\x1b[0m",
    owner: "\x1b[36m", // Cyan
    finder: "\x1b[32m", // Green
    contract: "\x1b[33m", // Yellow
    validator: "\x1b[35m", // Magenta
    bold: "\x1b[1m",
    red: "\x1b[31m"
};

// Simplified hash function
function hash(data) {
    return crypto.createHash('sha256').update(data).digest('hex');
}

// Helper to format currency
const usd = (val) => `$${val.toFixed(2)}`;

class SmartContract {
    constructor() {
        this.items = {};
        this.nextItemId = 1;

        // Treasury/Reward Pools
        this.treasuryTotalUSD = 10000; // Baseline DAO reserve
        this.protocolFeeRate = 0.015; // 1.5% fee on rewards to route into Treasury

        // Track hypothetical wallet balances for simulation context
        this.wallets = {
            alice: 500,  // Alice's hypothetical ETH converted to USD equivalence
            bob: 20      // Bob's initial balance
        };

        // Network Gas Fees (Arbitrary amounts)
        this.gasFees = {
            register: 1.50, // Fee to write item to chain
            verifyProof: 0.85, // Gas to verify ZK proof
            confirmReturn: 1.25 // Gas to transfer reward
        };

        console.log(`${colors.contract}[Network] Seiji Protocol Deployed. Baseline Treasury Pool Balance: ${usd(this.treasuryTotalUSD)}${colors.reset}`);
    }

    displayBalances() {
        console.log(`\n  --- OVERVIEW OF BALANCES ---`);
        console.log(`  Alice Wallet: ${colors.owner}${usd(this.wallets.alice)}${colors.reset}`);
        console.log(`  Bob Wallet: ${colors.finder}${usd(this.wallets.bob)}${colors.reset}`);
        console.log(`  Seiji Treasury Pool: ${colors.validator}${usd(this.treasuryTotalUSD)}${colors.reset}`);
        console.log(`  -------------------------------\n`);
    }

    // Step 1: Registration
    registerItem(ownerKey, itemType, descHash, geohash, rewardAmount) {
        console.log(`${colors.contract}[Contract] Charging Gas Fee for Registration: ${usd(this.gasFees.register)}${colors.reset}`);
        this.wallets[ownerKey] -= this.gasFees.register;

        console.log(`${colors.contract}[Contract] Escrowing ${usd(rewardAmount)} reward for new item...${colors.reset}`);
        this.wallets[ownerKey] -= rewardAmount;

        let id = this.nextItemId++;
        this.items[id] = {
            id,
            owner: ownerKey,
            finder: null,
            itemType,
            descriptionHash: descHash,
            lostGeohash: geohash,
            rewardLocked: rewardAmount,
            status: "REGISTERED",
            timestamp: Date.now()
        };

        console.log(`${colors.contract}[Contract] Item #${id} (${itemType}) registered at Geohash: ${geohash}.${colors.reset}\n`);
        return id;
    }

    // Step 2 & 3: Finding and ZK Proof Verification
    reportFound(itemId, finderKey, zkProofBytes, locationCommitment) {
        if (!this.items[itemId] || this.items[itemId].status !== "REGISTERED") {
            throw new Error("Item not available for finding");
        }

        console.log(`${colors.contract}[Contract] Bob pays Gas Fee for ZK Verification: ${usd(this.gasFees.verifyProof)}${colors.reset}`);
        this.wallets[finderKey] -= this.gasFees.verifyProof;

        console.log(`${colors.contract}[Contract] Verifying ZK Proof for Item #${itemId}...${colors.reset}`);

        let isProofValid = this.verifyZK(zkProofBytes, this.items[itemId].lostGeohash);
        if (isProofValid) {
            this.items[itemId].finder = finderKey;
            this.items[itemId].status = "FOUND";
            console.log(`${colors.contract}[Contract] ZK Proof Verified! Proximity check passed.${colors.reset}`);
            console.log(`${colors.contract}[Contract] Item #${itemId} marked as FOUND. Waiting for Owner to confirm return.${colors.reset}\n`);
        } else {
            console.log(`${colors.red}[Contract] ZK Proof failed. Verification rejected.${colors.reset}\n`);
        }
    }

    verifyZK(proof, expectedGeohash) {
        return proof.includes(expectedGeohash) && proof.includes("valid");
    }

    // Step 5: Reward Release
    confirmReturn(itemId, ownerKey) {
        let item = this.items[itemId];
        if (item.owner !== ownerKey) throw new Error("Only owner can confirm");

        console.log(`${colors.contract}[Contract] Alice pays Gas Fee to confirm return: ${usd(this.gasFees.confirmReturn)}${colors.reset}`);
        this.wallets[ownerKey] -= this.gasFees.confirmReturn;

        console.log(`${colors.contract}[Contract] Processing return confirmation for Item #${itemId}...${colors.reset}`);
        item.status = "RETURNED";

        let reward = item.rewardLocked;
        item.rewardLocked = 0;

        // Fee distribution: X% to Treasury, rest to Finder
        let protocolFee = reward * this.protocolFeeRate;
        let finderReward = reward - protocolFee;

        // Route to Treasury Pool
        this.treasuryTotalUSD += protocolFee;

        // Give Finder their portion
        this.wallets[item.finder] += finderReward;

        console.log(`${colors.contract}[Contract] Seiji Treasury captures ${this.protocolFeeRate * 100}% Protocol Fee: ${usd(protocolFee)}${colors.reset}`);
        console.log(`${colors.contract}[Contract] Transferring Finder Reward: ${usd(finderReward)} to ${item.finder}'s wallet.${colors.reset}\n`);
    }
}

// -------------------------------------------------------------
// Simulation Execution
// -------------------------------------------------------------
async function runSimulation() {
    console.log(`\n${colors.bold}=== STARTING SEIJI PROTOCOL SIMULATION ===${colors.reset}\n`);

    const seijiContract = new SmartContract();

    // Show initial balances
    seijiContract.displayBalances();

    // --- 1. Owner Action ---
    console.log(`${colors.owner}[Owner Alice] I lost my Prada leather wallet at the local mall. Registering it on Seiji...${colors.reset}`);
    const rewardUsd = 100;

    // We pass our "keys" ('alice' and 'bob') so the contract updates local balances appropriately inline.
    const itemId = seijiContract.registerItem(
        "alice",
        "Black Wallet",
        hash("Black Prada leather wallet"),
        "w21z7",
        rewardUsd
    );

    await new Promise(r => setTimeout(r, 800));
    console.log(`... [12 Hours Later] ...\n`);

    // --- 2. Finder Action ---
    console.log(`${colors.finder}[Finder Bob] Found a wallet on a bench! Scanning registry tag...${colors.reset}`);
    const proof = `zk_proof_proximity_w21z7_valid`;

    console.log(`${colors.finder}[Finder Bob] Off-chain ZK circuit compiled. Submitting Proof to Seiji...${colors.reset}`);
    seijiContract.reportFound(itemId, "bob", proof, "location_hash_0x123");

    await new Promise(r => setTimeout(r, 800));

    // --- 4. Off-Chain Chat Action ---
    console.log(`${colors.validator}[Off-Chain P2P Network] Alice & Bob initiate E2E chat using Seiji messenger, and meet at the coffee shop.${colors.reset}\n`);

    // --- 5. Return Confirmation ---
    console.log(`${colors.owner}[Owner Alice] I got my wallet back! Marking as returned on-chain...${colors.reset}`);
    seijiContract.confirmReturn(itemId, "alice");

    // Final Balances
    console.log(`${colors.bold}=== POST-TRANSACTION RESOLUTION ===${colors.reset}`);
    seijiContract.displayBalances();
    console.log(`${colors.bold}=== SIMULATION COMPLETE ===${colors.reset}\n`);
}

runSimulation();
