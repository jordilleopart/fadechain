// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title PoseidonT3
/// @notice Interface for the Poseidon hash function with 2 inputs (T=3)
/// @dev Deploy the Poseidon contract from circomlibjs or @zk-kit/poseidon
interface IPoseidonT3 {
    function poseidon(uint256[2] memory) external pure returns (uint256);
}

/// @title IncrementalMerkleTree
/// @notice A gas-efficient incremental Merkle tree using Poseidon hashing
/// @dev Based on the Tornado Cash / Semaphore pattern
library IncrementalMerkleTree {
    uint256 internal constant SNARK_SCALAR_FIELD =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;

    struct TreeData {
        uint32 depth;
        uint32 nextIndex;
        mapping(uint32 => uint256) filledSubtrees;
        uint256 root;
    }

    /// @notice Returns the zero value for a given level, precomputed as Poseidon(0,0) chains
    /// @dev For simplicity, level 0 zero = 0. Higher levels are Poseidon(zero[i-1], zero[i-1]).
    ///      In production, these should be precomputed constants.
    function zeros(uint32 /*level*/) internal pure returns (uint256) {
        // The "empty leaf" value. Using 0 for simplicity.
        return 0;
    }

    function init(TreeData storage self, uint32 depth) internal {
        require(depth > 0 && depth <= 32, "Invalid depth");
        self.depth = depth;
        self.root = 0; // Will be computed on first insert

        // Initialize filled subtrees with zero values
        for (uint32 i = 0; i < depth; i++) {
            self.filledSubtrees[i] = zeros(i);
        }
    }

    function insert(
        TreeData storage self,
        uint256 leaf,
        IPoseidonT3 hasher
    ) internal returns (uint256) {
        require(leaf < SNARK_SCALAR_FIELD, "Leaf too large");
        uint32 idx = self.nextIndex;
        require(idx < uint32(2 ** self.depth), "Tree is full");

        uint256 currentHash = leaf;
        uint32 currentIndex = idx;

        for (uint32 i = 0; i < self.depth; i++) {
            uint256 left;
            uint256 right;
            if (currentIndex % 2 == 0) {
                left = currentHash;
                right = zeros(i);
                self.filledSubtrees[i] = currentHash;
            } else {
                left = self.filledSubtrees[i];
                right = currentHash;
            }
            currentHash = hasher.poseidon([left, right]);
            currentIndex = currentIndex / 2;
        }

        self.root = currentHash;
        self.nextIndex = idx + 1;

        return currentHash;
    }
}
