// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IGroth16Verifier.sol";
import "./IncrementalMerkleTree.sol";

/// @title ZKTimeDecayVoting
/// @notice A privacy-preserving voting system with time-decaying vote weight.
///         Uses zk-SNARKs (Groth16) to prove vote eligibility without revealing identity,
///         and a linear decay function so earlier votes carry more weight.
/// @author Hackathon UPF - Cryptography & Security
contract ZKTimeDecayVoting {
    using IncrementalMerkleTree for IncrementalMerkleTree.TreeData;

    // ──────────────────────────── Constants ────────────────────────────
    /// @notice Fixed-point precision (18 decimals) for weight arithmetic
    uint256 public constant PRECISION = 1e18;

    /// @notice Minimum weight threshold — votes below this are rejected
    /// @dev Prevents near-zero-weight votes and mitigates timestamp manipulation
    uint256 public constant MIN_WEIGHT = PRECISION / 20; // 5% of full weight

    /// @notice Merkle tree depth (supports up to 2^20 ≈ 1M voters)
    uint32 public constant TREE_DEPTH = 20;

    // ──────────────────────────── Immutable state ────────────────────────────
    /// @notice Groth16 proof verifier (auto-generated from snarkjs)
    IGroth16Verifier public immutable verifier;

    /// @notice Poseidon hasher contract
    IPoseidonT3 public immutable hasher;

    /// @notice Admin address that manages registration phase
    address public immutable admin;

    /// @notice Voting period start timestamp (inclusive)
    uint256 public immutable votingStart;

    /// @notice Voting period end timestamp (exclusive)
    uint256 public immutable votingEnd;

    /// @notice Number of voting options (candidates/choices)
    uint256 public immutable numChoices;

    // ──────────────────────────── Mutable state ────────────────────────────
    /// @notice Incremental Merkle tree for voter commitments
    IncrementalMerkleTree.TreeData internal commitmentTree;

    /// @notice Whether registration is still open
    bool public registrationOpen;

    /// @notice Known Merkle roots (to allow proofs against any historical root)
    mapping(uint256 => bool) public knownRoots;

    /// @notice Used nullifier hashes (prevents double voting)
    mapping(uint256 => bool) public usedNullifiers;

    /// @notice Weighted vote tally per choice
    mapping(uint256 => uint256) public voteTally;

    /// @notice Total weighted votes cast
    uint256 public totalWeightedVotes;

    /// @notice Total number of votes cast
    uint256 public totalVoteCount;

    // ──────────────────────────── Events ────────────────────────────
    event VoterRegistered(uint256 indexed commitment, uint256 leafIndex, uint256 newRoot);
    event RegistrationClosed(uint256 finalRoot, uint256 totalRegistered);
    event VoteCast(
        uint256 indexed nullifierHash,
        uint256 choice,
        uint256 weight,
        uint256 timestamp
    );

    // ──────────────────────────── Errors ────────────────────────────
    error OnlyAdmin();
    error RegistrationNotOpen();
    error RegistrationStillOpen();
    error VotingNotActive();
    error InvalidProof();
    error NullifierAlreadyUsed();
    error InvalidChoice();
    error InvalidMerkleRoot();
    error WeightTooLow();
    error VotingNotEnded();

    // ──────────────────────────── Modifiers ────────────────────────────
    modifier onlyAdmin() {
        if (msg.sender != admin) revert OnlyAdmin();
        _;
    }

    modifier duringRegistration() {
        if (!registrationOpen) revert RegistrationNotOpen();
        _;
    }

    modifier duringVoting() {
        if (registrationOpen) revert RegistrationStillOpen();
        if (block.timestamp < votingStart || block.timestamp >= votingEnd)
            revert VotingNotActive();
        _;
    }

    // ──────────────────────────── Constructor ────────────────────────────
    /// @param _verifier Address of the deployed Groth16 verifier contract
    /// @param _hasher Address of the deployed Poseidon T3 hasher contract
    /// @param _votingStart Unix timestamp when voting opens
    /// @param _votingEnd Unix timestamp when voting closes
    /// @param _numChoices Number of valid voting options (0 to numChoices-1)
    constructor(
        address _verifier,
        address _hasher,
        uint256 _votingStart,
        uint256 _votingEnd,
        uint256 _numChoices
    ) {
        require(_votingStart < _votingEnd, "Invalid voting period");
        require(_numChoices > 0, "Need at least one choice");
        require(_verifier != address(0) && _hasher != address(0), "Zero address");

        verifier = IGroth16Verifier(_verifier);
        hasher = IPoseidonT3(_hasher);
        admin = msg.sender;
        votingStart = _votingStart;
        votingEnd = _votingEnd;
        numChoices = _numChoices;

        registrationOpen = true;
        commitmentTree.init(TREE_DEPTH);
    }

    // ──────────────────────────── Registration Phase ────────────────────────────

    /// @notice Register a voter commitment into the Merkle tree
    /// @param commitment Poseidon(nullifier, secret) computed off-chain
    function registerVoter(uint256 commitment) external duringRegistration {
        uint256 newRoot = commitmentTree.insert(commitment, hasher);
        knownRoots[newRoot] = true;

        emit VoterRegistered(commitment, commitmentTree.nextIndex - 1, newRoot);
    }

    /// @notice Close registration and fix the Merkle tree
    /// @dev Only admin. After this, no more commitments can be added.
    function closeRegistration() external onlyAdmin duringRegistration {
        registrationOpen = false;
        emit RegistrationClosed(commitmentTree.root, commitmentTree.nextIndex);
    }

    // ──────────────────────────── Voting Phase ────────────────────────────

    /// @notice Cast a vote with a ZK proof of eligibility
    /// @param _pA Groth16 proof element A
    /// @param _pB Groth16 proof element B
    /// @param _pC Groth16 proof element C
    /// @param _root Merkle root the proof was generated against
    /// @param _nullifierHash Hash of the voter's nullifier (public, for double-vote check)
    /// @param _voteChoice The option the voter is voting for (0 to numChoices-1)
    function castVote(
        uint[2] calldata _pA,
        uint[2][2] calldata _pB,
        uint[2] calldata _pC,
        uint256 _root,
        uint256 _nullifierHash,
        uint256 _voteChoice
    ) external duringVoting {
        // 1. Check the choice is valid
        if (_voteChoice >= numChoices) revert InvalidChoice();

        // 2. Check the Merkle root is known
        if (!knownRoots[_root]) revert InvalidMerkleRoot();

        // 3. Check the nullifier hasn't been used
        if (usedNullifiers[_nullifierHash]) revert NullifierAlreadyUsed();

        // 4. Verify the ZK proof
        uint[3] memory pubSignals = [_root, _nullifierHash, _voteChoice];
        bool isValid = verifier.verifyProof(_pA, _pB, _pC, pubSignals);
        if (!isValid) revert InvalidProof();

        // 5. Calculate time-decayed weight
        uint256 weight = _calculateWeight();
        if (weight < MIN_WEIGHT) revert WeightTooLow();

        // 6. Record the vote
        usedNullifiers[_nullifierHash] = true;
        voteTally[_voteChoice] += weight;
        totalWeightedVotes += weight;
        totalVoteCount += 1;

        emit VoteCast(_nullifierHash, _voteChoice, weight, block.timestamp);
    }

    // ──────────────────────────── View Functions ────────────────────────────

    /// @notice Get the current vote weight at this moment
    /// @return weight The vote weight with PRECISION decimals
    function getCurrentWeight() external view returns (uint256 weight) {
        if (block.timestamp < votingStart || block.timestamp >= votingEnd) return 0;
        return _calculateWeight();
    }

    /// @notice Get the weighted vote tally for a specific choice
    /// @param choice The voting option index
    /// @return The weighted vote count (divide by PRECISION for human-readable form)
    function getVoteTally(uint256 choice) external view returns (uint256) {
        return voteTally[choice];
    }

    /// @notice Get the current Merkle tree root
    function getMerkleRoot() external view returns (uint256) {
        return commitmentTree.root;
    }

    /// @notice Get results for all choices after voting ends
    /// @return choices Array of weighted tallies for each choice
    /// @return winner Index of the winning choice
    function getResults()
        external
        view
        returns (uint256[] memory choices, uint256 winner)
    {
        if (block.timestamp < votingEnd) revert VotingNotEnded();

        choices = new uint256[](numChoices);
        uint256 maxVotes = 0;

        for (uint256 i = 0; i < numChoices; i++) {
            choices[i] = voteTally[i];
            if (choices[i] > maxVotes) {
                maxVotes = choices[i];
                winner = i;
            }
        }
    }

    // ──────────────────────────── Internal ────────────────────────────

    /// @notice Calculates linear time-decaying vote weight
    /// @dev weight = (votingEnd - block.timestamp) * PRECISION / (votingEnd - votingStart)
    ///      At votingStart → weight = PRECISION (1.0)
    ///      At votingEnd   → weight = 0
    function _calculateWeight() internal view returns (uint256) {
        uint256 duration = votingEnd - votingStart;
        uint256 remaining = votingEnd - block.timestamp;
        return (remaining * PRECISION) / duration;
    }
}
