;; Timelock - Delayed Execution for DAO Security
;; Ensures all governance actions have a mandatory delay

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u400))
(define-constant ERR_INVALID_DELAY (err u401))
(define-constant ERR_TX_NOT_FOUND (err u402))
(define-constant ERR_TX_NOT_READY (err u403))
(define-constant ERR_TX_EXPIRED (err u404))
(define-constant ERR_TX_ALREADY_EXECUTED (err u405))

;; Configuration
(define-data-var min-delay uint u144)    ;; ~1 day minimum
(define-data-var max-delay uint u4320)   ;; ~30 days maximum
(define-data-var grace-period uint u1440) ;; ~10 days to execute

;; Transaction states
(define-constant TX_QUEUED u0)
(define-constant TX_EXECUTED u1)
(define-constant TX_CANCELLED u2)

;; Data structures
(define-data-var tx-count uint u0)

(define-map queued-transactions
  uint
  {
    target: principal,
    value: uint,
    data: (buff 256),
    eta: uint,           ;; Execution time
    state: uint,
    queued-by: principal
  }
)

;; Queue a transaction
(define-public (queue-transaction 
    (target principal)
    (value uint)
    (data (buff 256))
    (delay uint)
  )
  (let
    (
      (tx-id (+ (var-get tx-count) u1))
      (eta (+ block-height delay))
    )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (>= delay (var-get min-delay)) ERR_INVALID_DELAY)
    (asserts! (<= delay (var-get max-delay)) ERR_INVALID_DELAY)
    
    (map-set queued-transactions tx-id {
      target: target,
      value: value,
      data: data,
      eta: eta,
      state: TX_QUEUED,
      queued-by: tx-sender
    })
    
    (var-set tx-count tx-id)
    (ok { tx-id: tx-id, eta: eta })
  )
)

;; Execute a queued transaction
(define-public (execute-transaction (tx-id uint))
  (let
    (
      (tx (unwrap! (map-get? queued-transactions tx-id) ERR_TX_NOT_FOUND))
      (deadline (+ (get eta tx) (var-get grace-period)))
    )
    (asserts! (is-eq (get state tx) TX_QUEUED) ERR_TX_ALREADY_EXECUTED)
    (asserts! (>= block-height (get eta tx)) ERR_TX_NOT_READY)
    (asserts! (<= block-height deadline) ERR_TX_EXPIRED)
    
    ;; Mark as executed
    (map-set queued-transactions tx-id (merge tx { state: TX_EXECUTED }))
    
    ;; Execute would happen here via contract-call
    
    (ok true)
  )
)

;; Cancel a queued transaction
(define-public (cancel-transaction (tx-id uint))
  (let
    (
      (tx (unwrap! (map-get? queued-transactions tx-id) ERR_TX_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq (get state tx) TX_QUEUED) ERR_TX_ALREADY_EXECUTED)
    
    (map-set queued-transactions tx-id (merge tx { state: TX_CANCELLED }))
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-transaction (tx-id uint))
  (map-get? queued-transactions tx-id)
)

(define-read-only (get-min-delay)
  (var-get min-delay)
)

(define-read-only (get-max-delay)
  (var-get max-delay)
)

(define-read-only (get-grace-period)
  (var-get grace-period)
)

(define-read-only (is-ready (tx-id uint))
  (match (map-get? queued-transactions tx-id)
    tx (and 
      (is-eq (get state tx) TX_QUEUED)
      (>= block-height (get eta tx))
      (<= block-height (+ (get eta tx) (var-get grace-period)))
    )
    false
  )
)

;; Admin functions
(define-public (set-min-delay (delay uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (var-set min-delay delay)
    (ok true)
  )
)

(define-public (set-max-delay (delay uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (var-set max-delay delay)
    (ok true)
  )
)
