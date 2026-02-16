;; Governance Token - SIP-010 compliant with voting power
;; Implements delegation and vote tracking

;; Traits
(impl-trait 'SP3FBR2AGK5H9QBDH3EEN6DF8EK8JY7RX8QJ5SVTE.sip-010-trait-ft-standard.sip-010-trait)

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_BALANCE (err u101))
(define-constant ERR_INVALID_AMOUNT (err u102))

;; Token metadata
(define-fungible-token governance-token)
(define-data-var token-name (string-ascii 32) "DAO Governance Token")
(define-data-var token-symbol (string-ascii 10) "DAOGOV")
(define-data-var token-decimals uint u6)
(define-data-var token-uri (optional (string-utf8 256)) none)

;; Voting power tracking
(define-map voting-power principal uint)
(define-map delegates principal principal)
(define-map delegation-checkpoints 
  { delegator: principal, block: uint } 
  uint
)

;; SIP-010 Implementation
(define-read-only (get-name)
  (ok (var-get token-name))
)

(define-read-only (get-symbol)
  (ok (var-get token-symbol))
)

(define-read-only (get-decimals)
  (ok (var-get token-decimals))
)

(define-read-only (get-balance (account principal))
  (ok (ft-get-balance governance-token account))
)

(define-read-only (get-total-supply)
  (ok (ft-get-supply governance-token))
)

(define-read-only (get-token-uri)
  (ok (var-get token-uri))
)

(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
  (begin
    (asserts! (is-eq tx-sender sender) ERR_NOT_AUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (ft-transfer? governance-token amount sender recipient))
    ;; Update voting power
    (update-voting-power sender)
    (update-voting-power recipient)
    (match memo m (print m) true)
    (ok true)
  )
)

;; Minting (owner only)
(define-public (mint (amount uint) (recipient principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (ft-mint? governance-token amount recipient))
    (update-voting-power recipient)
    (ok true)
  )
)

;; Delegation
(define-public (delegate (to principal))
  (begin
    (map-set delegates tx-sender to)
    (update-voting-power tx-sender)
    (update-voting-power to)
    (ok true)
  )
)

(define-read-only (get-delegate (account principal))
  (default-to account (map-get? delegates account))
)

;; Voting Power
(define-read-only (get-voting-power (account principal))
  (default-to u0 (map-get? voting-power account))
)

(define-private (update-voting-power (account principal))
  (let
    (
      (balance (ft-get-balance governance-token account))
      (delegate-to (get-delegate account))
    )
    (if (is-eq account delegate-to)
      ;; No delegation - voting power equals balance
      (map-set voting-power account balance)
      ;; Delegated - add to delegate's power
      (begin
        (map-set voting-power account u0)
        (map-set voting-power delegate-to 
          (+ (get-voting-power delegate-to) balance)
        )
      )
    )
    true
  )
)

;; Checkpoint for historical voting power
(define-public (checkpoint)
  (begin
    (map-set delegation-checkpoints
      { delegator: tx-sender, block: block-height }
      (get-voting-power tx-sender)
    )
    (ok block-height)
  )
)

(define-read-only (get-past-votes (account principal) (block uint))
  (default-to u0 
    (map-get? delegation-checkpoints { delegator: account, block: block })
  )
)
