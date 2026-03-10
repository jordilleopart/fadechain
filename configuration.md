# ZK Time-Decay Voting System

**Challenge 3 — Cryptography & Security Hackathon (UPF 2025)**

A *privacy-preserving* voting system where the **vote weight decays linearly over time**: voting early gives more influence than voting late. **zk-SNARKs (Groth16)** are used so that no one can link a vote to the voter's identity.

---

## Table of Contents

1. [Project Structure](#project-structure)
2. [Prerequisites](#prerequisites)
3. [Step-by-Step Deployment in Remix](#step-by-step-deployment-in-remix)
4. [Using the Frontend](#using-the-frontend)
5. [Relayer (Optional)](#relayer-optional)
6. [Complete Protocol Flow](#complete-protocol-flow)
7. [Voter Registration — Complete Details](#voter-registration--complete-details)
8. [Protocol Design](#protocol-design)
9. [Scenarios and Actors](#scenarios-and-actors)
10. [Threat Model](#threat-model)
11. [Cryptographic Primitives](#cryptographic-primitives)
12. [ZK Circuit (Circom)](#zk-circuit-circom)

---

## Project Structure

```
├── remix/
│   ├── 1_MockVerifier.sol           # Mock Groth16 verifier (always returns true)
│   ├── 2_PoseidonT3Stub.sol         # Poseidon hash stub (uses keccak256 % BN128)
│   ├── 3_ZKTimeDecayVoting.sol      # Main contract (100% standalone, no imports)
│   └── frontend_remix_demo.html     # Complete frontend (MetaMask + Relayer)
├── relayer/
│   ├── server.js                    # Node.js server that relays votes
│   ├── package.json                 # Relayer dependencies
│   └── .env.example                 # Environment variables template
├── circuits/
│   └── vote.circom                  # Reference ZK circuit (Circom)
└── readme.md                        # This file
```

---

## Prerequisites

| Tool | Purpose | Where to get it |
|---|---|---|
| **MetaMask** | Sign transactions, interact with Sepolia | [metamask.io](https://metamask.io) |
| **Sepolia ETH** | Pay gas on testnet | [sepoliafaucet.com](https://sepoliafaucet.com) or [Google Cloud faucet](https://cloud.google.com/application/web3/faucet/ethereum/sepolia) |
| **Remix IDE** | Compile and deploy contracts | [remix.ethereum.org](https://remix.ethereum.org) |
| **Node.js 18+** | Only if using the relayer (optional) | [nodejs.org](https://nodejs.org) |

### Configure MetaMask for Sepolia

1. Open MetaMask → Networks → **Add network** → Select **Sepolia test network**.
2. Go to a Sepolia faucet and request test ETH (~0.05 ETH needed).
3. Verify the balance appears in MetaMask.

---

## Step-by-Step Deployment in Remix

### Step 1 — Open Remix IDE

1. Go to [https://remix.ethereum.org](https://remix.ethereum.org).
2. In the file explorer (left panel), create a folder called `zk-voting/`.
3. Inside that folder, create 3 files by copying the **exact** content from the files in `remix/`:
   - `1_MockVerifier.sol`
   - `2_PoseidonT3Stub.sol`
   - `3_ZKTimeDecayVoting.sol`

### Step 2 — Compile the contracts

1. Go to the **Solidity Compiler** tab (S-shaped icon in the left panel).
2. Configure:
   - **Compiler version**: `0.8.20` (or higher within 0.8.x)
   - **EVM Version**: `paris`
   - Check **Enable optimization** → Runs: `200`
3. Compile each file in order:
   - First `1_MockVerifier.sol`
   - Then `2_PoseidonT3Stub.sol`
   - Finally `3_ZKTimeDecayVoting.sol`
4. Verify there are no errors (SPDX warning can be ignored).

### Step 3 — Connect MetaMask to Remix

1. Go to the **Deploy & Run Transactions** tab (arrow icon).
2. In **Environment**, select **Injected Provider - MetaMask**.
3. MetaMask will request connection — accept and make sure you're on **Sepolia network**.
4. The account with Sepolia ETH will appear in the **Account** field.

### Step 4 — Deploy Contract 1: MockGroth16Verifier

1. In the contracts dropdown, select **MockGroth16Verifier** (from `1_MockVerifier.sol`).
2. Click **Deploy**.
3. MetaMask will ask to confirm the transaction → **Confirm**.
4. Once mined, the contract will appear in "Deployed Contracts".
5. **Copy the contract address** (click the copy icon next to the name). Example: `0xABC123...`

### Step 5 — Deploy Contract 2: PoseidonT3Stub

1. Select **PoseidonT3Stub** in the dropdown.
2. **Deploy** → Confirm in MetaMask.
3. **Copy the address** of the deployed contract. Example: `0xDEF456...`

### Step 6 — Deploy Contract 3: ZKTimeDecayVoting

This is the main contract. The constructor needs 5 parameters:

| Parameter | Type | Description |
|---|---|---|
| `_verifier` | address | The MockGroth16Verifier address (Step 4) |
| `_hasher` | address | The PoseidonT3Stub address (Step 5) |
| `_votingStart` | uint256 | Unix timestamp for voting start |
| `_votingEnd` | uint256 | Unix timestamp for voting end |
| `_numChoices` | uint256 | Number of options (e.g., 3 for options 0, 1, 2) |

#### How to get Unix timestamps

Use [https://www.unixtimestamp.com/](https://www.unixtimestamp.com/) or run in the browser console:

```javascript
// Start: in 5 minutes
Math.floor(Date.now() / 1000) + 300

// End: in 2 hours
Math.floor(Date.now() / 1000) + 7200
```

#### Deployment example

In the Remix "Deploy" fields, fill in (comma-separated if Remix requires it):

```
_verifier:    0xABC123...   (address from Step 4)
_hasher:      0xDEF456...   (address from Step 5)
_votingStart: 1750000000    (future timestamp, voting start)
_votingEnd:   1750007200    (end timestamp, 2 hours later)
_numChoices:  3             (three options: 0, 1, 2)
```

> **Important:** `_votingStart` must be a **future** timestamp (after the current time). Voter registration happens BEFORE voting starts.

1. Fill in the 5 fields → **Deploy** → Confirm in MetaMask.
2. **Copy the address** of the `ZKTimeDecayVoting` contract. This is the main address.

---

## Using the Frontend

### Option A — Direct mode (MetaMask)

1. Open the file `remix/frontend_remix_demo.html` in a web browser (double-click or drag to browser).
2. In the **Configure Contract** section:
   - Paste the deployed `ZKTimeDecayVoting` contract address.
   - Paste the `PoseidonT3Stub` contract address.
   - Leave RPC Network at `https://rpc.sepolia.org`.
   - Select **MetaMask (direct)** mode.
3. Click **Connect**.

### Option B — Relayer mode (greater privacy)

1. First configure and run the relayer (see [Relayer section](#relayer-optional)).
2. In the frontend's **Configure Contract** section:
   - Paste the addresses as before.
   - Select **Relayer** mode.
   - Enter the relayer URL: `http://localhost:3001`.
3. Click **Connect**.

### Frontend Flow

After connecting, the frontend automatically shows the **current voting phase**:

#### 1. Registration Phase (before `votingStart`)

- Click **Generate ZK Credentials**.
  - The frontend generates a random `nullifier` and a random `secret`.
  - Calculates the `commitment = StubPoseidon(nullifier, secret)`.
  - **SAVE THE CREDENTIALS** that appear in the log — they are needed to vote.
- Click **Register Voter** to send the commitment to the contract.
  - In MetaMask mode: it will sign the transaction from your wallet.
  - In Relayer mode: the relayer will send the transaction for you.
- The admin must repeat this process for each eligible voter (or each voter does it themselves).

#### 2. Close Registration (Admin only)

- The admin (the wallet that deployed the contract) clicks **Close Registration**.
- This fixes the Merkle Tree root and enables the voting phase.
- **Important:** Once closed, no more voters can be registered.

> **Note:** Registration must be closed **before** `votingStart` arrives. If not closed, no one can vote.

#### 3. Voting Phase (between `votingStart` and `votingEnd`)

- The weight bar shows the **current vote weight** (100% at start, decaying towards 0%).
- Select a vote option (0, 1, 2...).
- If credentials were generated before, they are used automatically. If not, paste the saved `nullifier` and `secret`.
- Click **Submit Vote**.
  - The frontend generates a dummy proof (compatible with MockVerifier).
  - The vote is recorded with the weight corresponding to the submission time.
  - The nullifier hash appears to confirm the vote was processed.

#### 4. Results (after `votingEnd`)

- Click **View Results** to see the weighted count per option.
- The winning option and weighted votes for each option are displayed.

---

## Relayer (Optional)

The relayer is a Node.js server that receives votes from voters and sends them to the blockchain using its own wallet. This hides the voter's address.

### Configuration

```bash
# 1. Enter the relayer directory
cd relayer

# 2. Install dependencies
npm install

# 3. Copy the configuration template
cp .env.example .env

# 4. Edit .env with real values
```

### Environment variables (relayer/.env)

```env
SEPOLIA_RPC_URL=https://rpc.sepolia.org
RELAYER_PRIVATE_KEY=your_private_key_here
VOTING_CONTRACT_ADDRESS=0x_ZKTimeDecayVoting_contract_address
RELAYER_PORT=3001
```

> **How to get the relayer's private key:** In MetaMask, create a new account dedicated to the relayer → Account → Details → Export private key. Send Sepolia ETH to this account so it can pay for gas.

### Run

```bash
node server.js
```

The server starts at `http://localhost:3001`. Endpoints:

| Endpoint | Method | Description |
|---|---|---|
| `/api/status` | GET | Contract status and current weight |
| `/api/register` | POST | Register a voter (sends commitment) |
| `/api/relay-vote` | POST | Submit a vote with ZK proof |
| `/api/results` | GET | Final voting results |

---

## Complete Protocol Flow

```
┌──────────────┐     ┌───────────────┐     ┌─────────────────┐     ┌────────────┐
│  DEPLOYMENT  │────▶│  REGISTRATION │────▶│  VOTING         │────▶│  TALLY     │
│              │     │               │     │                 │     │            │
│ Admin deploys│     │ Voters        │     │ Votes with      │     │ Weighted   │
│ 3 contracts  │     │ generate      │     │ temporal weight │     │ results    │
│ with Remix   │     │ commitments   │     │ + ZK proof      │     │ on-chain   │
└──────────────┘     │ and register  │     │                 │     └────────────┘
                     │               │     │ Weight = 100% → 0%│
                     │ Admin closes  │     │ (linear         │
                     │ registration  │     │  decay)         │
                     └───────────────┘     └─────────────────┘
```

**Example timeline:**

```
t=0            t=300s (5min)      t=300s          t=7500s (2h5min)
│              │                  │               │
▼              ▼                  ▼               ▼
Deploy ────── Registration ────── votingStart ────── votingEnd
              (close registration  Weight=100%       Weight=0%
               before here)        ──────────▶       Tally
```

---

## Voter Registration — Complete Details

Registration is the most important phase. Here's how it works step by step:

### What is a "commitment"

Each voter generates two secret random numbers:
- **nullifier**: will be used later to derive a `nullifierHash` that prevents double voting.
- **secret**: additional randomness factor.

The **commitment** is the hash of these two values:

```
commitment = PoseidonStub(nullifier, secret)
           = keccak256(abi.encodePacked(nullifier, secret)) % SNARK_FIELD
```

The commitment is uploaded to the contract (public), but no one can reverse it to obtain the nullifier or secret.

### How a voter registers

1. **Generate credentials** (off-chain, in the frontend):
   - The frontend generates random `nullifier` and `secret` (256 bits each, reduced modulo SNARK_FIELD).
   - Calculates the `commitment`.
   - Displays the credentials for the voter to save.

2. **Send the commitment to the contract** (on-chain):
   - Calls `registerVoter(commitment)`.
   - The contract inserts the commitment as a leaf in an **incremental Merkle Tree** (depth 20 = up to ~1 million voters).
   - The contract emits the `VoterRegistered(commitment, leafIndex, newRoot)` event.
   - Each insertion updates the Merkle Tree root.

3. **Save credentials**:
   - The voter **must save** their `nullifier` and `secret`. Without them, they won't be able to vote.
   - Example credentials shown by the frontend:
     ```
     Nullifier: 1928374650918273649501827364950...
     Secret:    7362910485736291048573629104857...
     Commitment: 4829175036482917503648291750364...
     ```

### Who can register voters

- **Any address** can call `registerVoter()` while registration is open.
- In a real scenario, the admin could add access control (whitelist). In this demo, it's open.
- The important thing is that the voter **never reveals** their nullifier/secret when registering — only the commitment.

### Closing registration

- Only the **admin** (the wallet that deployed the contract) can call `closeRegistration()`.
- This:
  1. Sets `registrationOpen = false`.
  2. Emits `RegistrationClosed(finalRoot, totalRegistered)`.
- After closing, no one else can register and voting can begin.

### Why the Merkle Tree

The Merkle Tree allows the voter to **prove they are registered** without revealing **which commitment is theirs**. When voting, the voter provides a ZK proof that says:

> "I know a `(nullifier, secret)` such that `Poseidon(nullifier, secret)` is a leaf of this Merkle Tree with root `root`, and the `nullifierHash = Poseidon(nullifier)` is this value."

The contract verifies the proof and accepts the vote without knowing who voted.

---

## Protocol Design

### Weight Formula (Time Decay)

$$w(t) = \frac{T_{end} - t}{T_{end} - T_{start}} \times 10^{18}$$

Where $t$ = `block.timestamp`.

| Moment | Weight |
|---|---|
| $t = T_{start}$ | $10^{18}$ (100%) |
| $t = T_{start} + \frac{duration}{2}$ | $5 \times 10^{17}$ (50%) |
| $t = T_{end}$ | $0$ (0%) |

Fixed-point arithmetic with 18 decimals (`PRECISION = 1e18`) is used to avoid truncation in Solidity.

The minimum weight is **5%** (`MIN_WEIGHT = PRECISION / 20`). Votes below this threshold are rejected to avoid insignificant-weight votes.

### Immutability

Critical parameters are `immutable` in the constructor:
- `verifier`, `hasher`, `admin`, `votingStart`, `votingEnd`, `numChoices`

No one can change them after deployment, not even the admin.

---

## Scenarios and Actors

### Use case: DAO governance with early decision incentive

A vote that decays over time makes sense in:

- **DAOs**: Incentivize members to participate early. Those who research and vote early have more weight than those who wait to see the trend (eliminates the *bandwagon* effect).
- **Participatory budgets**: Citizens who inform themselves and vote quickly have more influence.
- **Anti-collusion**: An adversary trying to coordinate a group needs to do so at the beginning, when there's less information.

### Actors

| Actor | Role | Trust |
|---|---|---|
| **Admin** | Deploys contract, defines parameters, closes registration | Semi-trusted: we trust the configuration. The contract limits their power post-deployment (immutables). |
| **Voters** | Generate commitments, cast votes with ZK proof | Honest-but-curious: they follow the protocol, but might try to spy on others' votes. |
| **Validators** | Produce blocks, set `block.timestamp` | Semi-adversarial: ~12-15s margin to manipulate timestamps (PoS). |
| **Observers** | Read the blockchain, analyze patterns | Passive adversaries: try to de-anonymize voters. |
| **Relayer** | Sends TX on behalf of the voter | Semi-trusted: knows the proof but cannot alter it. |

---

## Threat Model

### 1. `block.timestamp` Manipulation

**Attack:** A validator-voter produces a block with timestamp close to `votingStart` to obtain higher weight.

**Mitigation:**
- In Ethereum PoS, the timestamp must be strictly increasing and within ~12s of the expected slot.
- `MIN_WEIGHT` of 5% prevents zero-weight votes.
- Possible improvement: discretize into epochs (N time slots) instead of using exact seconds.

### 2. Front-running / Mempool Analysis

**Attack:** An adversary sees votes in the mempool and uses that information.

**Mitigation:**
- The `voteChoice` is a public input of the ZK proof (visible in the TX).
- Use relayer + private mempool (Flashbots Protect on mainnet). On Sepolia, this is accepted as a limitation.
- Improvement: encrypt `voteChoice` with a commit-reveal scheme.

### 3. Double Voting (replay)

**Attack:** Reuse the same proof or generate another with the same credentials.

**Mitigation:** The `nullifierHash = Poseidon(nullifier)` is deterministic. The contract stores `usedNullifiers[hash] = true` and rejects duplicates. **Already mitigated in the design.**

### 4. Linkability via Network Analysis

**Attack:** Correlate the Ethereum address with the voter's identity.

**Mitigation:** Use the relayer, which sends the TX from its own address.

### 5. Malicious Admin

**Attack:** The admin modifies `votingEnd` or the Merkle root post-deploy.

**Mitigation:** All critical parameters are `immutable`. The admin can only execute `closeRegistration()`.

---

## Cryptographic Primitives

| Primitive | Implementation | Property |
|---|---|---|
| **zk-SNARKs (Groth16)** | Circom + snarkjs / MockVerifier (demo) | Zero-Knowledge: verifies vote validity without revealing voter. ~256 byte proof. |
| **Poseidon Hash** | PoseidonT3Stub (keccak256 % BN128 for demo) | ZK-friendly, ~8x fewer constraints than SHA-256 in arithmetic circuit. |
| **Merkle Tree** | Incremental, depth 20 (~1M leaves) | Membership proof without revealing which leaf belongs to the voter. |
| **Nullifier scheme** | `nullifierHash = Poseidon(nullifier)` | Prevents double voting without revealing identity. Deterministic per voter. |
| **Fixed-point** | `PRECISION = 1e18` | Avoids fraction truncation in Solidity (no floats). |

### Why Groth16 and not PLONK or STARKs?

| Criterion | Groth16 | PLONK | STARKs |
|---|---|---|---|
| Proof size | ~128 bytes | ~400 bytes | ~50-200 KB |
| Verification gas | ~200K | ~300K | ~1-2M |
| Trusted Setup | Yes (per circuit) | Universal | No |
| Tooling | Excellent (Circom) | Good | Limited on-chain |

For a hackathon on Sepolia, Groth16 is optimal: lower gas, mature tooling, and the trusted setup is acceptable for a PoC.

### Note on MockVerifier

In the hackathon demo, a `MockGroth16Verifier` that always returns `true` is used. This allows testing the entire flow without needing to compile the Circom circuit or run the trusted setup ceremony. In production, it would be replaced with a real verifier generated by snarkjs.

---

## ZK Circuit (Circom)

The file `circuits/vote.circom` contains the reference circuit for production:

```
Template Vote:
  Private inputs: nullifier, secret, pathElements[20], pathIndices[20]
  Public inputs:  root, nullifierHash, voteChoice

  Constraints:
    1. commitment = Poseidon(nullifier, secret)
    2. Merkle proof: commitment is a leaf of the tree with root 'root'
    3. nullifierHash == Poseidon(nullifier)
    4. voteChoice is bound to the proof (cannot be changed post-generation)
```

To compile the circuit (in production):

```bash
# Compile
circom circuits/vote.circom --r1cs --wasm --sym -o build/

# Trusted setup (Phase 1)
snarkjs powersoftau new bn128 15 pot15_0000.ptau -v
snarkjs powersoftau contribute pot15_0000.ptau pot15_0001.ptau --name="First"
snarkjs powersoftau prepare phase2 pot15_0001.ptau pot15_final.ptau

# Phase 2
snarkjs groth16 setup build/vote.r1cs pot15_final.ptau vote_0000.zkey
snarkjs zkey contribute vote_0000.zkey vote_final.zkey --name="Contributor 1"
snarkjs zkey export verificationkey vote_final.zkey verification_key.json

# Export Solidity verifier
snarkjs zkey export solidityverifier vote_final.zkey Groth16Verifier.sol
```

---

## Quick Deployment Summary

```
1. Remix → Compile 3 contracts (Solidity 0.8.20, optimizer 200)
2. MetaMask → Connect to Sepolia with test ETH
3. Deploy MockGroth16Verifier → copy address
4. Deploy PoseidonT3Stub → copy address
5. Deploy ZKTimeDecayVoting(verifier, hasher, start, end, numChoices)
6. Open frontend_remix_demo.html → paste addresses → connect
7. Generate credentials → Register voters → Admin closes registration
8. Wait for votingStart → Vote → Early votes weigh more
9. After votingEnd → View weighted results
```

---

*Hackathon UPF 2025 — Cryptography & Security — Challenge 3: Voting System with Temporal Decay + ZK Privacy*
