// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IGroth16Verifier
/// @notice Interface for the auto-generated Groth16 verifier from snarkjs
interface IGroth16Verifier {
    /// @notice Verifies a Groth16 proof
    /// @param _pA Proof element A (2 elements)
    /// @param _pB Proof element B (2x2 elements)
    /// @param _pC Proof element C (2 elements)
    /// @param _pubSignals Public signals array [root, nullifierHash, voteChoice]
    /// @return True if the proof is valid
    function verifyProof(
        uint[2] calldata _pA,
        uint[2][2] calldata _pB,
        uint[2] calldata _pC,
        uint[3] calldata _pubSignals
    ) external view returns (bool);
}
