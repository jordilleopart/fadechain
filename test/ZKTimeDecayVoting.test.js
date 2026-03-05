/**
 * Tests for ZKTimeDecayVoting
 *
 * Tests the on-chain logic: time-decay weight calculation, registration,
 * double-vote prevention, and phase transitions.
 *
 * Note: ZK proof verification is tested with a mock verifier that always
 * returns true. Full integration tests with real proofs require the circuit
 * setup to be completed first.
 */

const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("ZKTimeDecayVoting", function () {
  let voting, verifier, hasher;
  let admin, voter1, voter2;
  let votingStart, votingEnd;

  const NUM_CHOICES = 3;
  const PRECISION = ethers.parseEther("1"); // 1e18

  beforeEach(async function () {
    [admin, voter1, voter2] = await ethers.getSigners();

    // Deploy mock verifier (always returns true for testing)
    const MockVerifier = await ethers.getContractFactory("MockGroth16Verifier");
    verifier = await MockVerifier.deploy();

    // Deploy Poseidon stub
    const PoseidonStub = await ethers.getContractFactory("PoseidonT3Stub");
    hasher = await PoseidonStub.deploy();

    // Voting: starts in 60s, lasts 3600s (1 hour)
    const now = await time.latest();
    votingStart = now + 60;
    votingEnd = votingStart + 3600;

    const Voting = await ethers.getContractFactory("ZKTimeDecayVoting");
    voting = await Voting.deploy(
      await verifier.getAddress(),
      await hasher.getAddress(),
      votingStart,
      votingEnd,
      NUM_CHOICES
    );
  });

  describe("Deployment", function () {
    it("Should set immutable parameters correctly", async function () {
      expect(await voting.votingStart()).to.equal(votingStart);
      expect(await voting.votingEnd()).to.equal(votingEnd);
      expect(await voting.numChoices()).to.equal(NUM_CHOICES);
      expect(await voting.admin()).to.equal(admin.address);
      expect(await voting.registrationOpen()).to.equal(true);
    });
  });

  describe("Registration", function () {
    it("Should allow registering voter commitments", async function () {
      const commitment = 12345n;
      await expect(voting.registerVoter(commitment))
        .to.emit(voting, "VoterRegistered");
    });

    it("Should reject registration after close", async function () {
      await voting.closeRegistration();
      await expect(voting.registerVoter(99999n))
        .to.be.revertedWithCustomError(voting, "RegistrationNotOpen");
    });

    it("Should only allow admin to close registration", async function () {
      await expect(voting.connect(voter1).closeRegistration())
        .to.be.revertedWithCustomError(voting, "OnlyAdmin");
    });
  });

  describe("Time-Decay Weight", function () {
    beforeEach(async function () {
      // Register a voter and close registration
      await voting.registerVoter(12345n);
      await voting.closeRegistration();
    });

    it("Should return full weight at votingStart", async function () {
      await time.increaseTo(votingStart);
      const weight = await voting.getCurrentWeight();
      expect(weight).to.equal(PRECISION);
    });

    it("Should return ~50% weight at midpoint", async function () {
      const midpoint = votingStart + 1800; // halfway
      await time.increaseTo(midpoint);
      const weight = await voting.getCurrentWeight();

      // Should be approximately 0.5e18 (allow 1 second tolerance)
      const halfWeight = PRECISION / 2n;
      const tolerance = PRECISION / 3600n; // 1 second worth
      expect(weight).to.be.closeTo(halfWeight, tolerance);
    });

    it("Should return ~0 weight near votingEnd", async function () {
      await time.increaseTo(votingEnd - 1);
      const weight = await voting.getCurrentWeight();
      // 1 second before end → weight ≈ 1/3600 ≈ 0.028%
      expect(weight).to.be.lessThan(PRECISION / 100n); // less than 1%
    });

    it("Should return 0 weight outside voting period", async function () {
      // Before voting starts
      const weight1 = await voting.getCurrentWeight();
      expect(weight1).to.equal(0);

      // After voting ends
      await time.increaseTo(votingEnd + 1);
      const weight2 = await voting.getCurrentWeight();
      expect(weight2).to.equal(0);
    });
  });

  describe("Voting", function () {
    const dummyProofA = [0n, 0n];
    const dummyProofB = [[0n, 0n], [0n, 0n]];
    const dummyProofC = [0n, 0n];
    const dummyRoot = 0n;
    const nullifier1 = 111n;
    const nullifier2 = 222n;

    beforeEach(async function () {
      // Register and close
      await voting.registerVoter(12345n);
      await voting.closeRegistration();

      // Mark root as known (the root after inserting the commitment)
      // In a real scenario, the root is automatically stored
    });

    it("Should reject votes before voting starts", async function () {
      await expect(
        voting.castVote(dummyProofA, dummyProofB, dummyProofC, dummyRoot, nullifier1, 0)
      ).to.be.revertedWithCustomError(voting, "VotingNotActive");
    });

    it("Should reject votes after voting ends", async function () {
      await time.increaseTo(votingEnd + 1);
      await expect(
        voting.castVote(dummyProofA, dummyProofB, dummyProofC, dummyRoot, nullifier1, 0)
      ).to.be.revertedWithCustomError(voting, "VotingNotActive");
    });

    it("Should reject invalid choice", async function () {
      await time.increaseTo(votingStart);
      await expect(
        voting.castVote(dummyProofA, dummyProofB, dummyProofC, dummyRoot, nullifier1, NUM_CHOICES)
      ).to.be.revertedWithCustomError(voting, "InvalidChoice");
    });

    it("Should reject unknown merkle root", async function () {
      await time.increaseTo(votingStart);
      const unknownRoot = 999999n;
      await expect(
        voting.castVote(dummyProofA, dummyProofB, dummyProofC, unknownRoot, nullifier1, 0)
      ).to.be.revertedWithCustomError(voting, "InvalidMerkleRoot");
    });

    it("Should reject double voting (same nullifier)", async function () {
      await time.increaseTo(votingStart);
      const root = await voting.getMerkleRoot();

      // First vote succeeds
      await voting.castVote(dummyProofA, dummyProofB, dummyProofC, root, nullifier1, 0);

      // Second vote with same nullifier fails
      await expect(
        voting.castVote(dummyProofA, dummyProofB, dummyProofC, root, nullifier1, 1)
      ).to.be.revertedWithCustomError(voting, "NullifierAlreadyUsed");
    });

    it("Should accept valid votes and accumulate weighted tallies", async function () {
      await time.increaseTo(votingStart);
      const root = await voting.getMerkleRoot();

      // Vote at the start (weight ≈ 1.0)
      await voting.castVote(dummyProofA, dummyProofB, dummyProofC, root, nullifier1, 0);

      const tally0 = await voting.getVoteTally(0);
      expect(tally0).to.be.greaterThan(0);
      expect(await voting.totalVoteCount()).to.equal(1);

      // Second voter at midpoint (weight ≈ 0.5)
      await time.increaseTo(votingStart + 1800);
      await voting.castVote(dummyProofA, dummyProofB, dummyProofC, root, nullifier2, 1);

      const tally1 = await voting.getVoteTally(1);
      expect(tally1).to.be.greaterThan(0);
      expect(tally1).to.be.lessThan(tally0); // Later vote has less weight
      expect(await voting.totalVoteCount()).to.equal(2);
    });
  });

  describe("Results", function () {
    it("Should revert getResults before voting ends", async function () {
      await expect(voting.getResults())
        .to.be.revertedWithCustomError(voting, "VotingNotEnded");
    });

    it("Should return correct results after voting ends", async function () {
      await voting.registerVoter(12345n);
      await voting.closeRegistration();

      await time.increaseTo(votingStart);
      const root = await voting.getMerkleRoot();

      // Cast a vote for choice 1
      await voting.castVote([0, 0], [[0, 0], [0, 0]], [0, 0], root, 111n, 1);

      await time.increaseTo(votingEnd + 1);
      const [choices, winner] = await voting.getResults();

      expect(winner).to.equal(1);
      expect(choices[1]).to.be.greaterThan(0);
      expect(choices[0]).to.equal(0);
    });
  });
});
