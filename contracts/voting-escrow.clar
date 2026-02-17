;; ============================================
;; Voting Escrow Contract (veToken Model)
;; ============================================
;; Time-weighted voting power based on lock duration
;; Inspired by Curve's veCRV model
;; ============================================

;; Constants
(define-constant ERR-NOT-AUTHORIZED (err u5001))
(define-constant ERR-INVALID-AMOUNT (err u5002))
(define-constant ERR-INVALID-DURATION (err u5003))
(define-constant ERR-LOCK-EXISTS (err u5004))
(define-constant ERR-NO-LOCK (err u5005))
(define-constant ERR-LOCK-NOT-EXPIRED (err u5006))
(define-constant ERR-LOCK-EXPIRED (err u5007))

;; Lock duration constants (in blocks, ~10 min per block)
(define-constant MIN-LOCK-DURATION u4320)    ;; ~30 days
(define-constant MAX-LOCK-DURATION u210240)  ;; ~4 years
(define-constant WEEK u1008)                  ;; ~7 days

;; Data Variables
(define-data-var contract-owner principal tx-sender)
(define-data-var total-locked uint u0)
(define-data-var total-supply uint u0)

;; Lock data structure
(define-map locks principal {
  amount: uint,
  end: uint,
  start: uint
})

;; Historical point for voting power calculation
(define-map user-point-history { user: principal, epoch: uint } {
  bias: int,
  slope: int,
  ts: uint
})

(define-map user-point-epoch principal uint)

;; Slope changes at specific blocks
(define-map slope-changes uint int)

;; ============================================
;; Core Functions
;; ============================================

;; Create a new lock
(define-public (create-lock (amount uint) (unlock-time uint))
  (let (
    (sender tx-sender)
    (current-block block-height)
    (rounded-unlock (round-to-week unlock-time))
  )
    ;; Validations
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (is-none (map-get? locks sender)) ERR-LOCK-EXISTS)
    (asserts! (>= (- rounded-unlock current-block) MIN-LOCK-DURATION) ERR-INVALID-DURATION)
    (asserts! (<= (- rounded-unlock current-block) MAX-LOCK-DURATION) ERR-INVALID-DURATION)
    
    ;; Transfer tokens to contract
    (try! (contract-call? .governance-token transfer amount sender (as-contract tx-sender) none))
    
    ;; Create lock
    (map-set locks sender {
      amount: amount,
      end: rounded-unlock,
      start: current-block
    })
    
    ;; Update totals
    (var-set total-locked (+ (var-get total-locked) amount))
    
    ;; Checkpoint
    (try! (checkpoint sender amount rounded-unlock u0 u0))
    
    (print { event: "lock-created", user: sender, amount: amount, unlock-time: rounded-unlock })
    (ok true)))

;; Increase lock amount
(define-public (increase-amount (additional-amount uint))
  (let (
    (sender tx-sender)
    (lock (unwrap! (map-get? locks sender) ERR-NO-LOCK))
    (current-amount (get amount lock))
    (end-time (get end lock))
  )
    (asserts! (> additional-amount u0) ERR-INVALID-AMOUNT)
    (asserts! (> end-time block-height) ERR-LOCK-EXPIRED)
    
    ;; Transfer additional tokens
    (try! (contract-call? .governance-token transfer additional-amount sender (as-contract tx-sender) none))
    
    ;; Update lock
    (map-set locks sender (merge lock { amount: (+ current-amount additional-amount) }))
    
    ;; Update totals
    (var-set total-locked (+ (var-get total-locked) additional-amount))
    
    ;; Checkpoint
    (try! (checkpoint sender (+ current-amount additional-amount) end-time current-amount end-time))
    
    (print { event: "amount-increased", user: sender, additional: additional-amount })
    (ok true)))

;; Extend lock duration
(define-public (increase-unlock-time (new-unlock-time uint))
  (let (
    (sender tx-sender)
    (lock (unwrap! (map-get? locks sender) ERR-NO-LOCK))
    (amount (get amount lock))
    (old-end (get end lock))
    (rounded-unlock (round-to-week new-unlock-time))
  )
    (asserts! (> old-end block-height) ERR-LOCK-EXPIRED)
    (asserts! (> rounded-unlock old-end) ERR-INVALID-DURATION)
    (asserts! (<= (- rounded-unlock block-height) MAX-LOCK-DURATION) ERR-INVALID-DURATION)
    
    ;; Update lock
    (map-set locks sender (merge lock { end: rounded-unlock }))
    
    ;; Checkpoint
    (try! (checkpoint sender amount rounded-unlock amount old-end))
    
    (print { event: "unlock-extended", user: sender, new-unlock: rounded-unlock })
    (ok true)))

