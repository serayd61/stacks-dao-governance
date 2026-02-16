# Stacks DAO Governance

A decentralized autonomous organization (DAO) framework for the Stacks blockchain. Build and deploy your own DAO with on-chain governance, treasury management, and proposal voting.

## Features

- **On-chain Voting**: Token-weighted voting with delegation support
- **Proposal System**: Create, discuss, and execute proposals
- **Treasury Management**: Multi-sig treasury with spending limits
- **Timelock**: Configurable execution delays for security
- **Quorum Requirements**: Minimum participation thresholds
- **Vote Delegation**: Delegate voting power to trusted addresses

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     DAO Governance                          │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │  Governance │  │  Proposal   │  │     Treasury        │  │
│  │    Token    │  │   Manager   │  │     Manager         │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
│         │               │                    │              │
│         └───────────────┼────────────────────┘              │
│                         │                                   │
│              ┌──────────┴──────────┐                        │
│              │   Execution Engine  │                        │
│              │    (with Timelock)  │                        │
│              └─────────────────────┘                        │
└─────────────────────────────────────────────────────────────┘
```

## Smart Contracts

### governance-token.clar
SIP-010 compliant governance token with voting power tracking.

```clarity
;; Core functions
(define-public (mint (amount uint) (recipient principal)))
(define-public (delegate (to principal)))
(define-read-only (get-voting-power (account principal)))
```

### proposal-manager.clar
Handles proposal lifecycle from creation to execution.

```clarity
;; Proposal states: Draft -> Active -> Succeeded/Defeated -> Queued -> Executed
(define-public (create-proposal (title (string-utf8 256)) (description (string-utf8 4096))))
(define-public (vote (proposal-id uint) (support bool)))
(define-public (queue-proposal (proposal-id uint)))
(define-public (execute-proposal (proposal-id uint)))
```

### treasury-manager.clar
Manages DAO funds with spending controls.

```clarity
(define-public (deposit (amount uint)))
(define-public (propose-spending (recipient principal) (amount uint) (reason (string-utf8 256))))
(define-public (execute-spending (spending-id uint)))
```

## Quick Start

### Prerequisites
- Clarinet CLI
- Node.js 18+

### Installation

```bash
git clone https://github.com/serayd61/stacks-dao-governance.git
cd stacks-dao-governance
npm install
```

### Deploy to Testnet

```bash
clarinet deployments generate --testnet
clarinet deployments apply --testnet
```

### Run Tests

```bash
clarinet test
```

## Configuration

Create a `dao-config.json` file:

```json
{
  "name": "My DAO",
  "symbol": "MYDAO",
  "votingPeriod": 1440,
  "timelockDelay": 144,
  "quorumPercentage": 10,
  "proposalThreshold": 100000
}
```

## Usage Examples

### Create a Proposal

```typescript
import { createProposal } from '@stacks-dao/sdk';

await createProposal({
  title: "Increase Treasury Allocation",
  description: "Proposal to increase marketing budget by 10%",
  actions: [
    {
      contract: "treasury-manager",
      function: "set-budget",
      args: ["marketing", 110000]
    }
  ]
});
```

### Vote on Proposal

```typescript
import { vote } from '@stacks-dao/sdk';

await vote({
  proposalId: 1,
  support: true
});
```

### Delegate Voting Power

```typescript
import { delegate } from '@stacks-dao/sdk';

await delegate({
  to: "SP3K8BC0PPEVCV7NZ6QSRWPQ2JE9E5B6N3PA0KBR9"
});
```

## Security Considerations

1. **Timelock**: All proposals have a mandatory delay before execution
2. **Quorum**: Minimum participation required for valid votes
3. **Multi-sig Treasury**: Large withdrawals require multiple signatures
4. **Emergency Actions**: Guardian role for critical situations

## Roadmap

- [x] Core governance contracts
- [x] Proposal voting system
- [x] Treasury management
- [ ] Frontend dashboard
- [ ] Snapshot integration
- [ ] Cross-chain governance
- [ ] Gasless voting (meta-transactions)

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

MIT License - see [LICENSE](LICENSE) for details

## Links

- [Documentation](https://docs.stacks-dao.dev)
- [Discord](https://discord.gg/stacks)
- [Twitter](https://twitter.com/stacksdao)
