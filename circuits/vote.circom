pragma circom 2.1.6;

include "../node_modules/circomlib/circuits/poseidon.circom";
include "../node_modules/circomlib/circuits/comparators.circom";
include "../node_modules/circomlib/circuits/mux1.circom";

// Merkle tree inclusion proof using Poseidon hash
template MerkleTreeInclusionProof(levels) {
    signal input leaf;
    signal input pathIndices[levels];   // 0 = left, 1 = right
    signal input pathElements[levels];  // sibling hashes
    signal output root;

    component hashers[levels];
    component mux[levels];

    signal hashes[levels + 1];
    hashes[0] <== leaf;

    for (var i = 0; i < levels; i++) {
        // pathIndices must be 0 or 1
        pathIndices[i] * (1 - pathIndices[i]) === 0;

        mux[i] = MultiMux1(2);
        mux[i].c[0][0] <== hashes[i];
        mux[i].c[0][1] <== pathElements[i];
        mux[i].c[1][0] <== pathElements[i];
        mux[i].c[1][1] <== hashes[i];
        mux[i].s <== pathIndices[i];

        hashers[i] = Poseidon(2);
        hashers[i].inputs[0] <== mux[i].out[0];
        hashers[i].inputs[1] <== mux[i].out[1];

        hashes[i + 1] <== hashers[i].out;
    }

    root <== hashes[levels];
}

// Main voting circuit
// Public inputs:  root, nullifierHash, voteChoice
// Private inputs: nullifier, secret, pathElements[], pathIndices[]
template Vote(levels) {
    // Public signals
    signal input root;           // Merkle root of registered commitments
    signal input nullifierHash;  // Hash of nullifier (to prevent double voting)
    signal input voteChoice;     // The voting option chosen (e.g., 0, 1, 2...)

    // Private signals
    signal input nullifier;              // Secret nullifier unique to voter
    signal input secret;                 // Secret known only to voter
    signal input pathElements[levels];   // Merkle proof siblings
    signal input pathIndices[levels];    // Merkle proof path (left/right)

    // 1. Compute commitment = Poseidon(nullifier, secret)
    component commitmentHasher = Poseidon(2);
    commitmentHasher.inputs[0] <== nullifier;
    commitmentHasher.inputs[1] <== secret;

    // 2. Verify Merkle tree membership
    component tree = MerkleTreeInclusionProof(levels);
    tree.leaf <== commitmentHasher.out;
    for (var i = 0; i < levels; i++) {
        tree.pathElements[i] <== pathElements[i];
        tree.pathIndices[i] <== pathIndices[i];
    }

    // 3. Constrain: computed root must match the public root
    root === tree.root;

    // 4. Compute nullifierHash = Poseidon(nullifier) and constrain it
    component nullifierHasher = Poseidon(1);
    nullifierHasher.inputs[0] <== nullifier;
    nullifierHash === nullifierHasher.out;

    // 5. Add voteChoice as a constraint to bind the proof to this specific vote
    //    (square it to create a constraint without requiring a specific value)
    signal voteChoiceSquare;
    voteChoiceSquare <== voteChoice * voteChoice;
}

// Instantiate with Merkle tree depth of 20 (supports up to ~1M voters)
component main {public [root, nullifierHash, voteChoice]} = Vote(20);
