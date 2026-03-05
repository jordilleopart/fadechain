# fadechain
Privacy-preserving on-chain voting with Groth16 zero-knowledge proofs, incremental Merkle tree registration, and exponential temporal decay weighting — built in Solidity.


```mermaid
    flowchart TB
        classDef onchain fill:#0f2027,stroke:#00d4ff,stroke-width:2px,color:#e0f7ff
        classDef offchain fill:#1a0a2e,stroke:#bf5fff,stroke-width:2px,color:#f0e0ff
        classDef decision fill:#0d1f0d,stroke:#39ff14,stroke-width:2px,color:#ccffcc
        classDef result fill:#1f0a0a,stroke:#ff4444,stroke-width:2px,color:#ffe0e0
        classDef phase fill:#111,stroke:#555,stroke-width:1px,color:#aaa,font-style:italic

        %% ─── PHASE 0 ───
        F0(["⚙️ PHASE 0 · Deployment"]):::phase
        F0 --> A["🏛️ Admin deploys smart contract · Voting start/end time · Candidate options · Immutable security parameters"]:::onchain

        %% ─── PHASE 1 ───
        A --> F1(["🔐 PHASE 1 · Registration"]):::phase
        F1 --> B["🎲 Voter locally generates nullifier + secret"]:::offchain
        B --> C["#️⃣ Computes commitment: hash(nullifier, secret)"]:::offchain
        C --> D["📤 Sends commitment to contract on-chain"]:::onchain
        D --> E["🌳 Commitment inserted into Merkle Tree"]:::onchain

        %% ─── PHASE 2 ───
        E --> F2(["🔒 PHASE 2 · Transition"]):::phase
        F2 --> F["❄️ Registration CLOSED · Merkle Root FROZEN"]:::onchain

        %% ─── PHASE 3 ───
        F --> F3(["🧮 PHASE 3 · ZK Proof Generation (off-chain)"]):::phase
        F3 --> G["🗳️ Voter selects their vote choice"]:::offchain
        G --> H["⚡ Browser/client generates Zero-Knowledge Proof · Proves: commitment ∈ MerkleTree · Without revealing: voter identity"]:::offchain

        %% ─── PHASE 4 ───
        H --> F4(["📡 PHASE 4 · Vote Submission"]):::phase
        F4 --> I["🔁 Relayer receives ZK Proof + vote"]:::offchain
        I --> J["📨 Relayer submits tx on-chain · pays gas fees · Voter wallet NOT linked to vote"]:::onchain

        %% ─── PHASE 5 ───
        J --> F5(["✅ PHASE 5 · On-chain Verification"]):::phase
        F5 --> K{{"🔍 Nullifier already used?"}}:::decision
        K -- "Yes → Double vote" --> L["🚫 Transaction REJECTED"]:::result
        K -- "No → Continue" --> M{{"🔬 ZK Proof valid?"}}:::decision
        M -- "Invalid" --> N["🚫 Proof REJECTED"]:::result
        M -- "Valid ✓" --> O["✅ Nullifier marked as spent"]:::onchain

        %% ─── PHASE 6 ───
        O --> F6(["⏱️ PHASE 6 · Weighted Count with Temporal Decay"]):::phase
        F6 --> P["⏰ Contract captures exact tx timestamp"]:::onchain
        P --> Q["📉 Computes vote weight via decay function: w = f(t_vote, t_start, t_end)"]:::onchain
        Q --> R["➕ Adds weighted vote to cumulative tally"]:::onchain
        R --> S{{"⏳ Voting period still active?"}}:::decision
        S -- "Yes" --> F3
        S -- "No → End" --> T["📊 FINAL RESULTS · Public · Auditable · Immutable · Permanently on-chain"]:::result
```