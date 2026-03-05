# ZK Time-Decay Voting System

**Reto 3 — Hackathon Cryptography & Security (UPF 2025)**

Sistema de votación *privacy-preserving* donde el **peso del voto decae linealmente con el tiempo**: votar pronto da más influencia que votar tarde. Se usan **zk-SNARKs (Groth16)** para que nadie pueda vincular un voto con la identidad del votante.

---

## Índice

1. [Estructura del Proyecto](#estructura-del-proyecto)
2. [Requisitos Previos](#requisitos-previos)
3. [Deployment paso a paso en Remix](#deployment-paso-a-paso-en-remix)
4. [Uso del Frontend](#uso-del-frontend)
5. [Relayer (Opcional)](#relayer-opcional)
6. [Flujo Completo del Protocolo](#flujo-completo-del-protocolo)
7. [Registro de Votantes — Detalle Completo](#registro-de-votantes--detalle-completo)
8. [Diseño del Protocolo](#diseño-del-protocolo)
9. [Escenarios y Actores](#escenarios-y-actores)
10. [Modelo de Amenazas (Threat Model)](#modelo-de-amenazas-threat-model)
11. [Primitivas Criptográficas](#primitivas-criptográficas)
12. [Circuito ZK (Circom)](#circuito-zk-circom)

---

## Estructura del Proyecto

```
├── remix/
│   ├── 1_MockVerifier.sol           # Verificador Groth16 mock (siempre devuelve true)
│   ├── 2_PoseidonT3Stub.sol         # Hash Poseidon stub (usa keccak256 % BN128)
│   ├── 3_ZKTimeDecayVoting.sol      # Contrato principal (100% autónomo, sin imports)
│   └── frontend_remix_demo.html     # Frontend completo (MetaMask + Relayer)
├── relayer/
│   ├── server.js                    # Servidor Node.js que retransmite votos
│   ├── package.json                 # Dependencias del relayer
│   └── .env.example                 # Plantilla de variables de entorno
├── circuits/
│   └── vote.circom                  # Circuito ZK de referencia (Circom)
└── readme.md                        # Este archivo
```

---

## Requisitos Previos

| Herramienta | Para qué | Dónde obtenerla |
|---|---|---|
| **MetaMask** | Firmar transacciones, interactuar con Sepolia | [metamask.io](https://metamask.io) |
| **Sepolia ETH** | Pagar gas en testnet | [sepoliafaucet.com](https://sepoliafaucet.com) o [Google Cloud faucet](https://cloud.google.com/application/web3/faucet/ethereum/sepolia) |
| **Remix IDE** | Compilar y desplegar los contratos | [remix.ethereum.org](https://remix.ethereum.org) |
| **Node.js 18+** | Solo si se usa el relayer (opcional) | [nodejs.org](https://nodejs.org) |

### Configurar MetaMask para Sepolia

1. Abrir MetaMask → Redes → **Agregar red** → Seleccionar **Sepolia test network**.
2. Ir a un faucet de Sepolia y solicitar ETH de prueba (se necesitan ~0.05 ETH).
3. Verificar que el saldo aparece en MetaMask.

---

## Deployment paso a paso en Remix

### Paso 1 — Abrir Remix IDE

1. Ir a [https://remix.ethereum.org](https://remix.ethereum.org).
2. En el explorador de archivos (panel izquierdo), crear una carpeta llamada `zk-voting/`.
3. Dentro de esa carpeta, crear 3 archivos copiando el contenido **exacto** de los archivos en `remix/`:
   - `1_MockVerifier.sol`
   - `2_PoseidonT3Stub.sol`
   - `3_ZKTimeDecayVoting.sol`

### Paso 2 — Compilar los contratos

1. Ir a la pestaña **Solidity Compiler** (icono con forma de S en el panel izquierdo).
2. Configurar:
   - **Compiler version**: `0.8.20` (o superior dentro de 0.8.x)
   - **EVM Version**: `paris`
   - Marcar **Enable optimization** → Runs: `200`
3. Compilar cada archivo en orden:
   - Primero `1_MockVerifier.sol`
   - Luego `2_PoseidonT3Stub.sol`
   - Finalmente `3_ZKTimeDecayVoting.sol`
4. Verificar que no hay errores (warning de SPDX se puede ignorar).

### Paso 3 — Conectar MetaMask a Remix

1. Ir a la pestaña **Deploy & Run Transactions** (icono de flecha).
2. En **Environment**, seleccionar **Injected Provider - MetaMask**.
3. MetaMask pedirá conectar — aceptar y asegurarse de estar en **red Sepolia**.
4. La cuenta con Sepolia ETH aparecerá en el campo **Account**.

### Paso 4 — Desplegar el Contrato 1: MockGroth16Verifier

1. En el dropdown de contratos, seleccionar **MockGroth16Verifier** (del archivo `1_MockVerifier.sol`).
2. Hacer clic en **Deploy**.
3. MetaMask pedirá confirmar la transacción → **Confirmar**.
4. Una vez minado, el contrato aparecerá en "Deployed Contracts".
5. **Copiar la dirección del contrato** (hacer clic en el icono de copiar junto al nombre). Ejemplo: `0xABC123...`

### Paso 5 — Desplegar el Contrato 2: PoseidonT3Stub

1. Seleccionar **PoseidonT3Stub** en el dropdown.
2. **Deploy** → Confirmar en MetaMask.
3. **Copiar la dirección** del contrato desplegado. Ejemplo: `0xDEF456...`

### Paso 6 — Desplegar el Contrato 3: ZKTimeDecayVoting

Este es el contrato principal. El constructor necesita 5 parámetros:

| Parámetro | Tipo | Descripción |
|---|---|---|
| `_verifier` | address | La dirección de MockGroth16Verifier (Paso 4) |
| `_hasher` | address | La dirección de PoseidonT3Stub (Paso 5) |
| `_votingStart` | uint256 | Timestamp Unix de inicio de la votación |
| `_votingEnd` | uint256 | Timestamp Unix de fin de la votación |
| `_numChoices` | uint256 | Número de opciones (ej: 3 para opciones 0, 1, 2) |

#### Cómo obtener timestamps Unix

Usar [https://www.unixtimestamp.com/](https://www.unixtimestamp.com/) o ejecutar en la consola del navegador:

```javascript
// Inicio: dentro de 5 minutos
Math.floor(Date.now() / 1000) + 300

// Fin: dentro de 2 horas
Math.floor(Date.now() / 1000) + 7200
```

#### Ejemplo de despliegue

En los campos "Deploy" de Remix, rellenar (separados por coma si Remix lo pide así):

```
_verifier:    0xABC123...   (dirección del Paso 4)
_hasher:      0xDEF456...   (dirección del Paso 5)
_votingStart: 1750000000    (timestamp futuro, inicio de la votación)
_votingEnd:   1750007200    (timestamp de fin, 2 horas después)
_numChoices:  3             (tres opciones: 0, 1, 2)
```

> **Importante:** `_votingStart` debe ser un timestamp **futuro** (posterior al momento actual). El registro de votantes se hace ANTES de que empiece la votación.

1. Rellenar los 5 campos → **Deploy** → Confirmar en MetaMask.
2. **Copiar la dirección** del contrato `ZKTimeDecayVoting`. Esta es la dirección principal.

---

## Uso del Frontend

### Opción A — Modo directo (MetaMask)

1. Abrir el archivo `remix/frontend_remix_demo.html` en un navegador web (doble clic o arrastrar al navegador).
2. En la sección **Configurar Contrato**:
   - Pegar la dirección del contrato `ZKTimeDecayVoting` desplegado.
   - Pegar la dirección del contrato `PoseidonT3Stub`.
   - Dejar Red RPC en `https://rpc.sepolia.org`.
   - Seleccionar modo **MetaMask (directo)**.
3. Hacer clic en **Conectar**.

### Opción B — Modo relayer (mayor privacidad)

1. Primero configurar y ejecutar el relayer (ver [sección Relayer](#relayer-opcional)).
2. En la sección **Configurar Contrato** del frontend:
   - Pegar las direcciones como antes.
   - Seleccionar modo **Relayer**.
   - Escribir la URL del relayer: `http://localhost:3001`.
3. Hacer clic en **Conectar**.

### Flujo en el Frontend

Tras conectar, el frontend muestra automáticamente la **fase actual** de la votación:

#### 1. Fase de Registro (antes de `votingStart`)

- Hacer clic en **Generar Credenciales ZK**.
  - El frontend genera un `nullifier` aleatorio y un `secret` aleatorio.
  - Calcula el `commitment = StubPoseidon(nullifier, secret)`.
  - **GUARDAR LAS CREDENCIALES** que aparecen en el log — son necesarias para votar.
- Hacer clic en **Registrar Votante** para enviar el commitment al contrato.
  - En modo MetaMask: firmará la transacción desde tu wallet.
  - En modo Relayer: el relayer enviará la transacción por ti.
- El admin debe repetir este proceso para cada votante elegible (o cada votante lo hace por su cuenta).

#### 2. Cerrar Registro (solo Admin)

- El admin (la wallet que desplegó el contrato) hace clic en **Cerrar Registro**.
- Esto fija la raíz del Merkle Tree y habilita la fase de votación.
- **Importante:** Una vez cerrado, no se pueden registrar más votantes.

> **Nota:** El registro se debe cerrar **antes** de que llegue el `votingStart`. Si no se cierra, nadie puede votar.

#### 3. Fase de Votación (entre `votingStart` y `votingEnd`)

- La barra de peso muestra el **peso actual del voto** (100% al inicio, decayendo hacia 0%).
- Seleccionar una opción de voto (0, 1, 2...).
- Si se generaron credenciales antes, se usan automáticamente. Si no, pegar el `nullifier` y `secret` guardados.
- Hacer clic en **Enviar Voto**.
  - El frontend genera una proof dummy (compatible con el MockVerifier).
  - El voto se registra con el peso correspondiente al momento del envío.
  - Aparece el hash del nullifier para confirmar que el voto se procesó.

#### 4. Resultados (después de `votingEnd`)

- Hacer clic en **Ver Resultados** para ver el conteo ponderado por opción.
- Se muestra la opción ganadora y los votos ponderados de cada opción.

---

## Relayer (Opcional)

El relayer es un servidor Node.js que recibe los votos de los votantes y los envía a la blockchain usando su propia wallet. Esto oculta la dirección del votante.

### Configuración

```bash
# 1. Entrar al directorio del relayer
cd relayer

# 2. Instalar dependencias
npm install

# 3. Copiar la plantilla de configuración
cp .env.example .env

# 4. Editar .env con los valores reales
```

### Variables de entorno (relayer/.env)

```env
SEPOLIA_RPC_URL=https://rpc.sepolia.org
RELAYER_PRIVATE_KEY=tu_clave_privada_aqui
VOTING_CONTRACT_ADDRESS=0x_direccion_del_contrato_ZKTimeDecayVoting
RELAYER_PORT=3001
```

> **Cómo obtener la clave privada del relayer:** En MetaMask, crear una cuenta nueva dedicada al relayer → Cuenta → Detalles → Exportar clave privada. Enviar Sepolia ETH a esta cuenta para que pueda pagar gas.

### Ejecutar

```bash
node server.js
```

El servidor arranca en `http://localhost:3001`. Endpoints:

| Endpoint | Método | Descripción |
|---|---|---|
| `/api/status` | GET | Estado del contrato y peso actual |
| `/api/register` | POST | Registrar un votante (envía commitment) |
| `/api/relay-vote` | POST | Enviar un voto con ZK proof |
| `/api/results` | GET | Resultados finales de la votación |

---

## Flujo Completo del Protocolo

```
┌──────────────┐     ┌───────────────┐     ┌─────────────────┐     ┌────────────┐
│  DEPLOYMENT  │────▶│  REGISTRO     │────▶│  VOTACIÓN       │────▶│  TALLY     │
│              │     │               │     │                 │     │            │
│ Admin deploy │     │ Votantes      │     │ Votos con       │     │ Resultados │
│ 3 contratos  │     │ generan       │     │ peso temporal   │     │ ponderados │
│ con Remix    │     │ commitments   │     │ + ZK proof      │     │ on-chain   │
└──────────────┘     │ y se registran│     │                 │     └────────────┘
                     │               │     │ Peso = 100% → 0%│
                     │ Admin cierra  │     │ (decaimiento    │
                     │ registro      │     │  lineal)        │
                     └───────────────┘     └─────────────────┘
```

**Timeline de ejemplo:**

```
t=0            t=300s (5min)      t=300s          t=7500s (2h5min)
│              │                  │               │
▼              ▼                  ▼               ▼
Deploy ────── Registro ────── votingStart ────── votingEnd
              (cerrar registro     Peso=100%        Peso=0%
               antes de aquí)      ──────────▶      Tally
```

---

## Registro de Votantes — Detalle Completo

El registro es la fase más importante. Así funciona paso a paso:

### Qué es un "commitment"

Cada votante genera dos números aleatorios secretos:
- **nullifier**: se usará más tarde para derivar un `nullifierHash` que evita el doble voto.
- **secret**: factor adicional de aleatoriedad.

El **commitment** es el hash de estos dos valores:

```
commitment = PoseidonStub(nullifier, secret)
           = keccak256(abi.encodePacked(nullifier, secret)) % SNARK_FIELD
```

El commitment se sube al contrato (público), pero nadie puede revertirlo para obtener el nullifier o el secret.

### Cómo se registra un votante

1. **Generar credenciales** (off-chain, en el frontend):
   - El frontend genera `nullifier` y `secret` aleatorios (256 bits cada uno, reducidos módulo SNARK_FIELD).
   - Calcula el `commitment`.
   - Muestra las credenciales para que el votante las guarde.

2. **Enviar el commitment al contrato** (on-chain):
   - Se llama `registerVoter(commitment)`.
   - El contrato inserta el commitment como hoja en un **Merkle Tree incremental** (profundidad 20 = hasta ~1 millón de votantes).
   - El contrato emite el evento `VoterRegistered(commitment, leafIndex, newRoot)`.
   - Cada inserción actualiza la raíz del Merkle Tree.

3. **Guardar las credenciales**:
   - El votante **debe guardar** su `nullifier` y `secret`. Sin ellos, no podrá votar.
   - Ejemplo de credenciales mostradas por el frontend:
     ```
     Nullifier: 1928374650918273649501827364950...
     Secret:    7362910485736291048573629104857...
     Commitment: 4829175036482917503648291750364...
     ```

### Quién puede registrar votantes

- **Cualquier dirección** puede llamar `registerVoter()` mientras el registro esté abierto.
- En un escenario real, el admin podría agregar un control de acceso (whitelist). En esta demo, está abierto.
- Lo importante es que el votante **nunca revela** su nullifier/secret al registrarse — solo el commitment.

### Cerrar el registro

- Solo el **admin** (la wallet que desplegó el contrato) puede llamar `closeRegistration()`.
- Esto:
  1. Pone `registrationOpen = false`.
  2. Emite `RegistrationClosed(finalRoot, totalRegistered)`.
- Después de cerrar, nadie más puede registrarse y la votación puede comenzar.

### Por qué el Merkle Tree

El Merkle Tree permite al votante **demostrar que está registrado** sin revelar **cuál commitment es el suyo**. Al votar, el votante proporciona un ZK proof que dice:

> "Conozco un `(nullifier, secret)` tal que `Poseidon(nullifier, secret)` es una hoja de este Merkle Tree con raíz `root`, y el `nullifierHash = Poseidon(nullifier)` es este valor."

El contrato verifica la proof y acepta el voto sin saber quién votó.

---

## Diseño del Protocolo

### Fórmula del Peso (Time Decay)

$$w(t) = \frac{T_{end} - t}{T_{end} - T_{start}} \times 10^{18}$$

Donde $t$ = `block.timestamp`.

| Momento | Peso |
|---|---|
| $t = T_{start}$ | $10^{18}$ (100%) |
| $t = T_{start} + \frac{duración}{2}$ | $5 \times 10^{17}$ (50%) |
| $t = T_{end}$ | $0$ (0%) |

Se usa aritmética de punto fijo con 18 decimales (`PRECISION = 1e18`) para evitar truncamiento en Solidity.

El peso mínimo es **5%** (`MIN_WEIGHT = PRECISION / 20`). Votos por debajo de este umbral se rechazan para evitar votos de peso insignificante.

### Inmutabilidad

Los parámetros críticos son `immutable` en el constructor:
- `verifier`, `hasher`, `admin`, `votingStart`, `votingEnd`, `numChoices`

Nadie puede cambiarlos después del despliegue, ni siquiera el admin.

---

## Escenarios y Actores

### Caso de uso: Gobernanza DAO con incentivo de decisión temprana

Un voto que decae con el tiempo tiene sentido en:

- **DAOs**: Incentivar que los miembros participen pronto. Quienes investigan y votan temprano tienen más peso que quienes esperan a ver la tendencia (elimina el efecto *bandwagon*).
- **Presupuestos participativos**: Los vecinos que se informan y votan rápido tienen más influencia.
- **Anti-colusión**: Un adversario que intente coordinar un grupo necesita hacerlo al inicio, cuando hay menos información.

### Actores

| Actor | Rol | Confianza |
|---|---|---|
| **Admin** | Despliega contrato, define parámetros, cierra registro | Semi-trusted: confiamos en la configuración. El contrato limita su poder post-deployment (immutables). |
| **Votantes** | Generan commitments, emiten votos con ZK proof | Honestos-pero-curiosos: siguen el protocolo, pero podrían intentar espiar votos ajenos. |
| **Validadores** | Producen bloques, fijan `block.timestamp` | Semi-adversarios: margen de ~12-15s para manipular timestamps (PoS). |
| **Observadores** | Leen la blockchain, analizan patrones | Adversarios pasivos: intentan desanonimizar votantes. |
| **Relayer** | Envía TX en nombre del votante | Semi-trusted: conoce la proof pero no puede alterarla. |

---

## Modelo de Amenazas (Threat Model)

### 1. Manipulación del `block.timestamp`

**Ataque:** Un validador-votante produce un bloque con timestamp cercano a `votingStart` para obtener mayor peso.

**Mitigación:**
- En Ethereum PoS, el timestamp debe ser estrictamente creciente y dentro de ~12s del slot esperado.
- `MIN_WEIGHT` del 5% impide votos a peso 0.
- Mejora posible: discretizar en épocas (N tramos) en vez de usar segundos exactos.

### 2. Front-running / Análisis del mempool

**Ataque:** Un adversario ve votos en el mempool y usa esa información.

**Mitigación:**
- El `voteChoice` es un input público de la ZK proof (visible en la TX).
- Usar relayer + mempool privado (Flashbots Protect en mainnet). En Sepolia, se acepta como limitación.
- Mejora: cifrar `voteChoice` con esquema commit-reveal.

### 3. Doble votación (replay)

**Ataque:** Reutilizar la misma proof o generar otra con las mismas credenciales.

**Mitigación:** El `nullifierHash = Poseidon(nullifier)` es determinista. El contrato almacena `usedNullifiers[hash] = true` y rechaza duplicados. **Ya mitigado en el diseño.**

### 4. Linkabilidad por análisis de red

**Ataque:** Correlacionar la dirección Ethereum con la identidad del votante.

**Mitigación:** Usar el relayer, que envía la TX desde su propia dirección.

### 5. Admin malicioso

**Ataque:** El admin modifica `votingEnd` o la raíz Merkle post-deploy.

**Mitigación:** Todos los parámetros críticos son `immutable`. El admin solo puede ejecutar `closeRegistration()`.

---

## Primitivas Criptográficas

| Primitiva | Implementación | Propiedad |
|---|---|---|
| **zk-SNARKs (Groth16)** | Circom + snarkjs / MockVerifier (demo) | Zero-Knowledge: verifica validez del voto sin revelar votante. Proof de ~256 bytes. |
| **Poseidon Hash** | PoseidonT3Stub (keccak256 % BN128 para demo) | ZK-friendly, ~8x menos constraints que SHA-256 en circuito aritmético. |
| **Merkle Tree** | Incremental, profundidad 20 (~1M hojas) | Membership proof sin revelar cuál hoja es la del votante. |
| **Nullifier scheme** | `nullifierHash = Poseidon(nullifier)` | Impide doble voto sin revelar identidad. Determinista por votante. |
| **Punto fijo** | `PRECISION = 1e18` | Evita truncamiento de fracciones en Solidity (no tiene floats). |

### ¿Por qué Groth16 y no PLONK o STARKs?

| Criterio | Groth16 | PLONK | STARKs |
|---|---|---|---|
| Tamaño de proof | ~128 bytes | ~400 bytes | ~50-200 KB |
| Gas de verificación | ~200K | ~300K | ~1-2M |
| Trusted Setup | Sí (por circuito) | Universal | No |
| Tooling | Excelente (Circom) | Bueno | Limitado on-chain |

Para un hackathon en Sepolia, Groth16 es óptimo: menor gas, tooling maduro, y el trusted setup es aceptable para un PoC.

### Nota sobre el MockVerifier

En la demo del hackathon, se usa un `MockGroth16Verifier` que siempre devuelve `true`. Esto permite probar todo el flujo sin necesidad de compilar el circuito Circom ni ejecutar la ceremonia de trusted setup. En producción, se reemplazaría por un verificador real generado por snarkjs.

---

## Circuito ZK (Circom)

El archivo `circuits/vote.circom` contiene el circuito de referencia para producción:

```
Template Vote:
  Private inputs: nullifier, secret, pathElements[20], pathIndices[20]
  Public inputs:  root, nullifierHash, voteChoice

  Constraints:
    1. commitment = Poseidon(nullifier, secret)
    2. Merkle proof: commitment es hoja del árbol con raíz 'root'
    3. nullifierHash == Poseidon(nullifier)
    4. voteChoice está vinculado a la proof (no se puede cambiar post-generación)
```

Para compilar el circuito (en producción):

```bash
# Compilar
circom circuits/vote.circom --r1cs --wasm --sym -o build/

# Trusted setup (Phase 1)
snarkjs powersoftau new bn128 15 pot15_0000.ptau -v
snarkjs powersoftau contribute pot15_0000.ptau pot15_0001.ptau --name="First"
snarkjs powersoftau prepare phase2 pot15_0001.ptau pot15_final.ptau

# Phase 2
snarkjs groth16 setup build/vote.r1cs pot15_final.ptau vote_0000.zkey
snarkjs zkey contribute vote_0000.zkey vote_final.zkey --name="Contributor 1"
snarkjs zkey export verificationkey vote_final.zkey verification_key.json

# Exportar verificador Solidity
snarkjs zkey export solidityverifier vote_final.zkey Groth16Verifier.sol
```

---

## Resumen rápido de despliegue

```
1. Remix → Compilar 3 contratos (Solidity 0.8.20, optimizer 200)
2. MetaMask → Conectar a Sepolia con ETH de prueba
3. Deploy MockGroth16Verifier → copiar dirección
4. Deploy PoseidonT3Stub → copiar dirección
5. Deploy ZKTimeDecayVoting(verifier, hasher, start, end, numChoices)
6. Abrir frontend_remix_demo.html → pegar direcciones → conectar
7. Generar credenciales → Registrar votantes → Admin cierra registro
8. Esperar a votingStart → Votar → Votos tempranos pesan más
9. Tras votingEnd → Ver resultados ponderados
```

---

*Hackathon UPF 2025 — Cryptography & Security — Reto 3: Sistema de Votación con Decaimiento Temporal + ZK Privacy*
