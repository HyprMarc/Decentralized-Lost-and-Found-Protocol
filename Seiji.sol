// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Seiji Asset Recovery Protocol
 * @dev Manages the registration, finding, and deterministic reward settlement of lost physical items.
 * Integrates zero-knowledge proximity verification concepts and DAO arbitration to align economic incentives.
 */
contract Seiji {
    // ==========================================
    // SECURITY & MODIFIERS
    // ==========================================

    // A standard boolean lock to prevent Reentrancy attacks.
    // This stops malicious actors from repeatedly calling a function before the first execution finishes.
    bool private locked;
    modifier nonReentrant() {
        require(!locked, "No re-entrancy allowed");
        locked = true;
        _;
        locked = false;
    }

    // Restricts function execution exclusively to the wallet address that originally registered the item.
    modifier onlyOwner(uint256 _itemId) {
        require(items[_itemId].owner == msg.sender, "Caller is not the item owner");
        _;
    }

    // ==========================================
    // STATE VARIABLES & STRUCTS
    // ==========================================

    // Defines the deterministic lifecycle stages of a lost item within the smart contract.
    enum ItemStatus { REGISTERED, FOUND, RETURNED, DISPUTED, CANCELED }

    struct Item {
        address owner;             // The wallet address of the user who lost the item
        address finder;            // The wallet address of the user who successfully verifies proximity
        string itemType;           // Broad category categorization (e.g., "Electronics", "Wallet")
        bytes32 descriptionHash;   // Cryptographic hash of the item's private details to ensure data privacy
        string lostGeohash;        // The general regional spatial grid where the item was lost
        uint256 rewardDeposit;     // The financial bounty locked in the trustless escrow by the owner
        uint256 finderStake;       // FEATURE 4: The anti-spam deposit locked by the finder to prevent griefing
        ItemStatus status;         // Current operational state of the item
        uint256 createdAt;         // Timestamp of when the asset was registered on the ledger
        uint256 foundAt;           // FEATURE 1: Timestamp of when the item was reported found (starts the timeout clock)
    }

    uint256 public nextItemId;                 // Auto-incrementing identifier for newly registered items
    mapping(uint256 => Item) public items;     // On-chain storage mapping of all items by their ID
    
    // Protocol Economics & Governance Variables
    address public treasury;                   // Decentralized pool where protocol fees and slashed stakes are sent
    address public daoArbitrator;              // Address of the DAO smart contract that handles decentralized arbitration
    uint256 public protocolFeeBasisPoints = 150; // Protocol fee taken from successful returns (150 bps = 1.5%)
    uint256 public treasuryBalance;            // Tracks total systemic liquidity collected from fees and slashed funds
    
    // Timeouts and Crypto-Economic Thresholds
    uint256 public claimTimeout = 7 days;      // FEATURE 1: How long a finder must wait to auto-claim if the owner vanishes
    uint256 public requiredFinderStake = 0.01 ether; // FEATURE 4: The mandatory financial stake required to report an item as found

    // ==========================================
    // EVENTS
    // ==========================================
    
    event ItemRegistered(uint256 indexed itemId, address indexed owner, string geohash, uint256 reward);
    event ItemCanceled(uint256 indexed itemId);
    event ItemFound(uint256 indexed itemId, address indexed finder, bytes32 locationCommitment, uint256 stake);
    event RewardReleased(uint256 indexed itemId, address indexed finder, uint256 amount, uint256 feeToTreasury);
    event DisputeStarted(uint256 indexed itemId);
    event DisputeResolved(uint256 indexed itemId, address indexed winner, uint256 amount, bool stakeSlashed);
    event TimeoutClaimed(uint256 indexed itemId, address indexed finder, uint256 amount);

    // ==========================================
    // CONSTRUCTOR
    // ==========================================

    /**
     * @dev Initializes the contract with the required treasury and DAO addresses.
     */
    constructor(address _treasury, address _daoArbitrator) {
        treasury = _treasury;
        daoArbitrator = _daoArbitrator; 
    }

    // ==========================================
    // CORE PROTOCOL FUNCTIONS
    // ==========================================

    /**
     * @notice Step 1: Owner registers a lost item and locks the reward in escrow.
     * @param _itemType Broad category of the item.
     * @param _descriptionHash Hash of specific identifiers (serial numbers, etc.) to keep exact details private.
     * @param _lostGeohash The general spatial index (macro-level) where the item was lost.
     * @return The unique ID of the newly registered item.
     */
    function registerItem(
        string memory _itemType,
        bytes32 _descriptionHash,
        string memory _lostGeohash
    ) external payable returns (uint256) {
        require(msg.value > 0, "Reward must be greater than 0");

        uint256 itemId = nextItemId++;
        items[itemId] = Item({
            owner: msg.sender,
            finder: address(0),
            itemType: _itemType,
            descriptionHash: _descriptionHash,
            lostGeohash: _lostGeohash,
            rewardDeposit: msg.value, // Escrow the bounty to guarantee deterministic settlement
            finderStake: 0,
            status: ItemStatus.REGISTERED,
            createdAt: block.timestamp,
            foundAt: 0
        });

        emit ItemRegistered(itemId, msg.sender, _lostGeohash, msg.value);
        return itemId;
    }

    /**
     * @notice FEATURE 3: Allows the owner to cancel the search and withdraw their funds if the item hasn't been found.
     * This ensures capital is not permanently locked if the owner finds the item themselves.
     */
    function cancelRegistration(uint256 _itemId) external nonReentrant onlyOwner(_itemId) {
        Item storage item = items[_itemId];
        require(item.status == ItemStatus.REGISTERED, "Can only cancel if item is in REGISTERED state");

        item.status = ItemStatus.CANCELED;
        
        uint256 refundAmount = item.rewardDeposit;
        item.rewardDeposit = 0; // State change: Zero out balance before external transfer to prevent reentrancy

        (bool success, ) = msg.sender.call{value: refundAmount}("");
        require(success, "Refund transfer failed");

        emit ItemCanceled(_itemId);
    }

    /**
     * @notice Step 2: Finder reports the item as found. 
     * @dev FEATURE 4: Requires a financial stake to prevent geographic spoofing and spam attacks.
     * @param _locationCommitment Hash of the exact coordinates for future dispute verification.
     * @param _zkProof Zero-Knowledge proof verifying physical proximity to the Geohash.
     */
    function reportFound(
        uint256 _itemId,
        bytes32 _locationCommitment,
        bytes memory _zkProof
    ) external payable nonReentrant {
        Item storage item = items[_itemId];
        require(item.status == ItemStatus.REGISTERED, "Item is not currently looking for a finder");
        
        // Anti-Griefing Barrier: Makes brute-forcing or spamming the contract financially unviable.
        require(msg.value == requiredFinderStake, "Must attach the exact required stake to prevent spam");
        
        // Verifies the ZK proof to ensure the finder is actually in the correct geographic micro-domain.
        require(verifyMockZKProof(_zkProof), "Invalid Zero-Knowledge proximity proof");

        item.finder = msg.sender;
        item.finderStake = msg.value; // Lock the finder's stake alongside the owner's reward
        item.status = ItemStatus.FOUND;
        item.foundAt = block.timestamp; // Start the timeout clock to protect the finder

        emit ItemFound(_itemId, msg.sender, _locationCommitment, msg.value);
    }

    /**
     * @dev Mock verifier for the zk-SNARK proximity proof (PoPoK). 
     * In a production environment, this would interface with a compiled Groth16 or Plonk verifier contract.
     */
    function verifyMockZKProof(bytes memory _zkProof) internal pure returns (bool) {
        return _zkProof.length > 0;
    }

    /**
     * @notice Step 3: Owner confirms they received the item physical handover.
     * Releases the locked reward to the finder and returns the finder's original anti-spam stake.
     */
    function confirmReturn(uint256 _itemId) external nonReentrant onlyOwner(_itemId) {
        Item storage item = items[_itemId];
        require(item.status == ItemStatus.FOUND, "Item must be in FOUND state");
        
        item.status = ItemStatus.RETURNED;
        
        uint256 totalReward = item.rewardDeposit;
        uint256 finderStake = item.finderStake;
        
        // Zero out balances before transferring to maintain contract integrity
        item.rewardDeposit = 0;
        item.finderStake = 0;

        // Calculate the DAO protocol fee for maintaining systemic liquidity
        uint256 fee = (totalReward * protocolFeeBasisPoints) / 10000;
        uint256 finalReward = totalReward - fee;

        treasuryBalance += fee;

        // Cooperative outcome: Transfer the reward PLUS the original stake back to the honest finder
        (bool finderSuccess, ) = item.finder.call{value: finalReward + finderStake}("");
        require(finderSuccess, "Transfer to finder failed");
        
        emit RewardReleased(_itemId, item.finder, finalReward, fee);

    }

    /**
     * @notice FEATURE 1: Allows the finder to claim the funds if the owner disappears (the "Hostage" problem).
     * Ensures finders are mathematically guaranteed compensation if they perform the work but the owner fails to sign.
     */
    function claimTimeoutReward(uint256 _itemId) external nonReentrant {
        Item storage item = items[_itemId];
        require(item.status == ItemStatus.FOUND, "Item must be in FOUND state");
        require(msg.sender == item.finder, "Only the designated finder can claim a timeout");
        
        // Ensure the mandatory waiting period has passed since the ZK proof was submitted
        require(block.timestamp >= item.foundAt + claimTimeout, "Timeout period has not been reached yet");

        item.status = ItemStatus.RETURNED;
        
        uint256 totalReward = item.rewardDeposit;
        uint256 finderStake = item.finderStake;
        
        item.rewardDeposit = 0;
        item.finderStake = 0;

        uint256 fee = (totalReward * protocolFeeBasisPoints) / 10000;
        uint256 finalReward = totalReward - fee;

        treasuryBalance += fee;

        // Deterministic Payout: Finder gets reward + their stake back
        (bool success, ) = item.finder.call{value: finalReward + finderStake}("");
        require(success, "Transfer to finder failed");

        emit TimeoutClaimed(_itemId, msg.sender, finalReward);
    }

    // ==========================================
    // DISPUTE & ARBITRATION FUNCTIONS
    // ==========================================

    /**
     * @notice Freezes the item state and escalates the claim to the DAO Arbitrator if the physical handover fails.
     */
    function raiseDispute(uint256 _itemId) external onlyOwner(_itemId) {
        Item storage item = items[_itemId];
        require(item.status == ItemStatus.FOUND, "Can only dispute items that are marked FOUND");
        
        item.status = ItemStatus.DISPUTED;
        
        emit DisputeStarted(_itemId);
    }

    /**
     * @notice FEATURE 2 & 4: Called EXCLUSIVELY by the DAO smart contract after a Schelling-point majority vote.
     * Resolves the dispute and executes the slashing mechanics for malicious actors.
     * @param _payFinder Boolean indicating the DAO's consensus. True = Finder wins, False = Owner wins.
     */
    function resolveDispute(uint256 _itemId, bool _payFinder) external nonReentrant {
        require(msg.sender == daoArbitrator, "Only the authorized DAO contract can resolve disputes");
        
        Item storage item = items[_itemId];
        require(item.status == ItemStatus.DISPUTED, "Item is not currently in dispute");

        item.status = ItemStatus.RETURNED; 
        
        uint256 totalReward = item.rewardDeposit;
        uint256 finderStake = item.finderStake;
        
        item.rewardDeposit = 0;
        item.finderStake = 0;

        if (_payFinder) {
            // Outcome A: DAO rules in favor of the Finder (e.g., Owner retrieved item but maliciously refused to sign).
            // Finder receives the bounty (minus fee) AND gets their anti-spam stake back.
            uint256 fee = (totalReward * protocolFeeBasisPoints) / 10000;
            uint256 payout = totalReward - fee;
            treasuryBalance += fee;

            (bool success, ) = item.finder.call{value: payout + finderStake}("");
            require(success, "Transfer to finder failed");
            
            emit DisputeResolved(_itemId, item.finder, payout, false);
            
        } else {
            // Outcome B: DAO rules in favor of the Owner (e.g., Finder spoofed location or failed to deliver).
            // Owner gets their entire bounty refunded. 
            // Finder's stake is SLASHED and redirected to the protocol treasury to penalize fraud.
            treasuryBalance += finderStake; 

            (bool success, ) = item.owner.call{value: totalReward}("");
            require(success, "Refund transfer to owner failed");
            
            emit DisputeResolved(_itemId, item.owner, totalReward, true);
        }
    }
}
