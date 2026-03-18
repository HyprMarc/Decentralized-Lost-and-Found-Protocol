// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Decentralized Lost and Found Protocol
 * @dev Manages the registration, finding, and reward distribution of lost items.
 */
contract LostAndFound {
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

    event ItemRegistered(uint256 indexed itemId, address indexed owner, string geohash, uint256 reward);
    event ItemFound(uint256 indexed itemId, address indexed finder, bytes32 locationCommitment);
    event RewardReleased(uint256 indexed itemId, address indexed finder, uint256 amount);
    event DisputeStarted(uint256 indexed itemId);

    // Modifier to ensure only the owner can call
    modifier onlyOwner(uint256 _itemId) {
        require(items[_itemId].owner == msg.sender, "Only owner can call this");
        _;
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
        // require(zkVerifier.verifyProof(_zkProof, [item.lostGeohash, _locationCommitment]), "Invalid location ZK proof");
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
     * @dev Step 5: Owner confirms return and releases reward
     */
    function confirmReturn(uint256 _itemId) external onlyOwner(_itemId) {
        Item storage item = items[_itemId];
        require(item.status == ItemStatus.FOUND, "Item must be FOUND");
        
        item.status = ItemStatus.RETURNED;
        uint256 amount = item.rewardDeposit;
        item.rewardDeposit = 0;

        (bool success, ) = item.finder.call{value: amount}("");
        require(success, "Transfer failed.");

        emit RewardReleased(_itemId, item.finder, amount);
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
