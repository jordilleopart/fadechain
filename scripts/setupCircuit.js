/**
 * Circuit Setup Script
 * 
 * Compiles the Circom circuit and generates:
 * 1. R1CS constraint system
 * 2. WASM witness generator
 * 3. Groth16 proving/verification keys (via Powers of Tau ceremony)
 * 4. Solidity verifier contract
 * 
 * Prerequisites:
 * - circom 2.1.6+ installed globally (https://docs.circom.io/getting-started/installation/)
 * - snarkjs installed (npm install snarkjs)
 * 
 * Usage: node scripts/setupCircuit.js
 */

const { execSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const BUILD_DIR = path.join(__dirname, "..", "build", "circuits");
const CIRCUIT_PATH = path.join(__dirname, "..", "circuits", "vote.circom");
const CONTRACTS_DIR = path.join(__dirname, "..", "contracts");

function run(cmd, label) {
  console.log(`\n⏳ ${label}...`);
  console.log(`   $ ${cmd}`);
  execSync(cmd, { stdio: "inherit" });
  console.log(`✅ ${label} — done`);
}

async function main() {
  // Create build directory
  if (!fs.existsSync(BUILD_DIR)) {
    fs.mkdirSync(BUILD_DIR, { recursive: true });
  }

  // Step 1: Compile circuit
  run(
    `circom "${CIRCUIT_PATH}" --r1cs --wasm --sym -o "${BUILD_DIR}"`,
    "Compiling Circom circuit"
  );

  // Step 2: Download Powers of Tau (if not present)
  const ptauPath = path.join(BUILD_DIR, "pot20_final.ptau");
  if (!fs.existsSync(ptauPath)) {
    run(
      `snarkjs powersoftau new bn128 20 "${path.join(BUILD_DIR, "pot20_0000.ptau")}" -v`,
      "Starting Powers of Tau ceremony"
    );
    run(
      `snarkjs powersoftau contribute "${path.join(BUILD_DIR, "pot20_0000.ptau")}" "${path.join(BUILD_DIR, "pot20_0001.ptau")}" --name="hackathon-contribution" -v -e="random entropy for hackathon"`,
      "Contributing to Powers of Tau"
    );
    run(
      `snarkjs powersoftau prepare phase2 "${path.join(BUILD_DIR, "pot20_0001.ptau")}" "${ptauPath}" -v`,
      "Preparing Phase 2"
    );
  } else {
    console.log("✅ Powers of Tau file already exists, skipping...");
  }

  // Step 3: Generate zkey (Groth16 setup)
  const r1csPath = path.join(BUILD_DIR, "vote.r1cs");
  const zkeyInitPath = path.join(BUILD_DIR, "vote_0000.zkey");
  const zkeyFinalPath = path.join(BUILD_DIR, "vote_final.zkey");

  run(
    `snarkjs groth16 setup "${r1csPath}" "${ptauPath}" "${zkeyInitPath}"`,
    "Groth16 setup (zkey generation)"
  );

  run(
    `snarkjs zkey contribute "${zkeyInitPath}" "${zkeyFinalPath}" --name="hackathon" -v -e="more random entropy"`,
    "Contributing to zkey"
  );

  // Step 4: Export verification key
  const vkeyPath = path.join(BUILD_DIR, "verification_key.json");
  run(
    `snarkjs zkey export verificationkey "${zkeyFinalPath}" "${vkeyPath}"`,
    "Exporting verification key"
  );

  // Step 5: Export Solidity verifier
  const verifierPath = path.join(CONTRACTS_DIR, "Groth16Verifier.sol");
  run(
    `snarkjs zkey export solidityverifier "${zkeyFinalPath}" "${verifierPath}"`,
    "Generating Solidity verifier contract"
  );

  console.log("\n🎉 Circuit setup complete!");
  console.log(`   R1CS:        ${r1csPath}`);
  console.log(`   WASM:        ${path.join(BUILD_DIR, "vote_js", "vote.wasm")}`);
  console.log(`   ZKey:        ${zkeyFinalPath}`);
  console.log(`   VKey:        ${vkeyPath}`);
  console.log(`   Verifier:    ${verifierPath}`);
}

main().catch((err) => {
  console.error("❌ Error:", err.message);
  process.exit(1);
});
