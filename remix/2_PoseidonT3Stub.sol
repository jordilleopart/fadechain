// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ════════════════════════════════════════════════════════════════════════════
//  FILE 2: PoseidonT3Stub
//  Deploy SECOND — hash function for the Merkle tree
//
//  NOTE: This uses keccak256 % BN128_FIELD as a Poseidon stand-in.
//  For a full ZK flow, deploy the real Poseidon from circomlibjs instead.
//  For the hackathon demo with MockVerifier, this works correctly.
// ════════════════════════════════════════════════════════════════════════════

contract PoseidonT3Stub {
    uint256 internal constant SNARK_SCALAR_FIELD =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;

    function poseidon(uint256[2] memory inputs) public pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(inputs[0], inputs[1]))) % SNARK_SCALAR_FIELD;
    }
}
