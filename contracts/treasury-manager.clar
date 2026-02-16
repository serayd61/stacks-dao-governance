;; Treasury Manager - DAO Fund Management
;; Handles deposits, withdrawals, and spending proposals

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u300))
(define-constant ERR_INSUFFICIENT_FUNDS (err u301))
(define-constant ERR_SPENDING_NOT_FOUND (err u302))
(define-constant ERR_SPENDING_NOT_APPROVED (err u303))
(define-constant ERR_INVALID_AMOUNT (err u304))

;; Treasury state
(define-data-var treasury-balance uint u0)
(define-data-var spending-count uint u0)

;; Spending request states
(define-constant SPENDING_PENDING u0)
(define-constant SPENDING_APPROVED u1)
(define-constant SPENDING_EXECUTED u2)
(define-constant SPENDING_REJECTED u3)

;; Data structures
(define-map spending-requests
  uint
  {
    proposer: principal,
    recipient: principal,
    amount: uint,
    reason: (string-utf8 256),
    state: uint,
    created-at: uint
  }
)

(define-map budget-allocations
  (string-ascii 32)
  uint
)

;; Deposit STX to treasury
(define-public (deposit (amount uint))
  (begin
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (var-set treasury-balance (+ (var-get treasury-balance) amount))
    (ok (var-get treasury-balance))
  )
)

;; Propose spending
(define-public (propose-spending 
    (recipient principal) 
    (amount uint) 
    (reason (string-utf8 256))
  )
  (let
    (
      (spending-id (+ (var-get spending-count) u1))
    )
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (<= amount (var-get treasury-balance)) ERR_INSUFFICIENT_FUNDS)
    
    (map-set spending-requests spending-id {
      proposer: tx-sender,
      recipient: recipient,
      amount: amount,
      reason: reason,
      state: SPENDING_PENDING,
      created-at: block-height
    })
    
    (var-set spending-count spending-id)
    (ok spending-id)
  )
)

;; Approve spending (owner/DAO only)
(define-public (approve-spending (spending-id uint))
  (let
    (
      (spending (unwrap! (map-get? spending-requests spending-id) ERR_SPENDING_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq (get state spending) SPENDING_PENDING) ERR_SPENDING_NOT_APPROVED)
    
    (map-set spending-requests spending-id 
      (merge spending { state: SPENDING_APPROVED })
    )
    (ok true)
  )
)

;; Execute approved spending
(define-public (execute-spending (spending-id uint))
  (let
    (
      (spending (unwrap! (map-get? spending-requests spending-id) ERR_SPENDING_NOT_FOUND))
    )
    (asserts! (is-eq (get state spending) SPENDING_APPROVED) ERR_SPENDING_NOT_APPROVED)
    (asserts! (<= (get amount spending) (var-get treasury-balance)) ERR_INSUFFICIENT_FUNDS)
    
    ;; Transfer funds
    (try! (as-contract (stx-transfer? (get amount spending) tx-sender (get recipient spending))))
    
    ;; Update state
    (var-set treasury-balance (- (var-get treasury-balance) (get amount spending)))
    (map-set spending-requests spending-id 
      (merge spending { state: SPENDING_EXECUTED })
    )
    
    (ok true)
  )
)

;; Reject spending
(define-public (reject-spending (spending-id uint))
  (let
    (
      (spending (unwrap! (map-get? spending-requests spending-id) ERR_SPENDING_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    
    (map-set spending-requests spending-id 
      (merge spending { state: SPENDING_REJECTED })
    )
    (ok true)
  )
)

;; Set budget allocation
(define-public (set-budget (category (string-ascii 32)) (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (map-set budget-allocations category amount)
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-treasury-balance)
  (var-get treasury-balance)
)

(define-read-only (get-spending-request (spending-id uint))
  (map-get? spending-requests spending-id)
)

(define-read-only (get-budget (category (string-ascii 32)))
  (default-to u0 (map-get? budget-allocations category))
)

(define-read-only (get-spending-count)
  (var-get spending-count)
)
