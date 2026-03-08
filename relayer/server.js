/**
 * Relayer Service for ZK Time-Decay Voting
 *
 * This Node.js server receives ZK proofs + votes from the frontend
 * and submits them to the smart contract using its own funded wallet.
 *
 * WHY A RELAYER?
 * - The voter's Ethereum address is NOT linked to their vote.
 * - The relayer pays gas, so voters don't even need ETH.
 * - The relayer CANNOT alter the proof or the vote — the ZK proof binds them.
 *
 * Usage:
 *   1. Set env vars in relayer/.env
 *   2. node relayer/server.js
 */

const express = require("express");
const cors = require("cors");
const { ethers } = require("ethers");
require("dotenv").config({ path: __dirname + "/.env" });

// ── Config ──
const PORT = process.env.PORT || process.env.RELAYER_PORT || 3001;
const RPC_URL = process.env.SEPOLIA_RPC_URL || "https://rpc.sepolia.org";
const RELAYER_PRIVATE_KEY = process.env.RELAYER_PRIVATE_KEY;
const VOTING_CONTRACT_ADDRESS = process.env.VOTING_CONTRACT_ADDRESS;

if (!RELAYER_PRIVATE_KEY || !VOTING_CONTRACT_ADDRESS) {
  console.error("❌ Missing RELAYER_PRIVATE_KEY or VOTING_CONTRACT_ADDRESS in relayer/.env");
  process.exit(1);
}

// ── ABI (only the functions we need) ──
const VOTING_ABI = [
  "function castVote(uint[2] _pA, uint[2][2] _pB, uint[2] _pC, uint256 _root, uint256 _nullifierHash, uint256 _voteChoice) external",
  "function registerVoter(uint256 commitment) external",
  "function getCurrentWeight() external view returns (uint256)",
  "function getVoteTally(uint256 choice) external view returns (uint256)",
  "function numChoices() external view returns (uint256)",
  "function votingStart() external view returns (uint256)",
  "function votingEnd() external view returns (uint256)",
  "function getMerkleRoot() external view returns (uint256)",
  "function registrationOpen() external view returns (bool)",
  "function knownRoots(uint256) external view returns (bool)",
  "function usedNullifiers(uint256) external view returns (bool)",
  "function totalVoteCount() external view returns (uint256)",
  "function getResults() external view returns (uint256[], uint256)",
];

// ── Provider & Signer ──
const provider = new ethers.JsonRpcProvider(RPC_URL);
const relayerWallet = new ethers.Wallet(RELAYER_PRIVATE_KEY, provider);
const votingContract = new ethers.Contract(VOTING_CONTRACT_ADDRESS, VOTING_ABI, relayerWallet);

// ── Express App ──
const app = express();
app.use(cors());
app.use(express.json({ limit: "1mb" }));

// Nonce management to avoid nonce collisions on concurrent requests
let pendingNonce = null;
async function getNextNonce() {
  if (pendingNonce === null) {
    pendingNonce = await relayerWallet.getNonce();
  }
  const nonce = pendingNonce;
  pendingNonce++;
  return nonce;
}

// Reset nonce on error
function resetNonce() {
  pendingNonce = null;
}

// ── Routes ──

/**
 * POST /api/relay-vote
 * Body: { pA, pB, pC, root, nullifierHash, voteChoice }
 *
 * The relayer submits the ZK proof + vote on behalf of the voter.
 */
app.post("/api/relay-vote", async (req, res) => {
  try {
    const { pA, pB, pC, root, nullifierHash, voteChoice } = req.body;

    // Basic validation
    if (!pA || !pB || !pC || root === undefined || nullifierHash === undefined || voteChoice === undefined) {
      return res.status(400).json({ error: "Missing required fields: pA, pB, pC, root, nullifierHash, voteChoice" });
    }

    // Validate array shapes
    if (!Array.isArray(pA) || pA.length !== 2) {
      return res.status(400).json({ error: "pA must be an array of 2 elements" });
    }
    if (!Array.isArray(pB) || pB.length !== 2 || !Array.isArray(pB[0]) || pB[0].length !== 2) {
      return res.status(400).json({ error: "pB must be a 2x2 array" });
    }
    if (!Array.isArray(pC) || pC.length !== 2) {
      return res.status(400).json({ error: "pC must be an array of 2 elements" });
    }

    // Validate voteChoice is a non-negative integer
    const choice = Number(voteChoice);
    if (!Number.isInteger(choice) || choice < 0) {
      return res.status(400).json({ error: "voteChoice must be a non-negative integer" });
    }

    console.log(`📩 Relay request: choice=${choice}, nullifier=${nullifierHash.toString().slice(0, 16)}...`);

    // Check if nullifier already used (avoid wasting gas)
    const isUsed = await votingContract.usedNullifiers(nullifierHash);
    if (isUsed) {
      return res.status(409).json({ error: "This nullifier has already been used (double vote detected)" });
    }

    // Submit the transaction
    const nonce = await getNextNonce();
    const tx = await votingContract.castVote(
      pA, pB, pC,
      root,
      nullifierHash,
      choice,
      { nonce }
    );

    console.log(`📤 TX sent: ${tx.hash}`);
    const receipt = await tx.wait();
    console.log(`✅ TX confirmed in block ${receipt.blockNumber}`);

    res.json({
      success: true,
      txHash: receipt.hash,
      blockNumber: receipt.blockNumber,
    });
  } catch (err) {
    resetNonce();
    console.error("❌ Relay error:", err.message);

    // Parse revert reason if available
    const revertMatch = err.message.match(/reason="([^"]+)"/);
    const customError = err.message.match(/reverted with custom error '([^']+)'/);
    const reason = revertMatch?.[1] || customError?.[1] || err.message;

    res.status(500).json({ error: `Transaction failed: ${reason}` });
  }
});