;; Withdraw tokens after lock expires
(define-public (withdraw)
  (let (
    (sender tx-sender)
    (lock (unwrap! (map-get? locks sender) ERR-NO-LOCK))
    (amount (get amount lock))
    (end-time (get end lock))
  )
    (asserts! (<= end-time block-height) ERR-LOCK-NOT-EXPIRED)
    
    ;; Clear lock
    (map-delete locks sender)
    
    ;; Update totals
    (var-set total-locked (- (var-get total-locked) amount))
    
    ;; Transfer tokens back
    (try! (as-contract (contract-call? .governance-token transfer amount tx-sender sender none)))
    
    (print { event: "withdrawn", user: sender, amount: amount })
    (ok amount)))

;; ============================================
;; Voting Power Calculation
;; ============================================

;; Get current voting power for a user
(define-read-only (get-voting-power (user principal))
  (match (map-get? locks user)
    lock (calculate-voting-power (get amount lock) (get end lock))
    u0))

;; Calculate voting power based on amount and time remaining
(define-private (calculate-voting-power (amount uint) (end-time uint))
  (if (<= end-time block-height)
    u0
    (let (
      (time-remaining (- end-time block-height))
      (max-time MAX-LOCK-DURATION)
    )
      ;; Linear decay: voting_power = amount * time_remaining / max_time
      (/ (* amount time-remaining) max-time))))

;; Get voting power at a specific block
(define-read-only (get-voting-power-at (user principal) (target-block uint))
  (match (map-get? locks user)
    lock 
      (if (or (<= (get end lock) target-block) (< target-block (get start lock)))
        u0
        (calculate-voting-power (get amount lock) (get end lock)))
    u0))

;; Get total voting power
(define-read-only (get-total-voting-power)
  (var-get total-supply))

;; ============================================
;; Checkpoint Functions
;; ============================================

(define-private (checkpoint 
  (user principal) 
  (new-amount uint) 
  (new-end uint)
  (old-amount uint)
  (old-end uint))
  (let (
    (current-block block-height)
    (old-voting-power (calculate-voting-power old-amount old-end))
    (new-voting-power (calculate-voting-power new-amount new-end))
  )
    ;; Update total supply
    (var-set total-supply 
      (+ (- (var-get total-supply) old-voting-power) new-voting-power))
    
    ;; Update user epoch
    (let ((epoch (+ (default-to u0 (map-get? user-point-epoch user)) u1)))
      (map-set user-point-epoch user epoch)
      (map-set user-point-history { user: user, epoch: epoch } {
        bias: (to-int new-voting-power),
        slope: (to-int (/ new-amount MAX-LOCK-DURATION)),
        ts: current-block
      }))
    
    (ok true)))

;; ============================================
;; Helper Functions
;; ============================================

;; Round to nearest week
(define-private (round-to-week (ts uint))
  (* (/ ts WEEK) WEEK))

;; Convert uint to int safely
(define-private (to-int (value uint))
  (if (< value u9223372036854775807)
    (to-int value)
    0))

;; ============================================
;; Read-only Functions
;; ============================================

(define-read-only (get-lock-info (user principal))
  (map-get? locks user))

(define-read-only (get-total-locked)
  (var-get total-locked))

(define-read-only (get-lock-end (user principal))
  (match (map-get? locks user)
    lock (some (get end lock))
    none))

(define-read-only (get-user-epoch (user principal))
  (default-to u0 (map-get? user-point-epoch user)))

;; Check if user can vote
(define-read-only (can-vote (user principal))
  (> (get-voting-power user) u0))

;; Get voting power percentage
(define-read-only (get-voting-power-percentage (user principal))
  (let (
    (user-power (get-voting-power user))
    (total-power (var-get total-supply))
  )
    (if (is-eq total-power u0)
      u0
      (/ (* user-power u10000) total-power)))) ;; Returns basis points

;; ============================================
;; Admin Functions
;; ============================================

(define-public (set-owner (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set contract-owner new-owner)
    (ok true)))
