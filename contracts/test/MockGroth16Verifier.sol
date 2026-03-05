// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title MockGroth16Verifier
/// @notice Mock verifier that always returns true — for testing only
contract MockGroth16Verifier {
    function verifyProof(
        uint[2] calldata,
        uint[2][2] calldata,
        uint[2] calldata,
        uint[3] calldata
    ) external pure returns (bool) {
        return true;
    }
}