/**
 * POST /api/register
 * Body: { commitment }
 *
 * Register a voter commitment (relayer pays gas).
 */
app.post("/api/register", async (req, res) => {
  try {
    const { commitment } = req.body;
    if (!commitment) {
      return res.status(400).json({ error: "Missing commitment" });
    }

    console.log(`📩 Register request: commitment=${commitment.toString().slice(0, 16)}...`);

    const nonce = await getNextNonce();
    const tx = await votingContract.registerVoter(commitment, { nonce });
    console.log(`📤 TX sent: ${tx.hash}`);
    const receipt = await tx.wait();
    console.log(`✅ Registered in block ${receipt.blockNumber}`);

    res.json({
      success: true,
      txHash: receipt.hash,
      blockNumber: receipt.blockNumber,
    });
  } catch (err) {
    resetNonce();
    console.error("❌ Register error:", err.message);
    const reason = err.message.match(/reason="([^"]+)"/)?.[1] || err.message;
    res.status(500).json({ error: `Registration failed: ${reason}` });
  }
});

/**
 * GET /api/status
 * Returns contract state: registration open, voting times, current weight, tallies, etc.
 */
app.get("/api/status", async (req, res) => {
  try {
    const [
      regOpen,
      vStart,
      vEnd,
      nChoices,
      root,
      weight,
      totalVotes,
    ] = await Promise.all([
      votingContract.registrationOpen(),
      votingContract.votingStart(),
      votingContract.votingEnd(),
      votingContract.numChoices(),
      votingContract.getMerkleRoot(),
      votingContract.getCurrentWeight().catch(() => 0n),
      votingContract.totalVoteCount(),
    ]);

    // Get tallies for each choice
    const tallies = [];
    for (let i = 0; i < Number(nChoices); i++) {
      const tally = await votingContract.getVoteTally(i);
      tallies.push(tally.toString());
    }

    // Determine phase
    const now = Math.floor(Date.now() / 1000);
    let phase = "unknown";
    if (regOpen) phase = "registration";
    else if (now < Number(vStart)) phase = "waiting";
    else if (now < Number(vEnd)) phase = "voting";
    else phase = "ended";

    res.json({
      phase,
      registrationOpen: regOpen,
      votingStart: Number(vStart),
      votingEnd: Number(vEnd),
      numChoices: Number(nChoices),
      merkleRoot: root.toString(),
      currentWeight: weight.toString(),
      currentWeightPercent: (Number(weight) / 1e16).toFixed(2),
      totalVotes: Number(totalVotes),
      tallies,
      relayerAddress: relayerWallet.address,
    });
  } catch (err) {
    console.error("❌ Status error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

/**
 * GET /api/results
 * Returns final results after voting ends.
 */
app.get("/api/results", async (req, res) => {
  try {
    const [choices, winner] = await votingContract.getResults();
    res.json({
      choices: choices.map((c) => c.toString()),
      winner: Number(winner),
      choicesHumanReadable: choices.map((c) => (Number(c) / 1e18).toFixed(4)),
    });
  } catch (err) {
    const reason = err.message.match(/reason="([^"]+)"/)?.[1] || err.message;
    res.status(400).json({ error: reason });
  }
});

// ── Start ──
app.listen(PORT, () => {
  console.log(`\n🚀 ZK Voting Relayer running on http://localhost:${PORT}`);
  console.log(`   Relayer address: ${relayerWallet.address}`);
  console.log(`   Contract:        ${VOTING_CONTRACT_ADDRESS}`);
  console.log(`   RPC:             ${RPC_URL}\n`);
});
