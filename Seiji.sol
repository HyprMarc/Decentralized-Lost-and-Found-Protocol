// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Seiji
 * @dev Manages the registration, finding, and reward distribution of lost items.
 */
contract Seiji {
    enum ItemStatus { REGISTERED, FOUND, RETURNED, DISPUTED }

    struct Item {
        address owner;
        address finder;
        string itemType;
        bytes32 descriptionHash;
        string lostGeohash;
        uint256 rewardDeposit;
        ItemStatus status;
        uint256 createdAt;
    }

    uint256 public nextItemId;
    mapping(uint256 => Item) public items;
    
    // Treasury pool variables
    address public treasury;
    uint256 public protocolFeeBasisPoints = 150; // 1.5% of the reward goes to the treasury (150 bps)
    uint256 public treasuryBalance;

    event ItemRegistered(uint256 indexed itemId, address indexed owner, string geohash, uint256 reward);
    event ItemFound(uint256 indexed itemId, address indexed finder, bytes32 locationCommitment);
    event RewardReleased(uint256 indexed itemId, address indexed finder, uint256 amount, uint256 feeToTreasury);
    event DisputeStarted(uint256 indexed itemId);

    // Modifier to ensure only the owner can call
    modifier onlyOwner(uint256 _itemId) {
        require(items[_itemId].owner == msg.sender, "Only owner can call this");
        _;
    }

    constructor(address _treasury) {
        treasury = _treasury;
    }

    /**
     * @dev Step 1: Owner registers an item with a reward
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
            rewardDeposit: msg.value,
            status: ItemStatus.REGISTERED,
            createdAt: block.timestamp
        });

        emit ItemRegistered(itemId, msg.sender, _lostGeohash, msg.value);
        return itemId;
    }

    /**
     * @dev Step 2 & 3: Finder discovers item and submits ZK proof
     * Mock function for the ZK verifier
     */
    function reportFound(
        uint256 _itemId,
        bytes32 _locationCommitment,
        bytes memory _zkProof
    ) external {
        Item storage item = items[_itemId];
        require(item.status == ItemStatus.REGISTERED, "Item is not in REGISTERED state");
        
        // In a real implementation, we would call a Groth16 or Plonk verifier here:
        require(verifyMockZKProof(_zkProof), "Invalid ZK proof");

        item.finder = msg.sender;
        item.status = ItemStatus.FOUND;

        emit ItemFound(_itemId, msg.sender, _locationCommitment);
    }

    /**
     * @dev Mock ZK proof verifier for demonstration
     */
    function verifyMockZKProof(bytes memory _zkProof) internal pure returns (bool) {
        // Assume proof is valid for this demo
        return _zkProof.length > 0;
    }

    /**
     * @dev Step 5: Owner confirms return and releases reward.
     * Takes the protocol fee and distributes to the treasury pool.
     */
    function confirmReturn(uint256 _itemId) external onlyOwner(_itemId) {
        Item storage item = items[_itemId];
        require(item.status == ItemStatus.FOUND, "Item must be FOUND");
        
        item.status = ItemStatus.RETURNED;
        
        uint256 totalReward = item.rewardDeposit;
        item.rewardDeposit = 0;

        uint256 fee = (totalReward * protocolFeeBasisPoints) / 10000;
        uint256 finalReward = totalReward - fee;

        treasuryBalance += fee;

        (bool finderSuccess, ) = item.finder.call{value: finalReward}("");
        require(finderSuccess, "Transfer to finder failed.");
        
        // Treasury holds funds, to be claimed/disbursed by DAO
        
        emit RewardReleased(_itemId, item.finder, finalReward, fee);
    }

    /**
     * @dev Step 6: Dispute
     */
    function raiseDispute(uint256 _itemId) external onlyOwner(_itemId) {
        Item storage item = items[_itemId];
        require(item.status == ItemStatus.FOUND, "Can only dispute FOUND items");
        item.status = ItemStatus.DISPUTED;
        
        emit DisputeStarted(_itemId);
        // Dispute logic to be handled by DAO arbitration pool
    }
}
