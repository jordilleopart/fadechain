// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title PoseidonT3Stub
/// @notice Stub implementation of Poseidon(2) for local testing.
///         In production, deploy the real Poseidon contract from circomlibjs.
/// @dev Uses keccak256 modded into the BN128 scalar field as a placeholder.
///      THIS IS NOT CRYPTOGRAPHICALLY EQUIVALENT TO POSEIDON — only for testing.
contract PoseidonT3Stub {
    uint256 internal constant SNARK_SCALAR_FIELD =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;

    function poseidon(uint256[2] memory inputs) public pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(inputs[0], inputs[1]))) % SNARK_SCALAR_FIELD;
    }
}
