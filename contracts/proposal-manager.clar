;; Proposal Manager - DAO Proposal Lifecycle Management
;; Handles creation, voting, and execution of proposals

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u200))
(define-constant ERR_PROPOSAL_NOT_FOUND (err u201))
(define-constant ERR_VOTING_CLOSED (err u202))
(define-constant ERR_ALREADY_VOTED (err u203))
(define-constant ERR_INSUFFICIENT_VOTING_POWER (err u204))
(define-constant ERR_PROPOSAL_NOT_SUCCEEDED (err u205))
(define-constant ERR_TIMELOCK_NOT_PASSED (err u206))
(define-constant ERR_QUORUM_NOT_MET (err u207))

;; Proposal states
(define-constant STATE_PENDING u0)
(define-constant STATE_ACTIVE u1)
(define-constant STATE_SUCCEEDED u2)
(define-constant STATE_DEFEATED u3)
(define-constant STATE_QUEUED u4)
(define-constant STATE_EXECUTED u5)
(define-constant STATE_CANCELLED u6)

;; Configuration
(define-data-var voting-period uint u1440) ;; ~10 days in blocks
(define-data-var timelock-delay uint u144) ;; ~1 day in blocks
(define-data-var quorum-percentage uint u10) ;; 10% of total supply
(define-data-var proposal-threshold uint u100000000) ;; Min tokens to propose

;; Data structures
(define-data-var proposal-count uint u0)

(define-map proposals
  uint
  {
    proposer: principal,
    title: (string-utf8 256),
    description: (string-utf8 4096),
    start-block: uint,
    end-block: uint,
    for-votes: uint,
    against-votes: uint,
    state: uint,
    execution-time: uint
  }
)

(define-map votes
  { proposal-id: uint, voter: principal }
  { support: bool, votes: uint }
)

;; Create proposal
(define-public (create-proposal 
    (title (string-utf8 256)) 
    (description (string-utf8 4096))
  )
  (let
    (
      (proposal-id (+ (var-get proposal-count) u1))
      (start-block (+ block-height u1))
      (end-block (+ start-block (var-get voting-period)))
    )
    ;; Check proposer has enough tokens
    ;; (asserts! (>= (contract-call? .governance-token get-voting-power tx-sender) 
    ;;              (var-get proposal-threshold)) 
    ;;           ERR_INSUFFICIENT_VOTING_POWER)
    
    (map-set proposals proposal-id {
      proposer: tx-sender,
      title: title,
      description: description,
      start-block: start-block,
      end-block: end-block,
      for-votes: u0,
      against-votes: u0,
      state: STATE_ACTIVE,
      execution-time: u0
    })
    
    (var-set proposal-count proposal-id)
    (ok proposal-id)
  )
)

;; Vote on proposal
(define-public (vote (proposal-id uint) (support bool))
  (let
    (
      (proposal (unwrap! (map-get? proposals proposal-id) ERR_PROPOSAL_NOT_FOUND))
      (voter-power u1000000) ;; Simplified - would call governance-token
    )
    ;; Check voting is open
    (asserts! (is-eq (get state proposal) STATE_ACTIVE) ERR_VOTING_CLOSED)
    (asserts! (<= block-height (get end-block proposal)) ERR_VOTING_CLOSED)
    
    ;; Check not already voted
    (asserts! (is-none (map-get? votes { proposal-id: proposal-id, voter: tx-sender }))
              ERR_ALREADY_VOTED)
    
    ;; Record vote
    (map-set votes 
      { proposal-id: proposal-id, voter: tx-sender }
      { support: support, votes: voter-power }
    )
    
    ;; Update vote counts
    (if support
      (map-set proposals proposal-id 
        (merge proposal { for-votes: (+ (get for-votes proposal) voter-power) }))
      (map-set proposals proposal-id 
        (merge proposal { against-votes: (+ (get against-votes proposal) voter-power) }))
    )
    
    (ok true)
  )
)

;; Finalize voting and determine outcome
(define-public (finalize-proposal (proposal-id uint))
  (let
    (
      (proposal (unwrap! (map-get? proposals proposal-id) ERR_PROPOSAL_NOT_FOUND))
    )
    ;; Check voting period ended
    (asserts! (> block-height (get end-block proposal)) ERR_VOTING_CLOSED)
    (asserts! (is-eq (get state proposal) STATE_ACTIVE) ERR_VOTING_CLOSED)
    
    ;; Determine outcome
    (if (> (get for-votes proposal) (get against-votes proposal))
      (map-set proposals proposal-id (merge proposal { state: STATE_SUCCEEDED }))
      (map-set proposals proposal-id (merge proposal { state: STATE_DEFEATED }))
    )
    
    (ok true)
  )
)

;; Queue proposal for execution
(define-public (queue-proposal (proposal-id uint))
  (let
    (
      (proposal (unwrap! (map-get? proposals proposal-id) ERR_PROPOSAL_NOT_FOUND))
      (execution-time (+ block-height (var-get timelock-delay)))
    )
    (asserts! (is-eq (get state proposal) STATE_SUCCEEDED) ERR_PROPOSAL_NOT_SUCCEEDED)
    
    (map-set proposals proposal-id 
      (merge proposal { 
        state: STATE_QUEUED,
        execution-time: execution-time
      })
    )
    
    (ok execution-time)
  )
)

;; Execute proposal
(define-public (execute-proposal (proposal-id uint))
  (let
    (
      (proposal (unwrap! (map-get? proposals proposal-id) ERR_PROPOSAL_NOT_FOUND))
    )
    (asserts! (is-eq (get state proposal) STATE_QUEUED) ERR_PROPOSAL_NOT_SUCCEEDED)
    (asserts! (>= block-height (get execution-time proposal)) ERR_TIMELOCK_NOT_PASSED)
    
    ;; Mark as executed
    (map-set proposals proposal-id (merge proposal { state: STATE_EXECUTED }))
    
    ;; Execute actions would go here
    
    (ok true)
  )
)

;; Cancel proposal (proposer or guardian only)
(define-public (cancel-proposal (proposal-id uint))
  (let
    (
      (proposal (unwrap! (map-get? proposals proposal-id) ERR_PROPOSAL_NOT_FOUND))
    )
    (asserts! (or 
      (is-eq tx-sender (get proposer proposal))
      (is-eq tx-sender CONTRACT_OWNER)
    ) ERR_NOT_AUTHORIZED)
    
    (map-set proposals proposal-id (merge proposal { state: STATE_CANCELLED }))
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals proposal-id)
)

(define-read-only (get-proposal-state (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal (ok (get state proposal))
    ERR_PROPOSAL_NOT_FOUND
  )
)

(define-read-only (get-vote (proposal-id uint) (voter principal))
  (map-get? votes { proposal-id: proposal-id, voter: voter })
)

(define-read-only (get-proposal-count)
  (var-get proposal-count)
)

;; Configuration setters (owner only)
(define-public (set-voting-period (blocks uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (var-set voting-period blocks)
    (ok true)
  )
)

(define-public (set-timelock-delay (blocks uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (var-set timelock-delay blocks)
    (ok true)
  )
)
