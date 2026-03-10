// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ════════════════════════════════════════════════════════════════════════════
//  FILE 3: ZKTimeDecayVoting (FLATTENED FOR REMIX)
//  Deploy THIRD — pass the Verifier and Poseidon addresses from steps 1 & 2
//
//  This file is self-contained: all interfaces and libraries are inlined.
//  No imports needed.
// ════════════════════════════════════════════════════════════════════════════

// ──────────────────────────── Interfaces ────────────────────────────

interface IGroth16Verifier {
    function verifyProof(
        uint[2] calldata _pA,
        uint[2][2] calldata _pB,
        uint[2] calldata _pC,
        uint[3] calldata _pubSignals
    ) external view returns (bool);
}

interface IPoseidonT3 {
    function poseidon(uint256[2] memory) external pure returns (uint256);
}

// ──────────────────────────── Incremental Merkle Tree Library ────────────────────────────

library IncrementalMerkleTree {
    uint256 internal constant SNARK_SCALAR_FIELD =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;

    struct TreeData {
        uint32 depth;
        uint32 nextIndex;
        mapping(uint32 => uint256) filledSubtrees;
        uint256 root;
    }

    function zeros(uint32) internal pure returns (uint256) {
        return 0;
    }

    function init(TreeData storage self, uint32 depth) internal {
        require(depth > 0 && depth <= 32, "Invalid depth");
        self.depth = depth;
        self.root = 0;
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

// ──────────────────────────── Main Contract ────────────────────────────

/// @title ZKTimeDecayVoting
/// @notice Privacy-preserving voting with time-decaying weight + zk-SNARKs
/// @author Hackathon UPF 2026 — Cryptography & Security
contract ZKTimeDecayVoting {
    using IncrementalMerkleTree for IncrementalMerkleTree.TreeData;

    // ── Constants ──
    uint256 public constant PRECISION = 1e18;
    uint256 public constant MIN_WEIGHT = PRECISION / 20; // 5%
    uint32 public constant TREE_DEPTH = 20;

    // ── Immutable ──
    IGroth16Verifier public immutable verifier;
    IPoseidonT3 public immutable hasher;
    address public immutable admin;
    uint256 public immutable votingStart;
    uint256 public immutable votingEnd;
    uint256 public immutable numChoices;

    // ── State ──
    IncrementalMerkleTree.TreeData internal commitmentTree;
    bool public registrationOpen;
    mapping(uint256 => bool) public knownRoots;
    mapping(uint256 => bool) public usedNullifiers;
    mapping(uint256 => uint256) public voteTally;
    uint256 public totalWeightedVotes;
    uint256 public totalVoteCount;

    // ── Events ──
    event VoterRegistered(uint256 indexed commitment, uint256 leafIndex, uint256 newRoot);
    event RegistrationClosed(uint256 finalRoot, uint256 totalRegistered);
    event VoteCast(uint256 indexed nullifierHash, uint256 choice, uint256 weight, uint256 timestamp);

    // ── Errors ──
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

    // ── Modifiers ──
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

    // ── Constructor ──
    /// @param _verifier Address of MockGroth16Verifier (or real Groth16Verifier)
    /// @param _hasher   Address of PoseidonT3Stub (or real Poseidon)
    /// @param _votingStart Unix timestamp — when voting opens
    /// @param _votingEnd   Unix timestamp — when voting closes
    /// @param _numChoices  Number of options (0..numChoices-1)
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

    // ── Registration ──

    function registerVoter(uint256 commitment) external duringRegistration {
        uint256 newRoot = commitmentTree.insert(commitment, hasher);
        knownRoots[newRoot] = true;
        emit VoterRegistered(commitment, commitmentTree.nextIndex - 1, newRoot);
    }

    function closeRegistration() external onlyAdmin duringRegistration {
        registrationOpen = false;
        emit RegistrationClosed(commitmentTree.root, commitmentTree.nextIndex);
    }

    // ── Voting ──

    function castVote(
        uint[2] calldata _pA,
        uint[2][2] calldata _pB,
        uint[2] calldata _pC,
        uint256 _root,
        uint256 _nullifierHash,
        uint256 _voteChoice
    ) external duringVoting {
        if (_voteChoice >= numChoices) revert InvalidChoice();
        if (!knownRoots[_root]) revert InvalidMerkleRoot();
        if (usedNullifiers[_nullifierHash]) revert NullifierAlreadyUsed();

        uint[3] memory pubSignals = [_root, _nullifierHash, _voteChoice];
        bool isValid = verifier.verifyProof(_pA, _pB, _pC, pubSignals);
        if (!isValid) revert InvalidProof();

        uint256 weight = _calculateWeight();
        if (weight < MIN_WEIGHT) revert WeightTooLow();

        usedNullifiers[_nullifierHash] = true;
        voteTally[_voteChoice] += weight;
        totalWeightedVotes += weight;
        totalVoteCount += 1;

        emit VoteCast(_nullifierHash, _voteChoice, weight, block.timestamp);
    }

    // ── View Functions ──

    function getCurrentWeight() external view returns (uint256 weight) {
        if (block.timestamp < votingStart || block.timestamp >= votingEnd) return 0;
        return _calculateWeight();
    }

    function getVoteTally(uint256 choice) external view returns (uint256) {
        return voteTally[choice];
    }

    function getMerkleRoot() external view returns (uint256) {
        return commitmentTree.root;
    }

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

    // ── Internal ──

    /// @dev weight = (votingEnd - now) / (votingEnd - votingStart) * 1e18
    ///      t=start → 1e18 (100%)   |   t=end → 0 (0%)
    function _calculateWeight() internal view returns (uint256) {
        uint256 duration = votingEnd - votingStart;
        uint256 remaining = votingEnd - block.timestamp;
        return (remaining * PRECISION) / duration;
    }
}
